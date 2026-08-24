# 隐私空间（Vault）设计

日期：2026-08-24（2026-08-24 修订：评审后重做密钥恢复链路、落盘可靠性、迁移级联清理）
分支：`server-feat`（客户端） / 服务端（islelog-server，参考 `server-API.md`）
涉及仓库：本仓库（Flutter 客户端）；服务端需配合新增一个接口（见第 10 节）

---

## 1. 问题与威胁模型

日记里可能有一些不希望任何人（包括最亲密的人）看到的内容。现有产品完全没有锁屏/密码机制，所有内容对拿到已解锁手机的人都是明文可见的。

威胁模型：对方是**不懂技术**的人，但可能会翻文件系统、翻备份，未来也可能借助 AI 工具帮忙找线索。不需要防真正的技术攻击者，但要做到：

1. 界面上没有任何入口痕迹，不会被误触或看到
2. 磁盘上（包括备份）不出现明文内容，也不出现明显的"这里有个隐藏功能"的结构特征
3. 云端服务器只存密文
4. 分享给别人的安装包里，这个功能从编译产物层面就不存在

不追求的：抗专业取证、抗物理攻击、口令找回、抗逆向工程。口令忘记 = 数据永久丢失（恢复码是唯一兜底）。

## 2. 方案概述

- **入口**：主页搜索框输入预设口令**并回车**，直接进入隐私空间页；未命中时行为与普通搜索失败完全一致，无法区分。
- **加密**：随机生成一把主密钥（MK），分别用口令和恢复码包裹成两个 keyslot 存在文件头。磁盘上不存口令哈希，验证方式就是"能不能解开"。
- **存储**：两个不透明密文文件（`idx.bin` 文字索引 / `atc.bin` 附件包），从第 0 字节起就是均匀随机字节，没有明文头、没有 schema、没有 magic。
- **视图**：隐私空间内是主库日记 + vault 日记的合并时间线，可筛选"仅隐私"。主库完全不知道 vault 的存在。
- **移入/移出**：可以把一篇普通日记连同附件转入 vault（原条目及其关联数据被级联物理删除），也可以完整移出（附件字节还原成正常附件）。
- **同步**：vault 内容伪装成一条"加密备份"memo 上传。**单设备写 + 换机恢复**模型，不支持多设备并行编辑。
- **编译期开关**：分享版从编译产物层面不含此功能。

## 3. 密钥与加密

### 主密钥与 keyslot

主密钥 **MK 是随机生成的，不由口令直接派生**。这一点是换机恢复能成立的前提：MK 属于 vault，不属于设备；口令只是包裹 MK 的外壳，跟着密文文件一起走。

```
MK          = 32 字节随机（AES-256-GCM 密钥）
KEK(凭证)   = Argon2id(凭证, salt, m=32MB, t=2, p=1) → 32 字节
keyslot     = salt(16B) ‖ AES-GCM(KEK, MK)  →  固定 76 字节
```

文件头固定放**两个** keyslot：口令槽 + 恢复码槽。因此恢复码在本设计里是**必选**的，不是可选项——两个槽位恒定存在，文件布局在任何情况下完全一致，不会因为"有没有启用恢复码"而出现可区分的差异。

依赖：[`cryptography`](https://pub.dev/packages/cryptography) ^2.9.0（纯 Dart，Argon2id + AES-GCM，全平台，无原生绑定）。

### 文件格式

```
idx.bin:
  [0   .. 76)    keyslot#1  —— 口令包裹的 MK
  [76  .. 152)   keyslot#2  —— 恢复码包裹的 MK
  [152 ..    )   AES-GCM(MK, body)   ：12B nonce ‖ ciphertext ‖ 16B mac

atc.bin:
  [0   ..    )   AES-GCM(MK, TLV 附件容器)
```

**没有任何明文头字节**。格式版本号、是否有恢复码这类元信息全部放进加密后的 body JSON（`{"v":1,"revision":N,"entries":[...]}`），不放在明文区——否则文件开头那几个固定字节就成了可识别特征，与"看上去是随机字节"的目标直接冲突。

**没有口令哈希**：磁盘上不留任何"待验证的秘密"。验证口令的唯一方式是用派生的 KEK 尝试解开 keyslot，GCM tag 校验通过即为正确。

### 落盘可靠性

日记数据不能因为一次崩溃就全丢，而 AEAD 的特性是"损坏一个字节 = 整个文件解不开"。所以所有写盘必须原子：

```
1. 写 <target>.tmp，flush
2. 若 <target> 存在：rename(<target> → <target>.bak)
3. rename(<target>.tmp → <target>)
```

两次 rename 都是同文件系统内的原子操作。中间那个窗口（target 已改名、tmp 还没改名）里 `.bak` 持有完好数据，所以读取时的规则是：**target 不存在或解不开 → 回退读 `.bak`**。

### 损坏容忍

解锁路径全程不允许异常冒泡到 UI：文件长度不足、keyslot 截断、GCM 校验失败、body 不是合法 JSON、JSON 字段类型不对——**一律当作"这个口令打不开这个文件"处理，返回 false**，走回退读 `.bak` 的分支。原因有两层：一是崩溃本身就会暴露"刚才那次输入触发了特殊代码路径"，二是给不懂技术的人看到堆栈没有任何意义。

### 内存卫生

密钥和解密出的明文只在解锁期间常驻内存，锁定时清空引用（`Uint8List` 承载，不经过 `String`）。不做更复杂的防护（防 GC 复制、防 swap 等）——对应的威胁模型不在防御范围内。

## 4. 入口与锁定

### 三个入口动作

全部通过主页搜索框，**只在回车提交时判定**（见下方"为什么只在回车时判定"）：

| 输入 | 条件 | 行为 |
|---|---|---|
| `+口令` | 本地无 vault，且口令含大小写字母+数字、长度≥8、无空格 | 创建 vault |
| `口令` | 本地有 vault，长度≥8、无空格 | 解锁 |
| `?口令` | 本地无 vault，已配置服务端，长度≥8、无空格 | 从服务端恢复（换机用，见第 8 节） |

任何一条不满足，都**完全按普通搜索处理**——不弹提示、不报错、不给任何反馈。提示本身就会暴露"这里有个特殊入口"。

`+` 的强度约束还顺带防误触：日常搜索凑巧输入一个 8 位以上、以 `+` 开头的词（比如 `+项目截止0824`）不会被误判成创建请求。解锁不加这个约束——解锁失败的代价只是一次静默的空搜索结果。

### 为什么只在回车时判定

Flutter 的 `SearchDelegate` 里，逐键输入走 `buildSuggestions`，回车提交走 `buildResults`（`search.dart` 中 `onSubmitted → showResults`）。判定**只挂在 `buildResults`**，`buildSuggestions` 完全不触发。

如果挂在逐键路径上，用户每输入一个 ≥8 字符的普通搜索词都会跑一次 32MB 的 Argon2id（口令槽不中还要再跑一次恢复码槽），既是明显卡顿，也构成时间侧信道——"输入某些词时 App 会卡一下"本身就是可观察的异常。

另外在内存里缓存"上一个已尝试过且失败的候选串"，同一个词重复提交不重复派生。

### 锁定

**锁定时机**：离开隐私空间页；App 进入后台（`paused`）超过 60 秒。

只盯 `paused`，不把 `inactive` / `hidden` 拉进计时器——下拉通知栏、来电横幅、权限弹窗都会触发那两个状态，纳入计时会导致正常操作频繁掉锁，且对下面要解决的截屏问题毫无帮助。

**锁定必须驱动 UI**：`VaultController` 通过 `isUnlockedListenable` 广播状态。`VaultPage` / `VaultEditorPage` 监听到锁定后，立即清空输入框内容并弹回根页面。否则会出现"计时器已锁定、编辑器还开着并持有明文、此时点保存直接空指针崩溃"。存储层的写方法同步加防御检查，锁定状态下调用抛明确的 `StateError` 而非裸断言。

### 截屏与任务切换器

系统的最近任务缩略图是在应用进入后台的**瞬间**截取的，和"锁定计时器设多长"无关——60 秒宽限期完全挡不住它。这需要独立的截屏防护机制：

- **Android**：进入 vault 页时设 `FLAG_SECURE`，离开时清除。同时屏蔽截屏和任务切换器缩略图。
- **iOS**：在 `applicationWillResignActive` 时给窗口盖一层不透明视图，`didBecomeActive` 时移除。

两端都用自建 MethodChannel 实现（各约 15–20 行平台代码），不引第三方包。桌面端（macOS/Linux/Windows）没有等价机制，不在范围内。

## 5. 数据模型与视图

```dart
class VaultEntry {
  String id;                  // uuid
  String content;             // Markdown 正文
  DateTime createdAt;
  DateTime updatedAt;
  List<String> tags;          // 从 content 解析，仅存在于内存
  List<String> attachmentIds; // 对应 atc.bin 内的条目 id
  String? memosName;
  String? movedFromMemosName; // 由普通日记移入时记录来源，审计用
}
```

加密 body 的顶层结构：

```json
{ "v": 1, "revision": 17, "entries": [ ... ] }
```

`revision` 每次保存自增，用于第 8 节的同步取舍。

**合并时间线**：隐私空间页同时读主库 Isar（`DatabaseService`）和内存中的 `VaultEntry` 列表，按时间归并，vault 条目带小锁标记。顶部提供"全部 / 仅隐私"筛选。

**主库隔离**：vault 的标签、统计**不写入** `TagStat` 表或任何主库结构，只在内存中现算现用。否则主页侧边栏的标签列表会泄漏隐私标签。

**搜索**：隐私空间内的搜索是解锁后在内存中对已解密内容做字符串匹配，不建索引。

## 6. 附件

**存储格式**（`atc.bin` 加密前的明文体，TLV）：

```
[4B] 条目数
每条: [2B idLen][id] [2B mimeLen][mime] [4B dataLen][data]
```

不采用 zip：照片（JPEG）、录音（AAC）本身已是压缩格式，DEFLATE 收益接近零，不值得引入额外依赖。

**重写策略**：`idx.bin`（纯文字，体积小）每次保存都整体重写；`atc.bin`（附件，体积大）只在增删附件时重写。两者共用同一把 MK。

**已知代价**：附件整体重写，加一个新附件要把所有已有附件重新加密一遍。个人量级（几十个文件）可接受，量级显著增长后会变慢——v1 不做分片。

**查看时不落地明文**：图片走 `Image.memory(bytes)`；录音走自定义 `StreamAudioSource` 从内存字节播放。录音**录制**时受 `record` 包限制必须先写文件，读入内存后立即删除该临时文件。

## 7. 移入 / 移出

### 移入（普通日记 → vault）

前置检查：`memo.syncStatus == pending` 时**拒绝移入**并提示"请先完成同步"。原因是移入过程要删远端条目，而后台 `pushPendingBackground()` 可能正在推送这条 memo，导致"远端删完又被重建"。用前置条件把这个竞态窗口关掉，比引入"暂停同步引擎"这种重机制更简单可靠。

步骤：

1. 读取正文 + 附件字节（本地文件缺失时先 `AttachmentService.downloadToLocal` 拉回）
2. 写入 vault（`idx.bin` + `atc.bin`）
3. 服务端：硬删除该 memo（含版本历史）+ 硬删除其附件资源
4. 本地级联清理——**只删 `MemoEntry` 是不够的**：
   - 附件明文文件：逐个 `AttachmentService.deleteLocal(localPath)`，包括步骤 1 刚下载的那份副本
   - 评论：`getCommentsByMemoId(id)` → 逐个 `hardDeleteComment`。否则 `CommentEntry` 仍持有明文且能被主库搜索命中
   - 事件串：`removeMemoFromAllThreads(id)`。现有 `softDelete` 调了这个，`hardDelete` 没调，是既存缺口，vault 迁移路径必须自己补
   - 最后 `DatabaseService.hardDelete(memo.id)`

### 移出（vault → 普通日记）

附件必须完整还原，不能静默销毁：解密字节 → 写临时文件 → `AttachmentService.saveLocally()` → 挂到新建的 `MemoEntry` → 删除临时文件。全部成功后才从 vault 删除条目。

不采用"弹窗告知附件将被删除"的做法——数据不该丢，这是日记应用的底线。

## 8. 同步

### 模型：单设备写 + 换机恢复

v1 **不支持多设备并行编辑**。加密 body 里的 `revision` 计数器提供基本的先后取舍：拉取时 remote revision 更高则采用远端，否则保留本地并推送。若两台设备各自离线编辑后先后推送，**后推送的整体覆盖先推送的，没有合并**。真正的并行编辑需要在密文体内做条目级 revision 和冲突策略，另立一期。

### 上传格式

```
content:    "IsleLog-Backup/1\n<base64(idx.bin)>"
visibility: PRIVATE
附件:        atc.bin 密文作为普通附件上传（文件名 backup.dat）
```

复用现有 `AttachmentService` 的上传通道，不新建传输路径。客户端 `SyncService._applyRemoteMemo` 识别 `IsleLog-Backup/1` 前缀后直接跳过，因此在未设置过口令的设备上，这条 memo 只是静默存在。

### 换机恢复协议

这是原设计里断掉的一环，重新定义。**MK 属于 vault 而非设备**（第 3 节），keyslot 跟着 `idx.bin` 一起走，所以新设备只要拿到远端的 `idx.bin`，用同一个口令就能解开——前提是它**不能先自己创建一个 vault**（那会生成一把无关的新 MK）。

新设备输入 `?口令` 触发：

1. 检查本地无 vault、服务端已配置（否则按普通搜索处理）
2. 拉取远端 memo 列表，按 `IsleLog-Backup/1` 前缀找到备份条目
3. 解 base64 得到 `idx.bin` 字节，**在内存中**用输入的口令试解 keyslot
4. 解不开 → 静默失败，不落盘、不提示
5. 解开了 → 原子写入本地，下载 `backup.dat` 还原 `atc.bin`，完成解锁

恢复走**显式前缀**而非"解锁失败后自动尝试"，是为了避免每次长搜索词都触发一次远端全量列表拉取——那既慢又在网络层可观察。

`vaultBackupMemoName` 这个 SharedPreferences key 改名为中性的 `enc_backup_memo_name`，与"加密备份"封面故事一致（key 名在备份出的 XML/plist 里是明文可读的）。它存的只是资源指针，本身不含秘密。

### 覆盖前必须先验证

从远端拿回的数据，**必须先在内存中解密验证成功，才能原子替换本地文件**。原设计是先写盘再解密，远端损坏或口令不匹配时会把本地完好数据冲掉之后才抛异常。

### 封面故事

这条 memo 在服务端后台看起来就是一条"加密备份"记录，且客户端设置页有一个真实存在的"加密云备份"开关与之对应——不是编造的伪装，是一个确实生效的功能点，经得起对方在 App 内核对。

## 9. 编译期开关——分享版不含隐私空间

```dart
const bool kVaultEnabled = bool.fromEnvironment('VAULT_ENABLED', defaultValue: true);
```

`main.dart` 的初始化、`home_view.dart` 的搜索框钩子都包一层 `if (kVaultEnabled)`。因为是编译期常量，release 编译器会把 `false` 分支连同其中专属引用的类一起做死代码消除——不是运行时隐藏。

- **自用包**：不传参数，默认 `true`
- **分享包**：`flutter build apk --release --dart-define=VAULT_ENABLED=false --obfuscate --split-debug-info=build/symbols`

`--obfuscate` 是顺手加的零成本加固。不追求逆向工程级别的绝对不可恢复（残留字符串常量等边角案例），那已远超本威胁模型。

## 10. 存储位置

`Application Support/blob/` 下的 `idx.bin` / `atc.bin`（及各自的 `.bak`）。

**不**放系统 Caches 目录——那会被系统在空间紧张时清空，日记数据不可接受。

**不**调用平台 API 把这些文件排除出系统备份。评审建议排除，但这里权衡后不采纳：密文文件本身不携带任何可读信息，它出现在备份里和出现在实机上暴露的东西完全一样（都只是一个不明二进制）；反而排除备份会让"换新手机走系统备份恢复"这条路径失效，在用户没配服务端同步时会造成真实的数据丢失。

## 11. 服务端新增接口（阻塞项）

```
DELETE /api/v1/memos/:id?hard=true   [IsleLog 扩展，待新增]
```

物理删除该 memo 行及其在版本历史表中的所有记录（而非现有 `DELETE` 的软删除 `row_status=DELETED`）。附件同理需要硬删除路径。

这一步客户端单独做不到——现有软删除会让"移入前的明文"永久留在服务端数据库和版本历史里。服务端代码不在本仓库，需在 islelog-server 项目单独实现。**在服务端配合之前，移入功能应视为不完整**（明文在服务端只是被隐藏，未被清除）。

## 12. 需要改动的现有代码

| 文件 | 改动 |
|---|---|
| `lib/features/home/home_view.dart` | `_MemoSearchDelegate.buildResults` 路径加口令钩子（三种前缀），整体包在 `kVaultEnabled` 内 |
| `lib/services/sync/sync_service.dart` | `_applyRemoteMemo` 识别 `IsleLog-Backup/1` 前缀并跳过 |
| `lib/services/api/memos_api_service.dart` | `deleteMemo` 加 `hard` 参数；新增按 memo 列附件的方法 |
| `lib/services/settings/settings_service.dart` | 新增 `enc_backup_memo_name` |
| `lib/main.dart` | 初始化包在 `kVaultEnabled` 内 |
| `android/.../MainActivity.kt`、`ios/.../AppDelegate.swift` | 截屏防护 MethodChannel |
| 新增 `lib/shared/constants/build_flags.dart` | 编译期开关 |
| 新增 `lib/services/vault/` | 加解密、原子读写、会话控制、迁移、同步 |
| 新增 `lib/features/vault/` | 隐私空间页、独立精简编辑器、内存音频源 |

不涉及 Isar `@collection` 模型改动，不需要跑 `build_runner`。隐私空间的编辑器是独立新写的精简页面，不是改造 `memo_editor_page.dart`（该文件 3000+ 行，耦合 AI/天气/位置/网络附件队列，逐处审计"会不会碰草稿/网络"的成本高于新写；新写的版本"没有调用草稿 API"这一点一眼可验证）。

## 13. 明确不处理的泄漏点

- 服务端管理员/数据库层面能看到密文体积和上传时间等元数据
- 对方若已知存在隐私空间并索要口令，本设计不提供可否认的"假空间"机制（威胁模型已排除胁迫场景）
- 多设备并行编辑会整体覆盖，不合并（第 8 节）
- 桌面端无截屏防护
- 忘记口令且丢失恢复码 = 数据永久丢失，无后门
