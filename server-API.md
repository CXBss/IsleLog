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

> 若无任何变更记录，返回 `{ "changelog": null }`，客户端游标存 `-1`。

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

> `action` 取值：`CREATE` / `UPDATE` / `DELETE`。`entity` 取值：`memo` / `article` / `comment` / `attachment`。
>
> `entity=comment` 时，`entityId` 格式为 `memos/{id}`，直接用 `GET /api/v1/memos/{id}` 拉取。
>
> 客户端判断 `total >= 300` 时放弃增量，直接走全量同步。

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
