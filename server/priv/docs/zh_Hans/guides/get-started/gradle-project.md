---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist for a shared remote build cache, build and test insights across CI, bundle-size tracking, and preview links."
}
---
# Gradle 项目 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

按照此路径将现有的 Gradle 项目指向 Tuist。`dev.tuist` Gradle 插件将 Gradle 的本地构建缓存连接到 Tuist 的远程缓存，并将构建和测试数据上传到仪表板，而无需更改任何 `./gradlew` 命令。

下面的每个部分首先介绍当前缺失的内容，然后引导你了解填补这一空白的功能。

## 前提条件

- 一个包含 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 项目。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 连接项目

在 Gradle 项目的根目录下运行 `tuist init`。选择 **集成 Gradle 项目**，然后在浏览器中进行身份验证并选择应拥有该项目的账户。

```bash
tuist init
```

如果你是通过编码代理或脚本执行此操作，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互式表单：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 会在仓库根目录写入一个包含项目句柄的 `tuist.toml`，并打印一个 `plugins { ... }` 块。将其粘贴到 `settings.gradle.kts` 的顶部：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

使用 `./gradlew help` 进行健全性检查。Gradle 应该无错误加载。如果找不到插件，请确保该块位于 `settings.gradle.kts` 中，而不是 `build.gradle.kts` 中。

以下内容均为可选且相互独立。

## 远程构建缓存

Gradle 的本地构建缓存会在生成任务输出的机器上存储这些输出。同一分支上的两名开发者会命中各自 `~/.gradle` 中的缓存，而不会命中对方的缓存，并且 CI 每次作业都会命中一个全新的空缓存。

Tuist 远程缓存扩展了 Gradle 已在跨机器使用的相同键/值协议。任务的输出会在首次执行它的机器上上传，并由其他遇到相同输入的任何用户下载。在 `gradle.properties` 中启用它：

```properties
org.gradle.caching=true
```

然后在两个环境中构建：

```bash
./gradlew clean build --build-cache --info
```

可缓存的任务在第二次运行时报告 `FROM-CACHE`。打开仪表板上的 **Cache** 以查看随时间变化的命中率。

## 构建洞察

Gradle 在构建结束时发出任务计时信息，并使用 `--profile` 编写每个构建的 HTML 报告。两者都不会跨运行聚合数据。在一系列提交中变慢的任务在任何单次构建的报告上看起来都与以前一样。

一旦应用了 `dev.tuist` 插件，它会自动将每次构建的任务计时信息上传到仪表板。无需额外配置。在下一次 `./gradlew build` 之后打开仪表板上的 **Builds** 以查看趋势。

## 测试洞察

Gradle 的测试报告位于每个构建下的 `build/reports/tests/` 中。在十次 CI 运行中间歇性失败的测试，在任何给定报告中看起来都像是一个偶然失败一次的稳定测试。

测试洞察记录每次 `./gradlew test` 运行的每个任务的结果和持续时间，并关联跨运行的结果。不稳定的测试、缓慢的测试和失败会显示在仪表板的 **Tests** 选项卡上。当不稳定测试累积时，从仪表板上隔离它们，以便它们不再阻止合并。

该插件还支持 **压力测试模式**，它会重新运行构建引入的测试用例，并在它们合并之前标记任何被证明不稳定的用例。将其添加到 `settings.gradle.kts` 中的 `tuist` 扩展中：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Bundle 洞察

Android Gradle Plugin 在构建输出中报告生成的 `.aab` 的大小。该数字会随着分支消失，比较不同版本之间的大小是一项手动统计工作。Play Console 报告相同的数字，但仅在工件上传之后。

Bundle 洞察记录每个 `.aab`（推荐）或 `.apk` 的安装和下载大小，并且当超过每个分支的阈值时可以使 PR 检查失败。将此内容添加到构建步骤之后的 CI 中：

```bash
tuist inspect bundle App.aab
```

打开仪表板上的 **Bundle insights → Android** 以查看趋势并配置阈值。

## 预览

Play Console 的内部测试轨道在每次共享时都会增加审查和传播延迟。通过 Slack 或电子邮件发送原始 `.apk` 更快，但无法跟踪特定消息引用的是哪个构建。

预览将构建转换为一个可共享的链接，接收者只需一条命令即可安装：

```bash
tuist share App.apk
```

## 让团队加入

缓存命中、洞察和压力测试的效果都会随着连接到项目的人数增加而复合增长。从仪表板的账户设置中邀请你的团队成员加入组织，并设置 <.localized_link href="/guides/integrations/authentication/sso">单点登录</.localized_link>（Google、Okta、Microsoft），这样入职只需点击一下，而不需要每个人单独运行 `tuist auth login`。

对于 CI，不要使用个人登录。设置范围限定为你的项目的 `TUIST_TOKEN`（从仪表板上的项目设置创建）。

## 完整插件参考

这里涵盖的所有内容都是在 Gradle 项目上使用 Tuist 获得价值的最低要求。`tuist` 扩展块、`stressNewTests` 模式和 CI 身份验证的配置选项位于 [Install the Gradle plugin](https://tuist.dev/en/docs/guides/install-gradle-plugin) 参考中。
