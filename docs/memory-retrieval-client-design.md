# 记忆检索 — 客户端设计（服务端已实现，客户端待开发）

> 服务端已在 `islelog-back` 仓库实现并测试通过（`go build`/`go test ./...` 通过），
> 权威接口文档见本仓库 `server-API.md` 的"记忆检索"一节，本文档只覆盖 Flutter 客户端
> 要新增/修改的部分，字段名以 `server-API.md` 为准。
>
> **上线前提**：NAS GPU 上的 embedding 服务（`AI_LOCAL_EMBEDDING_BASE_URL` 等）尚未
> 部署，部署前这三个接口对 `LOCAL_EMBEDDING` 全部返回未启用（503 / 空结果）。客户端
> 开发和联调可以先针对"未启用"的置灰/空态分支来做，不必等 NAS 侧就绪。
>
> 三个新增服务端接口（均为 IsleLog 扩展，main 分支不适用，已实现）：
> - `POST /api/v1/ai/memory-search` — 自然语言问答，返回 answer + sources
> - `GET /api/v1/memos/:memo/related-memories` — 相关记忆，纯相似度，无需 LLM
> - `POST /api/v1/ai/on-this-day-compare` — 往年今日 AI 对照

---

## 一、总体原则

- 三个功能都是"在线增强"：`GET /api/v1/ai/providers` 里 `LOCAL_EMBEDDING` 不可用时，
  相关功能整体置灰并给出提示，不做离线兜底、不缓存"假答案"。
- **无依据 ≠ 报错**：`insufficientEvidence:true` / `relatedMemos:[]` 是正常的空结果，
  UI 用明确的空态文案呈现（"没有找到相关日记"），不要走错误提示的视觉样式。
- 涉及 DEEPSEEK 云端的请求，复用编辑器里标签建议/润色已有的"本次授权切云端"确认弹窗，
  不新做一套 UI。

## 二、功能一：记忆检索问答

新增入口：建议放在主页顶部搜索入口旁边，或者作为现有搜索页的一个 Tab（"关键词搜索" /
"AI 问答"），复用现有搜索页的导航结构，不单独开一个 Tab 占底部导航位。

交互：
1. 输入框 + 发送按钮，输入自然语言问题。
2. 请求中显示加载态（模型推理有延迟，尤其 LOCAL 模型），可考虑显示"正在检索相关日记…"
   的过程提示，而不是纯转圈——因为流程分两步（先检索再生成），用户能感知到在做什么。
3. 返回后：
   - `insufficientEvidence:true` → 展示空态插画/文案，可选："换个问法试试"提示。
   - 否则展示 AI 回答文本 + 下方"来源"横向卡片列表（`sources` 数组），每张卡片显示
     日期 + 正文片段，点击跳转对应 memo 详情页。
   - `indexIncomplete:true` → 在回答上方加一行小字提示"部分日记尚未完成索引，结果可能
     不全"，不阻塞展示已有结果。
4. Provider 选择：默认本地，界面上一个不起眼的"使用云端模型（更准确）"选项，点击后走
   现有云端授权确认弹窗，确认后本次请求带 `provider=DEEPSEEK, cloudConsent=true`。

## 三、功能二：详情页"相关记忆"

位置：`memo_detail_page`，正文和附件展示之后、评论区之前，新增一个区块。

交互：
- 页面打开时懒加载调用 `GET /memos/:memo/related-memories?limit=5`（不阻塞主内容渲染）。
- `pending:true` → 显示"正在分析关联记忆…"占位（不长期存在，纯粹是索引任务还没跑到这条
  memo，用户下次打开一般就有了，不需要轮询）。
- 结果为空且非 pending → 整个区块不渲染，不留空盒子。
- 有结果 → 2～5 张紧凑卡片，展示日期 + 片段 + `matchReason` 标签（服务端生成的短标签，
  如"地点相近 · 标签重合"，直接展示即可，不需要客户端二次加工）。点击跳转对应详情页。

## 四、功能三："往年今日" AI 对照

位置：`on_this_day` 模块，每条历史条目下方新增一个可展开的"AI 对照"入口（按钮，非自动
展开/自动请求）。

交互：
- 用户点击"查看 AI 对照"才发起 `POST /api/v1/ai/on-this-day-compare`（同一天可能有多条
  历史年份的记录，每条各自独立触发，不要一次性把当天所有历史条目都批量请求一遍）。
- 展示两段：`past.summary`（当时在意什么）、`now`（现在发生了什么变化）。
- `now.available:false` → 该部分展示"最近没有记录，暂时无法对照"文案，不展示"现在"标题
  下的空内容。
- 同样支持云端授权切换，同问答功能。

## 五、待办 / 依赖

- 服务端三个接口及 `ai/providers` 的 `LOCAL_EMBEDDING` 项已实现，客户端可以开始对接。
- NAS GPU 上的 embedding 服务还未部署，联调真实检索效果前需要先完成这一步（见
  `memory-retrieval-spec.md` 的开放问题一）。
- 客户端本地无需新增 Isar 模型（这三个功能都是"查询即得"，不需要离线缓存问答历史；
  如果后续要支持"问答历史列表"，再评估是否需要新表）。
- API 封装位置：`lib/services/api/memos_api_service.dart` 新增三个方法；调用方分别在
  新的问答页面、`memo_detail_page.dart`、`features/on_this_day/`。
