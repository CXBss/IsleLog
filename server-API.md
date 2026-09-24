# IsleLog Server API 文档

> 所有接口均需要认证（Bearer Token 或 Access Token），除非特别说明。
>
> 图例：
> - **[Memos 兼容]** — 与 Memos v0.25 API 完全兼容，客户端无需修改
> - **[IsleLog 扩展]** — IsleLog 新增或扩展的接口，Memos 客户端不感知

---

## 认证

### 登录
`POST /api/v1/auth/signin` **[Memos 兼容]**

**请求体**
```json
{ "username": "alice", "password": "secret" }
```

**响应**
```json
{ "token": "<JWT>" }
```

---

### 注册
`POST /api/v1/auth/signup` **[Memos 兼容]**

首个用户无需认证，自动成为 ADMIN；此后只有 ADMIN 可创建新用户。

**请求体**
```json
{ "username": "alice", "password": "secret" }
```

---

### 获取当前用户
`GET /api/v1/auth/me` **[Memos 兼容]**

**响应**
```json
{
  "name": "users/123",
  "username": "alice",
  "role": "ADMIN"
}
```

---

## Memo（日记）

### 列表
`GET /api/v1/memos` **[Memos 兼容]**

| 参数 | 类型 | 说明 |
|------|------|------|
| `pageSize` | int | 每页数量，默认 100 |
| `pageToken` | string | 游标，上一页最后一条 ID |
| `state` | string | `ARCHIVED` 返回归档，不传返回正常 |
| `filter` | string | 仅支持 `updated_ts >= <unix_ts>` 格式（增量同步） |

**响应**
```json
{
  "memos": [ /* Memo 对象数组 */ ],
  "nextPageToken": "123456"
}
```

---

### 创建
`POST /api/v1/memos` **[Memos 兼容]**

**请求体**
```json
{
  "content": "今天天气不错 #日记",
  "visibility": "PRIVATE",
  "createTime": "2026-01-01T10:00:00Z",
  "attachments": [{ "name": "attachments/456" }],
  "location": { "placeholder": "上海", "latitude": 31.23, "longitude": 121.47 }
}
```

> `location`、`createTime` 为 IsleLog 扩展字段，Memos 客户端可忽略。

---

### 获取单条
`GET /api/v1/memos/:id` **[Memos 兼容]**

ID 也可以是评论 ID，兼容 Memos 客户端查询评论详情。

---

### 更新
`PATCH /api/v1/memos/:id` **[Memos 兼容]**

支持 `?updateMask=field1,field2` 指定更新字段，不传则更新请求体中所有存在的字段。

| 字段 | 说明 |
|------|------|
| `content` | 正文 |
| `visibility` | `PRIVATE` / `PROTECTED` / `PUBLIC` |
| `state` | `NORMAL` / `ARCHIVED` |
| `pinned` | bool |
| `mood` | int，心情枚举 **[IsleLog 扩展]** |
| `weather` | int，天气枚举 **[IsleLog 扩展]** |
| `location` | `{ placeholder, latitude, longitude }` **[IsleLog 扩展]** |
| `displayTime` | RFC3339，展示时间 **[IsleLog 扩展]** |
| `createTime` | RFC3339，Memos 客户端用此字段改时间，服务端映射到 `display_ts` **[兼容处理]** |
| `attachments` | 附件列表，全量替换 |

---

### 删除
`DELETE /api/v1/memos/:id` **[Memos 兼容]**

软删除（`row_status=DELETED`）。ID 也可以是评论 ID，兼容 Memos 客户端删除评论。

---

## 评论

### 评论列表
`GET /api/v1/memos/:id/comments` **[Memos 兼容]**

**响应**
```json
{ "memos": [ /* 评论以 Memo 格式返回 */ ] }
```

---

### 创建评论
`POST /api/v1/memos/:id/comments` **[Memos 兼容]**

**请求体**
```json
{ "content": "评论内容" }
```

---

### 更新评论
`PATCH /api/v1/comments/:id` **[IsleLog 扩展]**

**请求体**
```json
{
  "content": "修改后的评论",
  "location": "上海",
  "latitude": 31.23,
  "longitude": 121.47
}
```

---

## Memo 版本历史

### 版本列表
`GET /api/v1/revisions/:id` **[IsleLog 扩展]**

返回指定 memo（或文章）的所有变更版本，不含 diff 详情。

**响应**
```json
{
  "revisions": [
    {
      "name": "memos/123/revisions/1",
      "version": 1,
      "changedFields": ["content", "visibility"],
      "createTime": "2026-01-01T10:00:00Z"
    }
  ]
}
```

---

### 版本详情
`GET /api/v1/revisions/:id/:version` **[IsleLog 扩展]**

返回指定版本的字段变更详情。

**响应**
```json
{
  "name": "memos/123/revisions/1",
  "version": 1,
  "createTime": "2026-01-01T10:00:00Z",
  "details": [
    {
      "fieldName": "content",
      "oldValue": null,
      "newValue": null,
      "diff": [ { "op": 0, "text": "不变部分" }, { "op": 1, "text": "新增部分" }, { "op": -1, "text": "删除部分" } ]
    },
    {
      "fieldName": "visibility",
      "oldValue": "PRIVATE",
      "newValue": "PUBLIC",
      "diff": null
    },
    {
      "fieldName": "parent_folder",
      "oldValue": "{\"id\":\"111\",\"name\":\"旧文件夹\"}",
      "newValue": "{\"id\":\"222\",\"name\":\"新文件夹\"}",
      "diff": null
    }
  ]
}
```

> `diff.op`：`0` 不变，`1` 新增，`-1` 删除。

---

## 附件

**附件响应结构**
```json
{
  "name": "attachments/456",
  "createTime": "2026-01-01T10:00:00Z",
  "filename": "photo.jpg",
  "type": "image/jpeg",
  "size": 102400,
  "externalLink": "/file/attachments/456/photo.jpg",
  "memo": "memos/123"
}
```
> `memo` 字段不存在表示附件尚未关联任何 memo。`content` 字段仅上传时传入，响应中不返回。

---

### 附件列表
`GET /api/v1/attachments` **[Memos 兼容]**

| 参数 | 类型 | 说明 |
|------|------|------|
| `pageSize` | int | 每页数量，默认 50，最大 1000 |
| `pageToken` | string | 分页游标（暂未实现，预留） |

**响应**
```json
{ "attachments": [ /* 附件对象数组 */ ] }
```

---

### 上传附件
`POST /api/v1/attachments` **[Memos 兼容]**

**请求体**
```json
{
  "filename": "photo.jpg",
  "type": "image/jpeg",
  "content": "<base64 编码的文件内容>",
  "memo": "memos/123"
}
```
> `memo` 可选，传入则上传后直接关联到对应 memo。

---

### 获取附件
`GET /api/v1/attachments/:id` **[Memos 兼容]**

---

### 更新附件
`PATCH /api/v1/attachments/:id` **[Memos 兼容]**

**请求体**
```json
{
  "filename": "new-name.jpg",
  "memo": "memos/123"
}
```
> `memo` 传空字符串解除关联，传 `"memos/123"` 重新绑定。

---

### 删除附件
`DELETE /api/v1/attachments/:id` **[Memos 兼容]**

同时删除磁盘文件。

---

### 列出 Memo 的附件
`GET /api/v1/memos/:id/attachments` **[Memos 兼容]**

**响应**
```json
{ "attachments": [ /* 附件对象数组 */ ] }
```

---

### 设置 Memo 的附件
`PATCH /api/v1/memos/:id/attachments` **[Memos 兼容]**

全量替换 memo 关联的附件列表（先解除旧关联，再绑定新列表）。

**请求体**
```json
{
  "name": "memos/123",
  "attachments": [
    { "name": "attachments/456" },
    { "name": "attachments/789" }
  ]
}
```

---

### 下载附件
`GET /file/attachments/:id/:filename` **[Memos 兼容]**

需要认证。直接返回文件内容。

---

## 用户

### 用户统计
`GET /api/v1/users/:id/getStats` **[Memos 兼容]**

**响应**
```json
{
  "name": "users/123",
  "memoDisplayTimestamps": ["2026-01-01T00:00:00Z"],
  "tagCount": { "日记": 10, "技术": 5 },
  "pinnedMemos": ["memos/456"],
  "totalMemoCount": 100
}
```

---

### Access Token 列表
`GET /api/v1/users/:id/accessTokens` **[Memos 兼容]**

---

### 创建 Access Token
`POST /api/v1/users/:id/accessTokens` **[Memos 兼容]**

**请求体**
```json
{ "description": "Flutter 客户端", "expiresAt": "2027-01-01T00:00:00Z" }
```

**响应**
```json
{
  "name": "users/123/accessTokens/789",
  "accessToken": "isle_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "description": "Flutter 客户端",
  "expiresAt": "2027-01-01T00:00:00Z"
}
```

> `accessToken` 明文只返回一次，请妥善保存。

---

### 删除 Access Token
`DELETE /api/v1/users/:id/accessTokens/:tokenId` **[Memos 兼容]**

---

## 文章

> 底层复用 `memos` 表（`type='ARTICLE'`），与日记完全独立的接口集。

### 文章列表
`GET /api/v1/articles` **[IsleLog 扩展]**

参数与 `GET /api/v1/memos` 相同。

**响应**
```json
{
  "articles": [ /* Article 对象数组 */ ],
  "nextPageToken": "123456"
}
```

---

### 创建文章
`POST /api/v1/articles` **[IsleLog 扩展]**

**请求体**
```json
{
  "title": "文章标题",
  "content": "正文内容...",
  "visibility": "PRIVATE",
  "parent": "folders/111",
  "attachments": [{ "name": "attachments/456" }]
}
```

> `parent` 为文件夹资源名，传 `null` 或不传表示放在根目录。

---

### 获取文章
`GET /api/v1/articles/:id` **[IsleLog 扩展]**

---

### 更新文章
`PATCH /api/v1/articles/:id` **[IsleLog 扩展]**

支持 `?updateMask=field1,field2`。

| 字段 | 说明 |
|------|------|
| `title` | 文章标题 |
| `content` | 正文 |
| `visibility` | `PRIVATE` / `PROTECTED` / `PUBLIC` |
| `state` | `NORMAL` / `ARCHIVED` |
| `pinned` | bool |
| `displayTime` | RFC3339 |
| `parent` | 文件夹资源名（`folders/123`），传空字符串或 `null` 移到根目录 |
| `attachments` | 附件列表，全量替换 |

> `parent` 变化会记录到版本历史，`fieldName=parent_folder`，`oldValue`/`newValue` 格式为 `{"id":"...","name":"..."}`。

---

### 删除文章
`DELETE /api/v1/articles/:id` **[IsleLog 扩展]**

软删除。

---

## 文件夹

### 文件夹列表
`GET /api/v1/folders` **[IsleLog 扩展]**

返回当前用户的所有文件夹，按名称排序。

**响应**
```json
{
  "folders": [
    {
      "name": "folders/111",
      "title": "技术笔记",
      "parent": null,
      "createTime": "2026-01-01T00:00:00Z",
      "updateTime": "2026-01-01T00:00:00Z"
    }
  ]
}
```

---

### 创建文件夹
`POST /api/v1/folders` **[IsleLog 扩展]**

**请求体**
```json
{ "title": "技术笔记", "parent": null }
```

---

### 获取文件夹
`GET /api/v1/folders/:id` **[IsleLog 扩展]**

---

### 更新文件夹
`PATCH /api/v1/folders/:id` **[IsleLog 扩展]**

**请求体**
```json
{ "title": "新名称", "parent": "folders/222" }
```

> `parent` 传空字符串或 `null` 移到根目录。不可将文件夹设为自身的子级。

---

### 删除文件夹
`DELETE /api/v1/folders/:id` **[IsleLog 扩展]**

删除后：子文件夹的 `parent` 置为 `null`（提升到根目录）；文件夹内文章的 `parent` 同样置为 `null`。

---

## 事件串

> 仅适用于 IsleLog 自建服务，不属于标准 Memos v0.25 API。

事件串把跨多篇日记的同一件事串成有序时间线。成员按日记的 `displayTime` 升序排列；
`memberCount`、`startedTime`、`lastTime` 均由服务端查询时计算。

### 列表

`GET /api/v1/threads`

可选参数 `status`：`ACTIVE` 或 `RESOLVED`。按 `updateTime` 倒序返回，响应为
`{"threads": [Thread]}`，列表不包含成员详情。

### 创建与更新

`POST /api/v1/threads` 请求体：
`{"title":"工位蛐蛐","summary":"","status":"ACTIVE","memos":["memos/1001"]}`。
`title` 必填且不可为空；不属于当前用户或已删除的日记会被忽略；传入 `summary` 时
`summarySource` 记为 `MANUAL`。

`status` 可选，取值 `ACTIVE`（默认）/ `RESOLVED`，其他值返回 400。**离线客户端必须
在创建时带上该字段**：事件串可能在首次推送前就被标记完结，若创建时丢失状态，服务端会
存成 `ACTIVE`，下一轮 pull 便把本地的完结标记覆盖掉。

`PATCH /api/v1/threads/:id` 可更新 `title`、`summary`、`status`（`ACTIVE` / `RESOLVED`）。
一旦手动传入 `summary`，`summarySource` 会变为 `MANUAL`。

### 成员与删除

`GET /api/v1/threads/:id` 返回事件串及其 `members`。

`PUT /api/v1/threads/:id/members` 请求体：`{"memos":["memos/1001","memos/1002"]}`，
原子地全量替换成员，方便离线客户端幂等重试。成员变更只更新事件串本身，不更新日记时间。

`DELETE /api/v1/threads/:id` 软删除事件串，保留成员关系以便恢复。

### Thread 响应结构

```json
{
  "name": "threads/123",
  "title": "工位蛐蛐",
  "summary": "工位附近有蛐蛐叫",
  "summarySource": "AI",
  "status": "ACTIVE",
  "memberCount": 4,
  "startedTime": "2026-08-11T09:00:00Z",
  "lastTime": "2026-08-13T22:00:00Z",
  "createTime": "2026-08-11T09:30:00Z",
  "updateTime": "2026-08-13T22:05:00Z",
  "members": [{"memo":"memos/1001","snippet":"工位附近有蛐蛐在叫","displayTime":"2026-08-11T09:00:00Z"}]
}
```

`members` 仅在单条查询和设置成员时返回；成员数为零时不返回起止时间。

## 事件串 AI 辅助

> 仅适用于 IsleLog 自建服务。每天凌晨 4 点跑一次批处理：先重算「脏」事件串的简介，
> 再为待分析的日记产出归属建议。后台任务**硬编码使用 LOCAL 模型**，绝不上云。
> AI 只写 `thread_suggestions` 与 `threads.summary`，永不修改事件串成员。

### 状态

`GET /api/v1/ai/thread-status` **[IsleLog 扩展]**

```json
{
  "enabled": true,
  "providerAvailable": true,
  "pendingMemos": 3,
  "dirtyThreads": 1,
  "lastRunTime": "2026-08-24T04:00:12Z",
  "lastRunError": ""
}
```

`lastRunTime` 在从未运行过时不输出。

### 开关

`PATCH /api/v1/ai/thread-settings` **[IsleLog 扩展]**

请求体 `{"enabled": false}`。关闭后夜间批次对该用户完全不运行，`pendingMemos` 会持续累积但不消耗模型。

### 立即执行

`POST /api/v1/ai/thread-batch:run` **[IsleLog 扩展]**

立即跑一遍批次，效果与夜间批次一致。本地模型不可用时返回 503。

### 建议列表

`GET /api/v1/thread-suggestions?status=PENDING` **[IsleLog 扩展]**

```json
{
  "suggestions": [
    {
      "name": "thread-suggestions/77",
      "memo": "memos/1001",
      "thread": "threads/20",
      "memoSnippet": "今晚又听到蛐蛐了",
      "threadTitle": "工位蛐蛐",
      "confidence": 0.86,
      "reason": "同样在讲工位的蛐蛐",
      "status": "PENDING",
      "createTime": "2026-08-24T04:00:12Z"
    }
  ]
}
```

按置信度倒序。**置信度低于 0.7 的匹配结果直接丢弃、不入库**，因此列表中不会出现低置信度项。
`memo` 或 `thread` 已被软删除的建议不会返回。

### 修改建议状态

`PATCH /api/v1/thread-suggestions/:id` **[IsleLog 扩展]**

请求体 `{"status": "ACCEPTED"}` 或 `{"status": "DISMISSED"}`。

> **接受建议不会写入事件串成员。** 服务端只记录状态，成员写入由客户端走
> `PUT /threads/:id/members` 完成，避免两个写入方互相覆盖。
>
> 同一 `(memo, thread)` 组合在库中只存在一行：用户忽略之后，再怎么编辑正文
> 也不会重新收到同一条建议。

### 事件串字段变化

`PATCH /api/v1/threads/:id` 新增两个字段：

| 字段 | 说明 |
|------|------|
| `summarySource` | `AI` / `MANUAL`，简介来源，仅供展示 |
| `summaryLocked` | bool，为 true 时 AI 不再改写该简介 |

服务端**不再从「请求里是否带 summary」推断来源**，两者都必须由客户端显式声明。
Thread 响应结构相应新增 `summaryLocked`。

---

## 变更日志（增量同步）

> 用于客户端增量同步。客户端全量同步完成后保存最新的 `changeId` 作为游标，下次启动时拉取 `id > changeId` 的变更，再按 `entity`/`entityId` 拉取对应实体的最新数据。
>
> **降级策略**：若增量变更条数 ≥ 300，客户端应放弃增量同步，改为全量同步。

### 获取最新一条变更
`GET /api/v1/changelogs/latest` **[IsleLog 扩展]**

全量同步完成后调用，将返回的 `id` 保存为后续增量同步的游标。

**响应**
```json
{
  "changelog": {
    "id": 987654322,
    "entity": "memo",
    "entityId": "memos/123",
    "action": "UPDATE",
    "createTime": "2026-04-07T10:00:00Z"
  }
}
```

> 若无任何变更记录，返回 `{ "changelog": null }`，客户端游标存 `0`（`-1` 表示「从未全量同步过」，会触发全量）。
>
> 客户端应在全量拉取**开始前**调用本接口，拉取结束后再保存游标，避免漏掉拉取期间产生的变更。

---

### 获取变更列表
`GET /api/v1/changelogs` **[IsleLog 扩展]**

传入上次同步游标，返回所有 `id > sinceId` 的变更，按 `id` 升序排列，客户端可顺序消费，最后一条的 `id` 即为新游标。

| 参数 | 类型 | 说明 |
|------|------|------|
| `sinceId` | int64 | 上次同步保存的游标，传 `-1` 或 `0` 返回全量 |

**响应**
```json
{
  "total": 2,
  "changelogs": [
    {
      "id": 987654321,
      "entity": "attachment",
      "entityId": "attachments/456",
      "action": "CREATE",
      "createTime": "2026-04-07T09:00:00Z"
    },
    {
      "id": 987654322,
      "entity": "memo",
      "entityId": "memos/123",
      "action": "UPDATE",
      "createTime": "2026-04-07T10:00:00Z"
    }
  ]
}
```

> `action` 取值：`CREATE` / `UPDATE` / `DELETE`。`entity` 取值：`memo` / `article` / `folder` / `comment` / `attachment` / `thread`。

> `entity=article` 时，`entityId` 格式为 `articles/{id}`，用 `GET /api/v1/articles/{id}` 拉取；注意文章响应里的 `name` 是 `memos/{id}`，客户端比对本地文章时要换算。
>
> `entity=folder` 时，`entityId` 格式为 `folders/{id}`，用 `GET /api/v1/folders/{id}` 拉取。
>
> 附件关联变化（`PATCH /memos/{id}/attachments` 列表有增删、`PATCH /attachments/{id}` 改名或换绑、`DELETE /attachments/{id}`）除 `attachment` 记录外，还会给归属的日记/文章各追加一条 `memo`/`article` 的 `UPDATE`，客户端只需关注这两类实体。
>
> 删除文件夹时，数据库会把子文件夹和子文章挪到根目录；服务端会为它们各追加一条 `folder`/`article` 的 `UPDATE`。

> `entity=thread` 时，`entityId` 格式为 `threads/{id}`，用 `GET /api/v1/threads/{id}` 拉取，其响应包含全部成员。
>
> `entity=comment` 时，`entityId` 格式为 `memos/{id}`，直接用 `GET /api/v1/memos/{id}` 拉取。
>
> 客户端判断 `total >= 300` 时放弃增量，直接走全量同步。

---

## AI 编辑辅助

> **仅适用于 IsleLog 自建服务**，不属于标准 Memos v0.25 API；标准 Memos 服务端返回 404。
>
> 需要认证。AI 能力依赖外部模型服务，通过服务端环境变量配置：`AI_LOCAL_*`（私有本地模型，如 llama.cpp 部署的 Qwen）和 `AI_DEEPSEEK_*`（云端 DeepSeek）。未配置时对应 Provider 为未启用状态。
>
> **隐私规则：**
> - `LOCAL` 调用失败不会自动转发 `DEEPSEEK`，任何错误都不会切换模型。
> - `cloudConsent` 仅对当前请求有效，服务端不持久化该授权。
> - AI 接口不会直接修改 memo 或 article，仅返回建议内容供客户端确认。

### Provider 状态
`GET /api/v1/ai/providers` **[IsleLog 扩展]**

固定返回 `LOCAL`、`DEEPSEEK` 两项。结果有 10 秒缓存。

**响应**
```json
[
  {
    "name": "LOCAL",
    "enabled": true,
    "available": true,
    "model": "qwen-local",
    "contextLength": 32768,
    "checkedAt": "2026-07-31T10:00:00Z"
  },
  {
    "name": "DEEPSEEK",
    "enabled": false,
    "available": false,
    "model": "",
    "contextLength": 0,
    "checkedAt": "2026-07-31T10:00:00Z"
  }
]
```

> `enabled=false` 表示服务端未配置该 Provider；`enabled=true, available=false` 表示已配置但健康检查失败（暂时离线）。`message` 仅在异常时输出。

---

### 标签建议
`POST /api/v1/ai/tag-suggestions` **[IsleLog 扩展]**

**请求体**
```json
{
  "content": "今天修复了同步冲突的问题",
  "existingTags": [{ "name": "工作", "count": 12 }],
  "provider": "LOCAL",
  "cloudConsent": false
}
```

| 字段 | 说明 |
|------|------|
| `content` | 正文，必填非空 |
| `existingTags` | 已有标签及使用次数（最多 1000 个，单个名称最长 100 字符），模型优先复用 |
| `provider` | `LOCAL` / `DEEPSEEK` |
| `cloudConsent` | `provider=DEEPSEEK` 时必须为 `true`，否则返回 403 |

**响应**
```json
{
  "suggestions": [
    { "name": "工作", "isNew": false, "confidence": 0.9, "reason": "开发记录" }
  ],
  "usage": { "promptTokens": 120, "completionTokens": 30 }
}
```

> 最多 5 个候选，`isNew` 由服务端根据 `existingTags` 重新计算。

---

### 润色
`POST /api/v1/ai/polish` **[IsleLog 扩展]**

**请求体**
```json
{
  "content": "第一段。\n\n第二段。",
  "mode": "LIGHT",
  "provider": "LOCAL",
  "cloudConsent": false
}
```

| `mode` | 说明 |
|--------|------|
| `LIGHT` | 只修正病句和错别字 |
| `MEDIUM` | 保留原意，改善表达 |
| `DEEP` | 允许较大结构和措辞调整 |
| `FORMAT_ONLY` | 只调整空白与 Markdown 格式，不改文字 |

**响应**
```json
{
  "segments": [
    {
      "sourceIndexes": [0],
      "originalText": "第一段。",
      "revisedText": "第一段已润色。",
      "reason": "语句通顺"
    }
  ],
  "usage": { "promptTokens": 200, "completionTokens": 80 }
}
```

> `sourceIndexes` 为以空行切分的原文段落索引，`originalText` 由服务端按索引回填。标签、Markdown 链接、待办标记、日期数值和代码块等受保护元素发生变化时，整个请求返回 422，客户端应丢弃结果。

---

### AI 错误码

错误统一为 `{ "code": 状态码, "message": "中文信息" }`，不回显请求正文或上游错误详情。

| 状态码 | 场景 |
|--------|------|
| 400 | 正文为空、Provider/润色模式无效、请求格式错误 |
| 403 | `DEEPSEEK` 缺少本次 `cloudConsent` |
| 413 | 请求体过大（>2MB）或已有标签数量过多 |
| 422 | 标签名称过长，或润色结果改变了受保护内容 |
| 429 | 并发超限（`LOCAL` 为 1，`DEEPSEEK` 为 2），稍后再试 |
| 502 | 模型返回格式无效或上游不可用 |
| 503 | 请求的 Provider 未启用 |

---

## 记忆检索

> **仅适用于 IsleLog 自建服务**，不属于标准 Memos v0.25 API；标准 Memos 服务端返回 404。
>
> embedding（把日记原文变成向量）永远走本地，不接受 `provider`/`cloudConsent`，由服务端
> 自动为每条日记建索引，客户端无需关心。只有"问答/生成"这一步（记忆检索问答、往年今日
> AI 对照）才是用户显式发起的请求，适用与标签建议/润色相同的 `provider` + `cloudConsent`
> 规则。"相关记忆"完全不调用生成模型，纯向量相似度计算。
>
> **无依据 ≠ 报错**：候选检索不到、或模型认为候选不足以回答时，接口返回 200 和
> `insufficientEvidence: true` / `now.available: false`，不是失败。服务端只信任真正
> 传给模型的候选日记 id，模型编造或引用候选之外 id 的内容一律在服务端被剔除。

### 自然语言问答

`POST /api/v1/ai/memory-search` **[IsleLog 扩展]**

**请求体**
```json
{
  "query": "去年夏天我去过哪些地方？",
  "provider": "LOCAL",
  "cloudConsent": false,
  "topK": 8
}
```

| 字段 | 说明 |
|------|------|
| `query` | 问题，必填非空 |
| `provider` | `LOCAL` / `DEEPSEEK`，只影响"生成答案"这一步；检索候选的 embedding 永远本地 |
| `cloudConsent` | `provider=DEEPSEEK` 时必须为 `true`，否则返回 403 |
| `topK` | 可选，召回候选条数，默认 8，最大 20 |

**响应（有依据）**
```json
{
  "answer": "去年夏天你提到去过厦门（7月）和黄山（8月）。",
  "sources": [
    {"memo": "memos/1001", "displayTime": "2025-07-12T10:00:00Z", "snippet": "…", "similarity": 0.81}
  ],
  "insufficientEvidence": false,
  "indexIncomplete": false,
  "usage": { "promptTokens": 480, "completionTokens": 60 }
}
```

**响应（无依据）**
```json
{ "answer": "", "sources": [], "insufficientEvidence": true, "indexIncomplete": false }
```

> `indexIncomplete: true` 表示还有日记尚未建完索引，结果可能不全，但不影响本次已返回的结果。
> `sources` 只包含模型真实引用、且确实出现在候选集合里的日记，模型编造的引用不会出现。

### 相关记忆

`GET /api/v1/memos/:memo/related-memories?limit=5` **[IsleLog 扩展]**

- 纯向量相似度 + 标签/地点/时间加权，**不调用任何生成模型**，可在打开详情页时直接调用。
- `limit` 范围 2～5，默认 3。
- 目标日记自己还没建好索引时返回空列表 + `pending: true`，客户端应展示"正在分析"而不是
  长期显示空白，也不要因此判定为"没有相关记忆"。

**响应**
```json
{
  "relatedMemos": [
    {
      "memo": "memos/998",
      "displayTime": "2025-08-02T09:00:00Z",
      "snippet": "……",
      "similarity": 0.71,
      "matchReason": "地点相近 · 标签重合"
    }
  ],
  "pending": false
}
```

### 往年今日 AI 对照

`POST /api/v1/ai/on-this-day-compare` **[IsleLog 扩展]**

**请求体**
```json
{ "memo": "memos/456", "provider": "LOCAL", "cloudConsent": false }
```

- 服务端自动拉取最近 7 天的日记作为"现在"素材，客户端不需要自己组装、发送近期日记。
- 最近 7 天没有任何日记，或近期素材不足以总结出有意义的近况时，`now.available` 为
  `false`，客户端应展示"最近没有记录，暂时无法对照"，而不是显示一段空内容。

**响应**
```json
{
  "past": { "summary": "当时在纠结要不要换工作。", "sources": ["memos/456"] },
  "now": {
    "available": true,
    "summary": "最近在筹备发布会，工作推进比较稳定。",
    "sources": ["memos/9001", "memos/9007"]
  },
  "usage": { "promptTokens": 300, "completionTokens": 50 }
}
```

`now.available: false` 时响应中不含 `now.summary` / `now.sources`。

### 记忆检索错误码

复用 AI 错误码表（400/403/429/502/503）；额外说明：

| 状态码 | 场景 |
|--------|------|
| 404 | `memo` 参数指向的日记不存在，或不属于当前用户 |
| 503 | embedding 服务未配置（`AI_LOCAL_EMBEDDING_BASE_URL` 未设置），记忆检索整体不可用 |

### Provider 状态扩展

`GET /api/v1/ai/providers` 响应数组新增一项，供客户端判断"记忆检索"入口是否可用：

```json
{
  "name": "LOCAL_EMBEDDING",
  "enabled": true,
  "available": true,
  "model": "bge-m3",
  "contextLength": 0,
  "checkedAt": "2026-09-15T10:00:00Z"
}
```

---

## 健康检查

`GET /healthz` **[IsleLog 扩展]**

无需认证。返回 `{"status":"ok"}`。

---

## Memo 响应结构

```json
{
  "name": "memos/123",
  "state": "NORMAL",
  "creator": "users/456",
  "createTime": "2026-01-01T10:00:00Z",
  "updateTime": "2026-01-01T10:00:00Z",
  "displayTime": "2026-01-01T10:00:00Z",
  "content": "今天天气不错 #日记",
  "visibility": "PRIVATE",
  "pinned": false,
  "tags": ["日记"],
  "attachments": [],
  "relations": [],
  "mood": 1,
  "weather": 2,
  "location": { "placeholder": "上海", "latitude": 31.23, "longitude": 121.47 }
}
```

> `mood`、`weather`、`location` 为 IsleLog 扩展字段，不存在时不输出。

## Article 响应结构

在 Memo 响应结构基础上额外包含：

```json
{
  "type": "ARTICLE",
  "title": "文章标题",
  "parent": "folders/111"
}
```

> `parent` 为 `null` 表示在根目录。
