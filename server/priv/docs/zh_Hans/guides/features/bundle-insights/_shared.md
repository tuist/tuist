## 了解包大小 {#understanding-sizes}

对于每个分析的包，Tuist 会报告两个值：

- **安装大小**：应用安装在设备上后占用的空间。
- **下载大小**：用户下载的压缩大小。对于 Apple 包，此信息仅针对 `.ipa`（归档文件的大小）提供；对于 `.xcarchive` 或 `.app` 输入则不可用。

大小以字节为单位存储，并使用十进制惯例显示，其中 1 MB 为 1,000,000 字节，1 GB 为 1,000,000,000 字节——这与 Apple 报告存储和应用大小所使用的惯例相同（参见 [Apple 设备上的存储容量如何衡量](https://support.apple.com/en-us/102119)）。733,446,863 字节的安装大小将显示为 733.4 MB。

## 持续集成 {#continuous-integration}

要随时间跟踪包大小，请在 CI 上分析包。首先，确保你的 CI 已 <.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。

Tuist 还需要知道应将包报告到哪个项目。如果你尚未连接项目，请运行 `tuist init`，或自行声明句柄：

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

设置完成后，你可以查看包大小随时间的变化情况：

![包大小图表](/images/guides/features/bundle-size/bundle-size-graph.png)

## 拉取/合并请求评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要与 Git 平台集成**
>
> 要获取自动拉取/合并请求评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 项目</.localized_link> 与 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。

一旦你的 Tuist 项目与 Git 平台（如 [GitHub](https://github.com)）连接，每当你运行 `tuist inspect bundle` 时，Tuist 都会直接在拉取/合并请求中发布评论：

![带有检查包的 GitHub 应用评论](/images/guides/features/bundle-size/github-app-with-bundles.png)

## 大小阈值 {#size-thresholds}

> [!WARNING]
> **需要与 Git 代码托管平台集成**
>
> 要使用大小阈值，请将 [Tuist GitHub App](https://github.com/apps/tuist) 连接到你的项目。你可以在项目的集成页面执行此操作。

大小阈值允许你在包大小相对于基准分支增加超过配置的百分比或绝对大小时阻止拉取请求。当违反阈值时，Tuist 会在 PR 提交上创建 GitHub Check Run，阻止合并，直到解决大小增加问题：

![显示超出包大小阈值的 PR 状态检查](/images/guides/features/bundle-size/github-pr-check-status.png)

Check Run 显示基准大小、当前大小以及以配置单位表示的变化。如果增加是有意为之，你可以直接在 GitHub UI 中点击 **接受** 按钮来接受：

![显示违反阈值的 GitHub Check Run](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 配置 {#size-thresholds-configuration}

要配置阈值，请转到项目的 **设置 > 包** 选项卡：

![包大小阈值设置](/images/guides/features/bundle-size/bundle-size-thresholds.png)

选择 **安装大小** 或 **下载大小**，然后选择 **阈值类型**：

- **百分比 (%)**：限制相对于基准大小的增长。支持小数百分比，例如 `0.47`。现有的百分比阈值保留其配置的值和行为。
- **绝对大小 (MB)**：按固定数量限制增长，与基准大小无关。输入 `1.5` 以允许最多 1.5 MB 的增长。MB 使用十进制单位：1 MB = 1,000,000 字节。值必须解析为正整数字节数。

![绝对包大小增长阈值配置](/images/guides/features/bundle-size/absolute-size-threshold.png)

两种类型都与配置的 **基准分支** 上的最新包进行比较，该包具有相同的名称、相同的包类型（例如 `.app` 或 `.ipa`），并且至少有一个共同的平台，因此模拟器 `.app` 仅与模拟器 `.app` 上传进行比较。可选的 **包名称** 将规则限制为该包。仅当增长 **超过** 限制时，检查才会失败；相等增长、大小不变和减少均通过。如果没有匹配的基准或所选指标的记录大小，则跳过该规则。绝对限制支持零大小基准；百分比限制会继续跳过它，因为百分比增长未定义。

### 限制谁可以接受 {#size-thresholds-approvals}

默认情况下，任何对仓库具有写入权限的人都可以接受大小增加，因为 GitHub 向这些人显示该按钮。要缩小范围，请在 **设置 > 包** 下设置 **谁可以接受**：

- **任何人**：默认值。任何对仓库具有写入权限的人。
- **选定的 GitHub 用户**：仅限你添加的 GitHub 用户名。

不在列表中的人会使检查保持失败状态并附带解释，按钮仍保留给可以使用它的人。
