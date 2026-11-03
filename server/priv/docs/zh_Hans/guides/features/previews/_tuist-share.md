## 使用 tuist share 的渠道 {#share-tracks}

对于通过 `tuist share` 发布的工作流，使用 `--track` 选择渠道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 发布说明 {#release-notes}

使用渠道区分环境组，使用发布说明标识单次构建的目的：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

将 `App` 替换为你的应用名称、应用文件路径或可执行分发及其 `--executable` 选项。发布说明是可选的纯文本，最多 10,000 个字符。首个非空行会在预览列表中以单行摘要形式显示，因此构建编号和其他识别信息一目了然。长行会被截断；完整说明会出现在详情页面。搜索会匹配显示名称和完整发布说明，包括未在摘要中显示的行。支持多行说明，例如 `--release-notes "$(< release-notes.txt)"`。它们不会更改应用的显示名称或其渠道。

### 兼容性 {#preview-metadata-compatibility}

发布说明是附加元数据，不属于预览的身份标识。来自旧版和新版客户端的上传仍会在各平台归入同一预览。首个非空说明会被保留：后续上传可以补充此前缺失的说明，但无法覆盖已有说明。省略 `release_notes`、发送 `null`，或发送空字符串或仅含空白字符的字符串都不会清除说明。现有预览不会回填，且在没有说明的情况下仍然有效。

列表 API 的可选查询参数 `track` 会不区分大小写地匹配完整渠道名称，与现有渠道存储保持一致。省略该参数或发送空值（`?track=`）以列出所有渠道。渠道名称仍是开放字符串，而非固定值列表。`GET /api/projects/:account_handle/:project_handle/previews/tracks` 返回 `{total_count, tracks: [{name, count}]}`，其中包含按名称排序且不区分大小写分组的渠道，其读取权限与列出构建时相同。计数覆盖整个项目，独立于分页、搜索和所选渠道；总数包含未跟踪渠道的预览。仅对具有包标识符且可列出的预览进行计数。列表 API 还接受可选的 `search`，用于对显示名称或完整发布说明进行字面量、不区分大小写的子串匹配，并在分页前与渠道条件组合。现有的 `display_name` 过滤仍为精确匹配。

旧版客户端可以继续在不发送任一字段的情况下上传和列出预览。新版客户端接受省略渠道或说明的旧响应，并忽略未来服务器添加的未知响应属性。API 集成也应忽略未知响应属性，以确保附加元数据的兼容性。

自托管部署需要支持发布说明和渠道过滤的服务器版本，以及更新的客户端，才能使用这些功能。较旧的服务器可能会忽略说明或未知查询参数。

## 拉取/合并请求评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要与 Git 平台集成**
>
> 要获取自动化的拉取/合并请求评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">远程项目</.localized_link> 与 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。

将 Tuist 项目与 Git 平台连接后，在 CI 中成功构建应用后添加 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 会直接在拉取/合并请求中发布预览链接，以便评审者无需本地构建即可测试：

![带有 Tuist Preview 链接的 GitHub 应用评论](/images/guides/features/github-app-with-preview.png)

## 自动化 {#automations}

使用 `--json` 从 `tuist share` 获取 JSON 输出：

```bash
tuist share --json
```

将结果用于自定义自动化，例如从 CI 发布 Slack 消息。`url` 键包含完整的预览链接；`qrCodeURL` 指向用于在设备上打开预览的二维码图片：

```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
