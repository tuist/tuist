## 标签 {#tags}

上传 bundle 时附加标签，以区分构建变体、环境或发布渠道。Bundle 标签遵循与构建洞察标签相同的约定：

```bash
tuist inspect bundle App.ipa --tags paid production
```

在 CI 中，你也可以使用 `TUIST_BUNDLE_TAGS` 设置逗号分隔的标签：

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

显式的 `--tags` 会替换环境变量中的标签。标签可以包含字母、数字、连字符和下划线，每个 bundle 最多 10 个标签，每个标签最多 50 个字符。同样的选项也适用于 Android bundle。`--json` 仅在本地运行，不会上传标签或 bundle。

标签显示在 bundle 名称旁边以及 bundle 详情中。使用仪表板的 **标签** 过滤器并输入标签，以在 bundle 列表中将其包含或排除。匹配是精确且区分大小写的，即使过滤器操作符标记为 **包含** 和 **不包含**：`paid` 不匹配 `paid-extra`。要从 CLI 进行过滤：

```bash
tuist bundle list --tags paid production
```

CLI、API（`?tags=paid,production`）和 MCP `list_bundles` 工具（`tags: ["paid", "production"]`）返回包含 **所有** 指定标签的 bundle。API 上传接受 `bundle.custom_metadata.tags`；列表和详情响应返回 `custom_metadata.tags`。现有没有标签的 bundle 仍然像以前一样可用。标签用于过滤 bundle 列表；它们不会更改大小图表或自动比较和阈值基线。

现有客户端可以继续上传和读取没有标签的 bundle。更新后的客户端也可以读取来自省略 `custom_metadata` 的旧服务器的响应。存储和过滤标签需要支持 bundle 标签的服务器版本：旧服务器会忽略上传元数据并拒绝标签过滤器。当未提供标签时，更新后的客户端会省略上传元数据和标签查询参数。

## 理解 bundle 大小 {#understanding-sizes}

对于每个分析的 bundle，Tuist 报告两个值：

- **安装大小**：应用安装在设备上后占用的空间。
- **下载大小**：用户下载的压缩大小。对于 Apple bundle，这仅针对 `.ipa`（归档文件的大小）报告；对于 `.xcarchive` 或 `.app` 输入则不可用。

大小以字节为单位存储，并使用十进制惯例显示，其中 1 MB 为 1,000,000 字节，1 GB 为 1,000,000,000 字节——这与 Apple 用于报告存储和应用大小的惯例相同（参见 [Apple 设备上如何测量存储容量](https://support.apple.com/en-us/102119)）。733,446,863 字节的安装大小显示为 733.4 MB。

## 持续集成 {#continuous-integration}

要跟踪 bundle 大小随时间的变化，请在 CI 上分析 bundle。首先，确保你的 CI 已 <.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。

Tuist 还需要知道将 bundle 报告到哪个项目。如果你尚未连接项目，请运行 `tuist init`，或自行声明句柄：

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

对于没有 Swift 清单的项目（例如 Gradle 项目），请使用 <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link>。当两个文件都存在时，`Tuist.swift` 优先。

GitHub Actions 工作流示例：

::: code-group
```yaml [Apple]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

设置完成后，你可以看到 bundle 大小随时间的变化：

![Bundle 大小图表](/images/guides/features/bundle-size/bundle-size-graph.png)

## 拉取/合并请求评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要与 Git 平台集成**
>
> 要获取自动拉取/合并请求评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 项目</.localized_link> 与 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。

一旦你的 Tuist 项目与你的 Git 平台（如 [GitHub](https://github.com)）连接，每当你运行 `tuist inspect bundle` 时，Tuist 都会直接在拉取/合并请求中发布评论：

![带有已检查 bundle 的 GitHub 应用评论](/images/guides/features/bundle-size/github-app-with-bundles.png)

## 大小阈值 {#size-thresholds}

> [!WARNING]
> **需要与 Git Forge 集成**
>
> 要使用大小阈值，请将 [Tuist GitHub App](https://github.com/apps/tuist) 连接到你的项目。你可以在项目的集成页面执行此操作。

大小阈值允许你在 bundle 大小相对于基线分支增加超过配置的百分比或绝对大小时阻止拉取请求。当违反阈值时，Tuist 会在 PR 提交上创建 GitHub Check Run，阻止合并直到解决大小增加问题：

![显示 bundle 大小阈值超出的 PR 状态检查](/images/guides/features/bundle-size/github-pr-check-status.png)

Check Run 显示基线大小、当前大小以及配置单位的变化。如果增加是有意的，你可以通过单击 **接受** 按钮直接从 GitHub UI 接受它：

![显示阈值违规的 GitHub check run](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 配置 {#size-thresholds-configuration}

要配置阈值，请转到项目的 **设置 > Bundles** 选项卡：

![Bundle 大小阈值设置](/images/guides/features/bundle-size/bundle-size-thresholds.png)

选择 **安装大小** 或 **下载大小**，然后选择 **阈值类型**：

- **百分比 (%)**：限制相对于基线大小的增长。支持小数百分比，例如 `0.47`。现有的百分比阈值保留其配置的值和行为。
- **绝对大小 (MB)**：限制固定数量的增长，与基线大小无关。输入 `1.5` 以允许最多 1.5 MB 的增长。MB 使用十进制单位：1 MB = 1,000,000 字节。值必须解析为正整数字节数。

![绝对 bundle 大小增长阈值配置](/images/guides/features/bundle-size/absolute-size-threshold.png)

两种类型都会与配置的 **基线分支** 上最新的 bundle 进行比较，要求名称相同、bundle 类型相同（例如 `.app` 或 `.ipa`），并且至少有一个共同的平台，因此模拟器 `.app` 仅与模拟器 `.app` 上传进行比较。可选的 **Bundle 名称** 将规则限制为该 bundle。仅当增长 **超过** 限制时检查才会失败；增长相等、大小不变和减少则通过。如果没有匹配的基线或所选指标没有记录的大小，则会跳过该规则。绝对限制支持零大小基线；百分比限制会继续跳过它，因为百分比增长未定义。

### 限制谁可以接受 {#size-thresholds-approvals}

默认情况下，任何对仓库具有写入权限的人都可以接受大小增加，因为 GitHub 会向这些人显示该按钮。要缩小范围，请在 **设置 > Bundles** 下设置 **谁可以接受**：

- **任何人**：默认值。任何对仓库具有写入权限的人。
- **选定的 GitHub 用户**：仅限你添加的 GitHub 用户名。

不在列表中的人会使检查保持失败状态并附带解释，按钮仍保留给可以使用它的人。
