---
{
  "title": "Gradle 项目",
  "titleTemplate": ":title · 入门指南 · 指南 · Tuist",
  "description": "将 Gradle 项目连接到 Tuist，以使用共享的远程构建缓存、获取 CI 中的构建和测试洞察、跟踪包大小以及生成预览链接。"
}
---
# Gradle 项目 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

按照此路径将现有的 Gradle 项目接入 Tuist。`dev.tuist` Gradle 插件会将 Gradle 的本地构建缓存连接到 Tuist 的远程缓存，并将构建和测试数据上传到仪表板，而无需更改任何 `./gradlew` 命令。

以下每个部分首先说明当前缺失的内容，然后引导你了解填补这一空白的功能。

## 前提条件

- 一个包含 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 项目。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 连接项目

在 Gradle 项目的根目录下运行 `tuist init`。选择 **集成 Gradle 项目**，然后在浏览器中完成身份验证，并选择应拥有该项目的账户。

```bash
tuist init
```

如果你通过编码代理或脚本执行此操作，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互式形式：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 会在仓库根目录写入包含项目句柄的 `tuist.toml`，并输出一个 `plugins { ... }` 块。将其粘贴到 `settings.gradle.kts` 的顶部：

<!-- @snippet: ../_gradle-plugin-block -->

使用 `./gradlew help` 进行健全性检查。Gradle 应该无错误加载。如果找不到插件，请确保该块位于 `settings.gradle.kts` 中，而不是 `build.gradle.kts`。

以下内容均为可选且相互独立。

## 远程构建缓存

Gradle 的本地构建缓存将任务输出存储在生成它们的机器上。同一分支上的两名开发者只会命中各自 `~/.gradle` 中的缓存，而不会命中对方的缓存；CI 每次作业都会命中一个全新的空缓存。

Tuist 远程缓存扩展了 Gradle 已在跨机器使用的相同键/值协议。任务的输出会在首次执行它的机器上上传，并由其他遇到相同输入的任何机器下载。在 `gradle.properties` 中启用它：

```properties
org.gradle.caching=true
```

然后在两个环境中构建：

```bash
./gradlew clean build --build-cache --info
```

可缓存的任务在第二次运行时会报告 `FROM-CACHE`。打开仪表板上的 **缓存** 查看随时间变化的命中率。

## 构建洞察

Gradle 在构建结束时发出任务计时信息，并使用 `--profile` 生成每次构建的 HTML 报告。两者都不会跨运行聚合数据。在一系列提交中逐渐变慢的任务，在任何单次构建的报告中看起来都与以往一样。

一旦应用了 `dev.tuist` 插件，它会自动将每次构建的任务计时上传到仪表板。无需额外配置。在下一次 `./gradlew build` 之后，打开仪表板上的 **构建** 查看趋势。

## 测试洞察

Gradle 的测试报告位于每次构建的 `build/reports/tests/` 下。在十次 CI 运行中间歇性失败的测试，在任何给定报告中看起来都像是一个偶然失败一次的稳定测试。

测试洞察记录每次 `./gradlew test` 运行中每个任务的结果和持续时间，并跨运行关联结果。不稳定测试、慢速测试和失败会显示在仪表板的 **测试** 选项卡上。当不稳定测试积累时，从仪表板隔离它们，以便它们不再阻止合并。

该插件还支持 **压力测试模式**，它会重新运行构建引入的测试用例，并在它们合并之前标记任何被证明不稳定的用例。将其添加到 `settings.gradle.kts` 中的 `tuist` 扩展：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Bundle 洞察

Android Gradle Plugin 会在构建输出中报告生成的 `.aab` 的大小。该数字会随着分支消失，跨版本比较大小是一项手动统计工作。Play Console 会报告相同的数字，但仅在构件上传之后。

Bundle 洞察记录每个 `.aab`（推荐）或 `.apk` 的安装和下载大小，并可以在超过每分支阈值时使 PR 检查失败。将此步骤添加到构建步骤之后的 CI 中：

```bash
tuist inspect bundle App.aab
```

打开仪表板上的 **Bundle 洞察 → Android** 查看趋势并配置阈值。

## 预览

Play Console 的内部测试轨道会在每次分享时增加审查和传播延迟。通过 Slack 或电子邮件发送原始 `.apk` 更快，但无法追踪特定消息引用的是哪个构建。

该插件可以直接构建并发布应用变体，无需单独的 CLI 上传：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

请求 `tuistShare<Variant>` 任务会使该次调用参与发布；普通构建从不上传预览。有关支持的 APK、签名和安装，请参阅 <.localized_link href="/guides/features/previews/gradle">Gradle 预览</.localized_link>。

## 带领团队一起使用

缓存命中、洞察和压力测试的效果会随着连接到项目的人数增加而累积。从仪表板的账户设置邀请团队成员加入组织，并设置 <.localized_link href="/guides/integrations/authentication/sso">单点登录</.localized_link>（Google、Okta、Microsoft），使入职只需点击一下，而不是每人执行一次 `tuist auth login`。

对于 CI，不要使用个人登录。使用 CI 提供商的 OIDC 身份进行身份验证，或在仪表板中使用 **CI** 预设创建账户令牌，并将其设置为 `TUIST_TOKEN`。请参阅 <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle 插件身份验证</.localized_link>。

## 完整插件参考

此处涵盖的所有内容是在 Gradle 项目中从 Tuist 获得价值的最小要求。`tuist` 扩展块、`stressNewTests` 模式和 CI 身份验证的配置选项详见 [安装 Gradle 插件](https://tuist.dev/en/docs/guides/install-gradle-plugin) 参考。
