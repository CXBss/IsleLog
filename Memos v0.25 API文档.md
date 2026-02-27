---
title: Memos v0.25 API文档
date: 2026-01-27T19:24:57Z
lastmod: 2026-01-29T09:43:04Z
---

# Memos v0.25 API文档

---

- Untitled
- [https://memos.apidocumentation.com/reference#tag/activityservice](https://memos.apidocumentation.com/reference#tag/activityservice)
- ListActivities returns a list of activities.
- 2026-01-27 19:24

---

- [ get/api/v1/activities](https://memos.apidocumentation.com/reference#tag/activityservice/get/api/v1/activities)
- [ get/api/v1/activities/{activity}](https://memos.apidocumentation.com/reference#tag/activityservice/get/api/v1/activities/{activity})

ListActivities returns a list of activities.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  The maximum number of activities to return. The service may return fewer than this value. If unspecified, at most 100 activities will be returned. The maximum value is 1000; values above 1000 will be coerced to 1000.
- pageToken

  Type: string

  A page token, received from a previous `ListActivities` call. Provide this to retrieve the subsequent page.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/activities
```

Show Schema

```json
{
  "activities": [
    {
      "name": "string",
      "creator": "string",
      "type": "TYPE_UNSPECIFIED",
      "level": "LEVEL_UNSPECIFIED",
      "createTime": "2026-01-27T11:23:52.606Z",
      "payload": {
        "memoComment": {
          "memo": "string",
          "relatedMemo": "string"
        }
      }
    }
  ],
  "nextPageToken": "string"
}
```

OK

GetActivity returns the activity with the given id.

Path Parameters

- activity

  Type: string

  required

  The activity id.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/activities/{activity}'
```

Show Schema

```json
{
  "name": "string",
  "creator": "string",
  "type": "TYPE_UNSPECIFIED",
  "level": "LEVEL_UNSPECIFIED",
  "createTime": "2026-01-27T11:23:52.606Z",
  "payload": {
    "memoComment": {
      "memo": "string",
      "relatedMemo": "string"
    }
  }
}
```

OK

- [ get/api/v1/attachments](https://memos.apidocumentation.com/reference#tag/attachmentservice/get/api/v1/attachments)
- [ post/api/v1/attachments](https://memos.apidocumentation.com/reference#tag/attachmentservice/post/api/v1/attachments)
- [ get/api/v1/attachments/{attachment}](https://memos.apidocumentation.com/reference#tag/attachmentservice/get/api/v1/attachments/{attachment})
- [ delete/api/v1/attachments/{attachment}](https://memos.apidocumentation.com/reference#tag/attachmentservice/delete/api/v1/attachments/{attachment})
- [ patch/api/v1/attachments/{attachment}](https://memos.apidocumentation.com/reference#tag/attachmentservice/patch/api/v1/attachments/{attachment})

ListAttachments lists all attachments.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of attachments to return. The service may return fewer than this value. If unspecified, at most 50 attachments will be returned. The maximum value is 1000; values above 1000 will be coerced to 1000.
- pageToken

  Type: string

  Optional. A page token, received from a previous `ListAttachments` call. Provide this to retrieve the subsequent page.
- filter

  Type: string

  Optional. Filter to apply to the list results. Example: "mime\_type\=\="image/png"" or "filename.contains("test")" Supported operators: \=, !\=, \<, \<\=, \>, \>\=, : (contains), in Supported fields: filename, mime\_type, create\_time, memo
- orderBy

  Type: string

  Optional. The order to sort results by. Example: "create\_time desc" or "filename asc"

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/attachments
```

Show Schema

```json
{
  "attachments": [
    {
      "name": "string",
      "createTime": "2026-01-27T11:23:52.606Z",
      "filename": "string",
      "externalLink": "string",
      "type": "string",
      "size": "string",
      "memo": "string"
    }
  ],
  "nextPageToken": "string",
  "totalSize": 1
}
```

OK

CreateAttachment creates a new attachment.

Query Parameters

- attachmentId

  Type: string

  Optional. The attachment ID to use for this attachment. If empty, a unique ID will be generated.

Body

required

application/json

- name

  Type: string

  The name of the attachment. Format: attachments/{attachment}
- createTime

  Type: string

  Format: date-time

  read-only

  Output only. The creation timestamp.
- filename

  Type: string

  required

  The filename of the attachment.
- content

  Type: string

  Format: bytes

  write-only

  Input only. The content of the attachment.
- externalLink

  Type: string

  Optional. The external link of the attachment.
- type

  Type: string

  required

  The MIME type of the attachment.
- size

  Type: string

  read-only

  Output only. The size of the attachment in bytes.
- memo

  Type: string

  Optional. The related memo. Refer to `Memo.name`. Format: memos/{memo}

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/attachments \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "filename": "",
  "content": "",
  "externalLink": "",
  "type": "",
  "memo": ""
}'
```

Show Schema

```json
{
  "name": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "filename": "string",
  "externalLink": "string",
  "type": "string",
  "size": "string",
  "memo": "string"
}
```

OK

GetAttachment returns a attachment by name.

Path Parameters

- attachment

  Type: string

  required

  The attachment id.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/attachments/{attachment}'
```

Show Schema

```json
{
  "name": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "filename": "string",
  "externalLink": "string",
  "type": "string",
  "size": "string",
  "memo": "string"
}
```

OK

DeleteAttachment deletes a attachment by name.

Path Parameters

- attachment

  Type: string

  required

  The attachment id.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/attachments/{attachment}' \
  --request DELETE
```

No Body

OK

UpdateAttachment updates a attachment.

Path Parameters

- attachment

  Type: string

  required

  The attachment id.

Query Parameters

- updateMask

  Type: string

  Format: field-mask

  Required. The list of fields to update.

Body

required

application/json

- name

  Type: string

  The name of the attachment. Format: attachments/{attachment}
- createTime

  Type: string

  Format: date-time

  read-only

  Output only. The creation timestamp.
- filename

  Type: string

  required

  The filename of the attachment.
- content

  Type: string

  Format: bytes

  write-only

  Input only. The content of the attachment.
- externalLink

  Type: string

  Optional. The external link of the attachment.
- type

  Type: string

  required

  The MIME type of the attachment.
- size

  Type: string

  read-only

  Output only. The size of the attachment in bytes.
- memo

  Type: string

  Optional. The related memo. Refer to `Memo.name`. Format: memos/{memo}

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/attachments/{attachment}' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "filename": "",
  "content": "",
  "externalLink": "",
  "type": "",
  "memo": ""
}'
```

Show Schema

```json
{
  "name": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "filename": "string",
  "externalLink": "string",
  "type": "string",
  "size": "string",
  "memo": "string"
}
```

OK

- [ get/api/v1/auth/me](https://memos.apidocumentation.com/reference#tag/authservice/get/api/v1/auth/me)
- [ post/api/v1/auth/refresh](https://memos.apidocumentation.com/reference#tag/authservice/post/api/v1/auth/refresh)
- [ post/api/v1/auth/signin](https://memos.apidocumentation.com/reference#tag/authservice/post/api/v1/auth/signin)
- [ post/api/v1/auth/signout](https://memos.apidocumentation.com/reference#tag/authservice/post/api/v1/auth/signout)

GetCurrentUser returns the authenticated user's information. Validates the access token and returns user details. Similar to OIDC's /userinfo endpoint.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/auth/me
```

Show Schema

```json
{
  "user": {
    "name": "string",
    "role": "ROLE_UNSPECIFIED",
    "username": "string",
    "email": "string",
    "displayName": "string",
    "avatarUrl": "string",
    "description": "string",
    "state": "STATE_UNSPECIFIED",
    "createTime": "2026-01-27T11:23:52.606Z",
    "updateTime": "2026-01-27T11:23:52.606Z"
  }
}
```

OK

RefreshToken exchanges a valid refresh token for a new access token. The refresh token is read from the HttpOnly cookie. Returns a new short-lived access token.

Body

required

application/json

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/auth/refresh \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{}'
```

Show Schema

```json
{
  "accessToken": "string",
  "expiresAt": "2026-01-27T11:23:52.606Z"
}
```

OK

SignIn authenticates a user with credentials and returns tokens. On success, returns an access token and sets a refresh token cookie. Supports password-based and SSO authentication methods.

Body

required

application/json

- passwordCredentials

  Type: object

  Nested message for password-based authentication credentials.
- ssoCredentials

  Type: object

  Nested message for SSO authentication credentials.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/auth/signin \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "passwordCredentials": {
    "username": "",
    "password": ""
  },
  "ssoCredentials": {
    "idpId": 1,
    "code": "",
    "redirectUri": "",
    "codeVerifier": ""
  }
}'
```

Show Schema

```json
{
  "user": {
    "name": "string",
    "role": "ROLE_UNSPECIFIED",
    "username": "string",
    "email": "string",
    "displayName": "string",
    "avatarUrl": "string",
    "description": "string",
    "state": "STATE_UNSPECIFIED",
    "createTime": "2026-01-27T11:23:52.606Z",
    "updateTime": "2026-01-27T11:23:52.606Z"
  },
  "accessToken": "string",
  "accessTokenExpiresAt": "2026-01-27T11:23:52.606Z"
}
```

OK

SignOut terminates the user's authentication. Revokes the refresh token and clears the authentication cookie.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/auth/signout \
  --request POST
```

No Body

OK

- [ get/api/v1/identity-providers](https://memos.apidocumentation.com/reference#tag/identityproviderservice/get/api/v1/identity-providers)
- [ post/api/v1/identity-providers](https://memos.apidocumentation.com/reference#tag/identityproviderservice/post/api/v1/identity-providers)
- [ get/api/v1/identity-providers/{identity-provider}](https://memos.apidocumentation.com/reference#tag/identityproviderservice/get/api/v1/identity-providers/{identity-provider})
- [ delete/api/v1/identity-providers/{identity-provider}](https://memos.apidocumentation.com/reference#tag/identityproviderservice/delete/api/v1/identity-providers/{identity-provider})
- [ patch/api/v1/identity-providers/{identity-provider}](https://memos.apidocumentation.com/reference#tag/identityproviderservice/patch/api/v1/identity-providers/{identity-provider})
- [ get/api/v1/instance/profile](https://memos.apidocumentation.com/reference#tag/instanceservice/get/api/v1/instance/profile)
- [ get/api/v1/instance/{instance}/*](https://memos.apidocumentation.com/reference#tag/instanceservice/get/api/v1/instance/{instance}/*)
- [ patch/api/v1/instance/{instance}/*](https://memos.apidocumentation.com/reference#tag/instanceservice/patch/api/v1/instance/{instance}/*)
- [ get/api/v1/memos](https://memos.apidocumentation.com/reference#tag/memoservice/get/api/v1/memos)
- [ post/api/v1/memos](https://memos.apidocumentation.com/reference#tag/memoservice/post/api/v1/memos)
- [ get/api/v1/memos/{memo}](https://memos.apidocumentation.com/reference#tag/memoservice/get/api/v1/memos/{memo})
- [ delete/api/v1/memos/{memo}](https://memos.apidocumentation.com/reference#tag/memoservice/delete/api/v1/memos/{memo})
- [ patch/api/v1/memos/{memo}](https://memos.apidocumentation.com/reference#tag/memoservice/patch/api/v1/memos/{memo})
- [ get/api/v1/memos/{memo}/attachments](https://memos.apidocumentation.com/reference#tag/memoservice/get/api/v1/memos/{memo}/attachments)
- [ patch/api/v1/memos/{memo}/attachments](https://memos.apidocumentation.com/reference#tag/memoservice/patch/api/v1/memos/{memo}/attachments)
- [ get/api/v1/memos/{memo}/comments](https://memos.apidocumentation.com/reference#tag/memoservice/get/api/v1/memos/{memo}/comments)
- [ post/api/v1/memos/{memo}/comments](https://memos.apidocumentation.com/reference#tag/memoservice/post/api/v1/memos/{memo}/comments)
- [ get/api/v1/memos/{memo}/reactions](https://memos.apidocumentation.com/reference#tag/memoservice/get/api/v1/memos/{memo}/reactions)
- [ post/api/v1/memos/{memo}/reactions](https://memos.apidocumentation.com/reference#tag/memoservice/post/api/v1/memos/{memo}/reactions)
- [ delete/api/v1/memos/{memo}/reactions/{reaction}](https://memos.apidocumentation.com/reference#tag/memoservice/delete/api/v1/memos/{memo}/reactions/{reaction})
- [ get/api/v1/memos/{memo}/relations](https://memos.apidocumentation.com/reference#tag/memoservice/get/api/v1/memos/{memo}/relations)
- [ patch/api/v1/memos/{memo}/relations](https://memos.apidocumentation.com/reference#tag/memoservice/patch/api/v1/memos/{memo}/relations)

ListMemos lists memos with pagination and filter.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of memos to return. The service may return fewer than this value. If unspecified, at most 50 memos will be returned. The maximum value is 1000; values above 1000 will be coerced to 1000.
- pageToken

  Type: string

  Optional. A page token, received from a previous `ListMemos` call. Provide this to retrieve the subsequent page.
- state

  Type: string

  Format: enum

  enum

  Optional. The state of the memos to list. Default to `NORMAL`. Set to `ARCHIVED` to list archived memos.

  - STATE\_UNSPECIFIED
  - NORMAL
  - ARCHIVED
- orderBy

  Type: string

  Optional. The order to sort results by. Default to "display\_time desc". Supports comma-separated list of fields following AIP-132. Example: "pinned desc, display\_time desc" or "create\_time asc" Supported fields: pinned, display\_time, create\_time, update\_time, name
- filter

  Type: string

  Optional. Filter to apply to the list results. Filter is a CEL expression to filter memos. Refer to `Shortcut.filter`.
- showDeleted

  Type: boolean

  Optional. If true, show deleted memos in the response.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/memos
```

Show Schema

```json
{
  "memos": [
    {
      "name": "string",
      "state": "STATE_UNSPECIFIED",
      "creator": "string",
      "createTime": "2026-01-27T11:23:52.606Z",
      "updateTime": "2026-01-27T11:23:52.606Z",
      "displayTime": "2026-01-27T11:23:52.606Z",
      "content": "string",
      "visibility": "VISIBILITY_UNSPECIFIED",
      "tags": [
        "string"
      ],
      "pinned": true,
      "attachments": [
        {
          "name": "",
          "filename": "",
          "content": "",
          "externalLink": "",
          "type": "",
          "memo": ""
        }
      ],
      "relations": [
        {
          "memo": {
            "name": ""
          },
          "relatedMemo": {
            "name": ""
          },
          "type": "TYPE_UNSPECIFIED"
        }
      ],
      "reactions": [
        {
          "name": "string",
          "creator": "string",
          "contentId": "string",
          "reactionType": "string",
          "createTime": "2026-01-27T11:23:52.606Z"
        }
      ],
      "property": {
        "hasLink": true,
        "hasTaskList": true,
        "hasCode": true,
        "hasIncompleteTasks": true
      },
      "parent": "string",
      "snippet": "string",
      "location": {
        "placeholder": "",
        "latitude": 1,
        "longitude": 1
      }
    }
  ],
  "nextPageToken": "string"
}
```

OK

CreateMemo creates a memo.

Query Parameters

- memoId

  Type: string

  Optional. The memo ID to use for this memo. If empty, a unique ID will be generated.

Body

required

application/json

- name

  Type: string

  The resource name of the memo. Format: memos/{memo}, memo is the user defined id or uuid.
- state

  Type: string

  Format: enum

  enum

  required

  The state of the memo.

  - STATE\_UNSPECIFIED
  - NORMAL
  - ARCHIVED
- creator

  Type: string

  read-only

  The name of the creator. Format: users/{user}
- createTime

  Type: string

  Format: date-time

  The creation timestamp. If not set on creation, the server will set it to the current time.
- updateTime

  Type: string

  Format: date-time

  The last update timestamp. If not set on creation, the server will set it to the current time.
- displayTime

  Type: string

  Format: date-time

  The display timestamp of the memo.
- content

  Type: string

  required

  Required. The content of the memo in Markdown format.
- visibility

  Type: string

  Format: enum

  enum

  required

  The visibility of the memo.

  - VISIBILITY\_UNSPECIFIED
  - PRIVATE
  - PROTECTED
  - PUBLIC
- tags

  Type: array string[]

  read-only

  Output only. The tags extracted from the content.
- pinned

  Type: boolean

  Whether the memo is pinned.
- attachments

  Type: array object[]

  Optional. The attachments of the memo.
- relations

  Type: array object[]

  Optional. The relations of the memo.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/memos \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "state": "STATE_UNSPECIFIED",
  "createTime": "",
  "updateTime": "",
  "displayTime": "",
  "content": "",
  "visibility": "VISIBILITY_UNSPECIFIED",
  "pinned": true,
  "attachments": [
    {
      "name": "",
      "filename": "",
      "content": "",
      "externalLink": "",
      "type": "",
      "memo": ""
    }
  ],
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ],
  "location": {
    "placeholder": "",
    "latitude": 1,
    "longitude": 1
  }
}'
```

Show Schema

```json
{
  "name": "string",
  "state": "STATE_UNSPECIFIED",
  "creator": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z",
  "displayTime": "2026-01-27T11:23:52.606Z",
  "content": "string",
  "visibility": "VISIBILITY_UNSPECIFIED",
  "tags": [
    "string"
  ],
  "pinned": true,
  "attachments": [
    {
      "name": "",
      "filename": "",
      "content": "",
      "externalLink": "",
      "type": "",
      "memo": ""
    }
  ],
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ],
  "reactions": [
    {
      "name": "string",
      "creator": "string",
      "contentId": "string",
      "reactionType": "string",
      "createTime": "2026-01-27T11:23:52.606Z"
    }
  ],
  "property": {
    "hasLink": true,
    "hasTaskList": true,
    "hasCode": true,
    "hasIncompleteTasks": true
  },
  "parent": "string",
  "snippet": "string",
  "location": {
    "placeholder": "",
    "latitude": 1,
    "longitude": 1
  }
}
```

OK

GetMemo gets a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}'
```

Show Schema

```json
{
  "name": "string",
  "state": "STATE_UNSPECIFIED",
  "creator": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z",
  "displayTime": "2026-01-27T11:23:52.606Z",
  "content": "string",
  "visibility": "VISIBILITY_UNSPECIFIED",
  "tags": [
    "string"
  ],
  "pinned": true,
  "attachments": [
    {
      "name": "",
      "filename": "",
      "content": "",
      "externalLink": "",
      "type": "",
      "memo": ""
    }
  ],
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ],
  "reactions": [
    {
      "name": "string",
      "creator": "string",
      "contentId": "string",
      "reactionType": "string",
      "createTime": "2026-01-27T11:23:52.606Z"
    }
  ],
  "property": {
    "hasLink": true,
    "hasTaskList": true,
    "hasCode": true,
    "hasIncompleteTasks": true
  },
  "parent": "string",
  "snippet": "string",
  "location": {
    "placeholder": "",
    "latitude": 1,
    "longitude": 1
  }
}
```

OK

DeleteMemo deletes a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Query Parameters

- force

  Type: boolean

  Optional. If set to true, the memo will be deleted even if it has associated data.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}' \
  --request DELETE
```

No Body

OK

UpdateMemo updates a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Query Parameters

- updateMask

  Type: string

  Format: field-mask

  Required. The list of fields to update.

Body

required

application/json

- name

  Type: string

  The resource name of the memo. Format: memos/{memo}, memo is the user defined id or uuid.
- state

  Type: string

  Format: enum

  enum

  required

  The state of the memo.

  - STATE\_UNSPECIFIED
  - NORMAL
  - ARCHIVED
- creator

  Type: string

  read-only

  The name of the creator. Format: users/{user}
- createTime

  Type: string

  Format: date-time

  The creation timestamp. If not set on creation, the server will set it to the current time.
- updateTime

  Type: string

  Format: date-time

  The last update timestamp. If not set on creation, the server will set it to the current time.
- displayTime

  Type: string

  Format: date-time

  The display timestamp of the memo.
- content

  Type: string

  required

  Required. The content of the memo in Markdown format.
- visibility

  Type: string

  Format: enum

  enum

  required

  The visibility of the memo.

  - VISIBILITY\_UNSPECIFIED
  - PRIVATE
  - PROTECTED
  - PUBLIC
- tags

  Type: array string[]

  read-only

  Output only. The tags extracted from the content.
- pinned

  Type: boolean

  Whether the memo is pinned.
- attachments

  Type: array object[]

  Optional. The attachments of the memo.
- relations

  Type: array object[]

  Optional. The relations of the memo.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "state": "STATE_UNSPECIFIED",
  "createTime": "",
  "updateTime": "",
  "displayTime": "",
  "content": "",
  "visibility": "VISIBILITY_UNSPECIFIED",
  "pinned": true,
  "attachments": [
    {
      "name": "",
      "filename": "",
      "content": "",
      "externalLink": "",
      "type": "",
      "memo": ""
    }
  ],
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ],
  "location": {
    "placeholder": "",
    "latitude": 1,
    "longitude": 1
  }
}'
```

Show Schema

```json
{
  "name": "string",
  "state": "STATE_UNSPECIFIED",
  "creator": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z",
  "displayTime": "2026-01-27T11:23:52.606Z",
  "content": "string",
  "visibility": "VISIBILITY_UNSPECIFIED",
  "tags": [
    "string"
  ],
  "pinned": true,
  "attachments": [
    {
      "name": "",
      "filename": "",
      "content": "",
      "externalLink": "",
      "type": "",
      "memo": ""
    }
  ],
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ],
  "reactions": [
    {
      "name": "string",
      "creator": "string",
      "contentId": "string",
      "reactionType": "string",
      "createTime": "2026-01-27T11:23:52.606Z"
    }
  ],
  "property": {
    "hasLink": true,
    "hasTaskList": true,
    "hasCode": true,
    "hasIncompleteTasks": true
  },
  "parent": "string",
  "snippet": "string",
  "location": {
    "placeholder": "",
    "latitude": 1,
    "longitude": 1
  }
}
```

OK

ListMemoAttachments lists attachments for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of attachments to return.
- pageToken

  Type: string

  Optional. A page token for pagination.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/attachments'
```

Show Schema

```json
{
  "attachments": [
    {
      "name": "string",
      "createTime": "2026-01-27T11:23:52.606Z",
      "filename": "string",
      "externalLink": "string",
      "type": "string",
      "size": "string",
      "memo": "string"
    }
  ],
  "nextPageToken": "string"
}
```

OK

SetMemoAttachments sets attachments for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Body

required

application/json

- name

  Type: string

  required

  Required. The resource name of the memo. Format: memos/{memo}
- attachments

  Type: array object[]

  required

  Required. The attachments to set for the memo.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/attachments' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "attachments": [
    {
      "name": "",
      "filename": "",
      "content": "",
      "externalLink": "",
      "type": "",
      "memo": ""
    }
  ]
}'
```

No Body

OK

ListMemoReactions lists reactions for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of reactions to return.
- pageToken

  Type: string

  Optional. A page token for pagination.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/reactions'
```

Show Schema

```json
{
  "reactions": [
    {
      "name": "string",
      "creator": "string",
      "contentId": "string",
      "reactionType": "string",
      "createTime": "2026-01-27T11:23:52.606Z"
    }
  ],
  "nextPageToken": "string",
  "totalSize": 1
}
```

OK

UpsertMemoReaction upserts a reaction for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Body

required

application/json

- name

  Type: string

  required

  Required. The resource name of the memo. Format: memos/{memo}
- reaction

  Type: object

  required

  Required. The reaction to upsert.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/reactions' \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "reaction": {
    "contentId": "",
    "reactionType": ""
  }
}'
```

Show Schema

```json
{
  "name": "string",
  "creator": "string",
  "contentId": "string",
  "reactionType": "string",
  "createTime": "2026-01-27T11:23:52.606Z"
}
```

OK

DeleteMemoReaction deletes a reaction for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.
- reaction

  Type: string

  required

  The reaction id.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/reactions/{reaction}' \
  --request DELETE
```

No Body

OK

ListMemoRelations lists relations for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of relations to return.
- pageToken

  Type: string

  Optional. A page token for pagination.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/relations'
```

Show Schema

```json
{
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ],
  "nextPageToken": "string"
}
```

OK

SetMemoRelations sets relations for a memo.

Path Parameters

- memo

  Type: string

  required

  The memo id.

Body

required

application/json

- name

  Type: string

  required

  Required. The resource name of the memo. Format: memos/{memo}
- relations

  Type: array object[]

  required

  Required. The relations to set for the memo.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/memos/{memo}/relations' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "relations": [
    {
      "memo": {
        "name": ""
      },
      "relatedMemo": {
        "name": ""
      },
      "type": "TYPE_UNSPECIFIED"
    }
  ]
}'
```

No Body

OK

- [ get/api/v1/users/{user}/shortcuts](https://memos.apidocumentation.com/reference#tag/shortcutservice/get/api/v1/users/{user}/shortcuts)
- [ post/api/v1/users/{user}/shortcuts](https://memos.apidocumentation.com/reference#tag/shortcutservice/post/api/v1/users/{user}/shortcuts)
- [ get/api/v1/users/{user}/shortcuts/{shortcut}](https://memos.apidocumentation.com/reference#tag/shortcutservice/get/api/v1/users/{user}/shortcuts/{shortcut})
- [ delete/api/v1/users/{user}/shortcuts/{shortcut}](https://memos.apidocumentation.com/reference#tag/shortcutservice/delete/api/v1/users/{user}/shortcuts/{shortcut})
- [ patch/api/v1/users/{user}/shortcuts/{shortcut}](https://memos.apidocumentation.com/reference#tag/shortcutservice/patch/api/v1/users/{user}/shortcuts/{shortcut})
- [ get/api/v1/users](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users)
- [ post/api/v1/users](https://memos.apidocumentation.com/reference#tag/userservice/post/api/v1/users)
- [ get/api/v1/users/{user}](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user})
- [ delete/api/v1/users/{user}](https://memos.apidocumentation.com/reference#tag/userservice/delete/api/v1/users/{user})
- [ patch/api/v1/users/{user}](https://memos.apidocumentation.com/reference#tag/userservice/patch/api/v1/users/{user})
- [ get/api/v1/users/{user}/notifications](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user}/notifications)
- [ delete/api/v1/users/{user}/notifications/{notification}](https://memos.apidocumentation.com/reference#tag/userservice/delete/api/v1/users/{user}/notifications/{notification})
- [ patch/api/v1/users/{user}/notifications/{notification}](https://memos.apidocumentation.com/reference#tag/userservice/patch/api/v1/users/{user}/notifications/{notification})
- [ get/api/v1/users/{user}/personalAccessTokens](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user}/personalAccessTokens)
- [ post/api/v1/users/{user}/personalAccessTokens](https://memos.apidocumentation.com/reference#tag/userservice/post/api/v1/users/{user}/personalAccessTokens)
- [ delete/api/v1/users/{user}/personalAccessTokens/{personalAccessToken}](https://memos.apidocumentation.com/reference#tag/userservice/delete/api/v1/users/{user}/personalAccessTokens/{personalAccessToken})
- [ get/api/v1/users/{user}/settings](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user}/settings)
- [ get/api/v1/users/{user}/settings/{setting}](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user}/settings/{setting})
- [ patch/api/v1/users/{user}/settings/{setting}](https://memos.apidocumentation.com/reference#tag/userservice/patch/api/v1/users/{user}/settings/{setting})
- [ get/api/v1/users/{user}/webhooks](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user}/webhooks)
- [ post/api/v1/users/{user}/webhooks](https://memos.apidocumentation.com/reference#tag/userservice/post/api/v1/users/{user}/webhooks)
- [ delete/api/v1/users/{user}/webhooks/{webhook}](https://memos.apidocumentation.com/reference#tag/userservice/delete/api/v1/users/{user}/webhooks/{webhook})
- [ patch/api/v1/users/{user}/webhooks/{webhook}](https://memos.apidocumentation.com/reference#tag/userservice/patch/api/v1/users/{user}/webhooks/{webhook})
- [ get/api/v1/users/{user}:getStats](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users/{user}:getStats)
- [ get/api/v1/users:stats](https://memos.apidocumentation.com/reference#tag/userservice/get/api/v1/users:stats)

ListUsers returns a list of users.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of users to return. The service may return fewer than this value. If unspecified, at most 50 users will be returned. The maximum value is 1000; values above 1000 will be coerced to 1000.
- pageToken

  Type: string

  Optional. A page token, received from a previous `ListUsers` call. Provide this to retrieve the subsequent page.
- filter

  Type: string

  Optional. Filter to apply to the list results. Example: "username \=\= 'steven'" Supported operators: \=\= Supported fields: username
- showDeleted

  Type: boolean

  Optional. If true, show deleted users in the response.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/users
```

Show Schema

```json
{
  "users": [
    {
      "name": "string",
      "role": "ROLE_UNSPECIFIED",
      "username": "string",
      "email": "string",
      "displayName": "string",
      "avatarUrl": "string",
      "description": "string",
      "state": "STATE_UNSPECIFIED",
      "createTime": "2026-01-27T11:23:52.606Z",
      "updateTime": "2026-01-27T11:23:52.606Z"
    }
  ],
  "nextPageToken": "string",
  "totalSize": 1
}
```

OK

CreateUser creates a new user.

Query Parameters

- userId

  Type: string

  Optional. The user ID to use for this user. If empty, a unique ID will be generated. Must match the pattern [a-z0-9-]+
- validateOnly

  Type: boolean

  Optional. If set, validate the request but don't actually create the user.
- requestId

  Type: string

  Optional. An idempotency token that can be used to ensure that multiple requests to create a user have the same result.

Body

required

application/json

- name

  Type: string

  The resource name of the user. Format: users/{user}
- role

  Type: string

  Format: enum

  enum

  required

  The role of the user.

  - ROLE\_UNSPECIFIED
  - ADMIN
  - USER
- username

  Type: string

  required

  Required. The unique username for login.
- email

  Type: string

  Optional. The email address of the user.
- displayName

  Type: string

  Optional. The display name of the user.
- avatarUrl

  Type: string

  Optional. The avatar URL of the user.
- description

  Type: string

  Optional. The description of the user.
- password

  Type: string

  write-only

  Input only. The password for the user.
- state

  Type: string

  Format: enum

  enum

  required

  The state of the user.

  - STATE\_UNSPECIFIED
  - NORMAL
  - ARCHIVED
- createTime

  Type: string

  Format: date-time

  read-only

  Output only. The creation timestamp.
- updateTime

  Type: string

  Format: date-time

  read-only

  Output only. The last update timestamp.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/users \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "role": "ROLE_UNSPECIFIED",
  "username": "",
  "email": "",
  "displayName": "",
  "avatarUrl": "",
  "description": "",
  "password": "",
  "state": "STATE_UNSPECIFIED"
}'
```

Show Schema

```json
{
  "name": "string",
  "role": "ROLE_UNSPECIFIED",
  "username": "string",
  "email": "string",
  "displayName": "string",
  "avatarUrl": "string",
  "description": "string",
  "state": "STATE_UNSPECIFIED",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z"
}
```

OK

GetUser gets a user by ID or username. Supports both numeric IDs and username strings:

- users/{id} (e.g., users/101)
- users/{username} (e.g., users/steven)

Path Parameters

- user

  Type: string

  required

  The user id.

Query Parameters

- readMask

  Type: string

  Format: field-mask

  Optional. The fields to return in the response. If not specified, all fields are returned.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}'
```

Show Schema

```json
{
  "name": "string",
  "role": "ROLE_UNSPECIFIED",
  "username": "string",
  "email": "string",
  "displayName": "string",
  "avatarUrl": "string",
  "description": "string",
  "state": "STATE_UNSPECIFIED",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z"
}
```

OK

DeleteUser deletes a user.

Path Parameters

- user

  Type: string

  required

  The user id.

Query Parameters

- force

  Type: boolean

  Optional. If set to true, the user will be deleted even if they have associated data.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}' \
  --request DELETE
```

No Body

OK

UpdateUser updates a user.

Path Parameters

- user

  Type: string

  required

  The user id.

Query Parameters

- updateMask

  Type: string

  Format: field-mask

  Required. The list of fields to update.
- allowMissing

  Type: boolean

  Optional. If set to true, allows updating sensitive fields.

Body

required

application/json

- name

  Type: string

  The resource name of the user. Format: users/{user}
- role

  Type: string

  Format: enum

  enum

  required

  The role of the user.

  - ROLE\_UNSPECIFIED
  - ADMIN
  - USER
- username

  Type: string

  required

  Required. The unique username for login.
- email

  Type: string

  Optional. The email address of the user.
- displayName

  Type: string

  Optional. The display name of the user.
- avatarUrl

  Type: string

  Optional. The avatar URL of the user.
- description

  Type: string

  Optional. The description of the user.
- password

  Type: string

  write-only

  Input only. The password for the user.
- state

  Type: string

  Format: enum

  enum

  required

  The state of the user.

  - STATE\_UNSPECIFIED
  - NORMAL
  - ARCHIVED
- createTime

  Type: string

  Format: date-time

  read-only

  Output only. The creation timestamp.
- updateTime

  Type: string

  Format: date-time

  read-only

  Output only. The last update timestamp.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "role": "ROLE_UNSPECIFIED",
  "username": "",
  "email": "",
  "displayName": "",
  "avatarUrl": "",
  "description": "",
  "password": "",
  "state": "STATE_UNSPECIFIED"
}'
```

Show Schema

```json
{
  "name": "string",
  "role": "ROLE_UNSPECIFIED",
  "username": "string",
  "email": "string",
  "displayName": "string",
  "avatarUrl": "string",
  "description": "string",
  "state": "STATE_UNSPECIFIED",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z"
}
```

OK

ListUserNotifications lists notifications for a user.

Path Parameters

- user

  Type: string

  required

  The user id.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Signed 32-bit integers (commonly used integer type).
- pageToken

  Type: string
- filter

  Type: string

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/notifications'
```

Show Schema

```json
{
  "notifications": [
    {
      "name": "string",
      "sender": "string",
      "status": "STATUS_UNSPECIFIED",
      "createTime": "2026-01-27T11:23:52.606Z",
      "type": "TYPE_UNSPECIFIED",
      "activityId": 1
    }
  ],
  "nextPageToken": "string"
}
```

OK

DeleteUserNotification deletes a notification.

Path Parameters

- user

  Type: string

  required

  The user id.
- notification

  Type: string

  required

  The notification id.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/notifications/{notification}' \
  --request DELETE
```

No Body

OK

UpdateUserNotification updates a notification.

Path Parameters

- user

  Type: string

  required

  The user id.
- notification

  Type: string

  required

  The notification id.

Query Parameters

- updateMask

  Type: string

  Format: field-mask

Body

required

application/json

- name

  Type: string

  read-only

  The resource name of the notification. Format: users/{user}/notifications/{notification}
- sender

  Type: string

  read-only

  The sender of the notification. Format: users/{user}
- status

  Type: string

  Format: enum

  enum

  The status of the notification.

  - STATUS\_UNSPECIFIED
  - UNREAD
  - ARCHIVED
- createTime

  Type: string

  Format: date-time

  read-only

  The creation timestamp.
- type

  Type: string

  Format: enum

  enum

  read-only

  The type of the notification.

  - TYPE\_UNSPECIFIED
  - MEMO\_COMMENT
- activityId

  Type: integer

  Format: int32

  The activity ID associated with this notification.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/notifications/{notification}' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "status": "STATUS_UNSPECIFIED",
  "activityId": 1
}'
```

Show Schema

```json
{
  "name": "string",
  "sender": "string",
  "status": "STATUS_UNSPECIFIED",
  "createTime": "2026-01-27T11:23:52.606Z",
  "type": "TYPE_UNSPECIFIED",
  "activityId": 1
}
```

OK

ListPersonalAccessTokens returns a list of Personal Access Tokens (PATs) for a user. PATs are long-lived tokens for API/script access, distinct from short-lived JWT access tokens.

Path Parameters

- user

  Type: string

  required

  The user id.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of tokens to return.
- pageToken

  Type: string

  Optional. A page token for pagination.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/personalAccessTokens'
```

Show Schema

```json
{
  "personalAccessTokens": [
    {
      "name": "string",
      "description": "string",
      "createdAt": "2026-01-27T11:23:52.606Z",
      "expiresAt": "2026-01-27T11:23:52.606Z",
      "lastUsedAt": "2026-01-27T11:23:52.606Z"
    }
  ],
  "nextPageToken": "string",
  "totalSize": 1
}
```

OK

CreatePersonalAccessToken creates a new Personal Access Token for a user. The token value is only returned once upon creation.

Path Parameters

- user

  Type: string

  required

  The user id.

Body

required

application/json

- parent

  Type: string

  required

  Required. The parent resource where this token will be created. Format: users/{user}
- description

  Type: string

  Optional. Description of the personal access token.
- expiresInDays

  Type: integer

  Format: int32

  Optional. Expiration duration in days (0 \= never expires).

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/personalAccessTokens' \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "parent": "",
  "description": "",
  "expiresInDays": 1
}'
```

Show Schema

```json
{
  "personalAccessToken": {
    "name": "string",
    "description": "string",
    "createdAt": "2026-01-27T11:23:52.606Z",
    "expiresAt": "2026-01-27T11:23:52.606Z",
    "lastUsedAt": "2026-01-27T11:23:52.606Z"
  },
  "token": "string"
}
```

OK

DeletePersonalAccessToken deletes a Personal Access Token.

Path Parameters

- user

  Type: string

  required

  The user id.
- personalAccessToken

  Type: string

  required

  The personalAccessToken id.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/personalAccessTokens/{personalAccessToken}' \
  --request DELETE
```

No Body

OK

ListUserSettings returns a list of user settings.

Path Parameters

- user

  Type: string

  required

  The user id.

Query Parameters

- pageSize

  Type: integer

  Format: int32

  Optional. The maximum number of settings to return. The service may return fewer than this value. If unspecified, at most 50 settings will be returned. The maximum value is 1000; values above 1000 will be coerced to 1000.
- pageToken

  Type: string

  Optional. A page token, received from a previous `ListUserSettings` call. Provide this to retrieve the subsequent page.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/settings'
```

Show Schema

```json
{
  "settings": [
    {
      "name": "string",
      "generalSetting": {
        "locale": "",
        "memoVisibility": "",
        "theme": ""
      },
      "webhooksSetting": {
        "webhooks": [
          {
            "name": "",
            "url": "",
            "displayName": ""
          }
        ]
      }
    }
  ],
  "nextPageToken": "string",
  "totalSize": 1
}
```

OK

GetUserSetting returns the user setting.

Path Parameters

- user

  Type: string

  required

  The user id.
- setting

  Type: string

  required

  The setting id.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/settings/{setting}'
```

Show Schema

```json
{
  "name": "string",
  "generalSetting": {
    "locale": "",
    "memoVisibility": "",
    "theme": ""
  },
  "webhooksSetting": {
    "webhooks": [
      {
        "name": "",
        "url": "",
        "displayName": ""
      }
    ]
  }
}
```

OK

UpdateUserSetting updates the user setting.

Path Parameters

- user

  Type: string

  required

  The user id.
- setting

  Type: string

  required

  The setting id.

Query Parameters

- updateMask

  Type: string

  Format: field-mask

  Required. The list of fields to update.

Body

required

application/json

- name

  Type: string

  The name of the user setting. Format: users/{user}/settings/{setting}, {setting} is the key for the setting. For example, "users/123/settings/GENERAL" for general settings.
- generalSetting

  Type: object

  General user settings configuration.
- webhooksSetting

  Type: object

  User webhooks configuration.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/settings/{setting}' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "generalSetting": {
    "locale": "",
    "memoVisibility": "",
    "theme": ""
  },
  "webhooksSetting": {
    "webhooks": [
      {
        "name": "",
        "url": "",
        "displayName": ""
      }
    ]
  }
}'
```

Show Schema

```json
{
  "name": "string",
  "generalSetting": {
    "locale": "",
    "memoVisibility": "",
    "theme": ""
  },
  "webhooksSetting": {
    "webhooks": [
      {
        "name": "",
        "url": "",
        "displayName": ""
      }
    ]
  }
}
```

OK

ListUserWebhooks returns a list of webhooks for a user.

Path Parameters

- user

  Type: string

  required

  The user id.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/webhooks'
```

Show Schema

```json
{
  "webhooks": [
    {
      "name": "string",
      "url": "string",
      "displayName": "string",
      "createTime": "2026-01-27T11:23:52.606Z",
      "updateTime": "2026-01-27T11:23:52.606Z"
    }
  ]
}
```

OK

CreateUserWebhook creates a new webhook for a user.

Path Parameters

- user

  Type: string

  required

  The user id.

Body

required

application/json

- name

  Type: string

  The name of the webhook. Format: users/{user}/webhooks/{webhook}
- url

  Type: string

  The URL to send the webhook to.
- displayName

  Type: string

  Optional. Human-readable name for the webhook.
- createTime

  Type: string

  Format: date-time

  read-only

  The creation time of the webhook.
- updateTime

  Type: string

  Format: date-time

  read-only

  The last update time of the webhook.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/webhooks' \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "url": "",
  "displayName": ""
}'
```

Show Schema

```json
{
  "name": "string",
  "url": "string",
  "displayName": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z"
}
```

OK

DeleteUserWebhook deletes a webhook for a user.

Path Parameters

- user

  Type: string

  required

  The user id.
- webhook

  Type: string

  required

  The webhook id.

Responses

- ‍
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/webhooks/{webhook}' \
  --request DELETE
```

No Body

OK

UpdateUserWebhook updates an existing webhook for a user.

Path Parameters

- user

  Type: string

  required

  The user id.
- webhook

  Type: string

  required

  The webhook id.

Query Parameters

- updateMask

  Type: string

  Format: field-mask

  The list of fields to update.

Body

required

application/json

- name

  Type: string

  The name of the webhook. Format: users/{user}/webhooks/{webhook}
- url

  Type: string

  The URL to send the webhook to.
- displayName

  Type: string

  Optional. Human-readable name for the webhook.
- createTime

  Type: string

  Format: date-time

  read-only

  The creation time of the webhook.
- updateTime

  Type: string

  Format: date-time

  read-only

  The last update time of the webhook.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}/webhooks/{webhook}' \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data '{
  "name": "",
  "url": "",
  "displayName": ""
}'
```

Show Schema

```json
{
  "name": "string",
  "url": "string",
  "displayName": "string",
  "createTime": "2026-01-27T11:23:52.606Z",
  "updateTime": "2026-01-27T11:23:52.606Z"
}
```

OK

GetUserStats returns statistics for a specific user.

Path Parameters

- user

  Type: string

  required

  The user id.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl 'https://memos.apidocumentation.com/api/v1/users/{user}:getStats'
```

Show Schema

```json
{
  "name": "string",
  "memoDisplayTimestamps": [
    "2026-01-27T11:23:52.606Z"
  ],
  "memoTypeStats": {
    "linkCount": 1,
    "codeCount": 1,
    "todoCount": 1,
    "undoCount": 1
  },
  "tagCount": {
    "propertyName*": 1
  },
  "pinnedMemos": [
    "string"
  ],
  "totalMemoCount": 1
}
```

OK

ListAllUserStats returns statistics for all users.

Responses

- application/json
- application/json

Selected HTTP client: Shell Curl

```curl
curl https://memos.apidocumentation.com/api/v1/users:stats
```

Show Schema

```json
{
  "stats": [
    {
      "name": "string",
      "memoDisplayTimestamps": [
        "2026-01-27T11:23:52.606Z"
      ],
      "memoTypeStats": {
        "linkCount": 1,
        "codeCount": 1,
        "todoCount": 1,
        "undoCount": 1
      },
      "tagCount": {
        "propertyName*": 1
      },
      "pinnedMemos": [
        "string"
      ],
      "totalMemoCount": 1
    }
  ]
}
```

OK
