## 使用 tuist share 管理渠道 {#share-tracks}

对于使用 `tuist share` 发布的工作流，请使用 `--track` 选择渠道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 发布说明 {#release-notes}

使用渠道对环境进行分组，并使用发布说明描述单个构建的用途：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

将 `App` 替换为你的应用名称、应用文件路径或可执行分发包及其 `--executable` 选项。发布说明为可选的纯文本，最多 10,000 个字符。首个非空行会在预览列表中以单行摘要形式显示，因此构建版本号和其他标识信息一目了然。过长的行会被截断；完整说明会显示在详情页中。搜索会匹配显示名称和完整的发布说明，包括未在摘要中显示的行。支持多行说明，例如 `--release-notes "$(< release-notes.txt)"`。它们不会更改应用的显示名称或其所属渠道。

### 兼容性 {#preview-metadata-compatibility}

发布说明不会改变构建所属的预览。预览接收的首批说明会被保留：后续上传可以为尚无说明的预览添加说明，但无法覆盖或清除现有说明。在发布说明功能推出之前上传的预览在没有说明的情况下仍然有效。

自托管部署需要支持发布说明和渠道过滤的服务器版本，以及更新后的客户端。较旧的服务器会忽略这些说明。有关列表端点的渠道和搜索过滤器，请参阅 [API 参考](https://tuist.dev/api/docs)。

## 拉取请求/合并请求评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要集成 Git 代码托管平台**
>
> 要获得自动的拉取请求/合并请求评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">远程项目</.localized_link> 与 <.localized_link href="/guides/integrations/gitforge/github">Git 代码托管平台</.localized_link> 集成。

一旦你的 Tuist 项目与 Git 平台连接，请在 CI 中成功构建应用后添加 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 会直接在拉取请求/合并请求中发布预览链接，以便评审者无需在本地构建即可测试：

![带有 Tuist Preview 链接的 GitHub 应用评论](/images/guides/features/github-app-with-preview.png)

## 自动化 {#automations}

使用 `--json` 从 `tuist share` 获取 JSON 输出：

```bash
tuist share --json
```

利用结果进行自定义自动化，例如从 CI 发布 Slack 消息。`url` 键包含完整的预览链接；`qrCodeURL` 指向用于在设备上打开预览的二维码图片：

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
