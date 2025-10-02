---
{
  "title": "Build",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to build your projects efficiently."
}
---
# 构建 {#build｝

项目通常通过构建系统提供的 CLI（如`xcodebuild` ）构建。Tuist 对其进行包装，以改善用户体验，并将工作流程与平台集成，以提供优化和分析功能。

您可能会问，使用`tuist build` 比使用`tuist generate` （如果需要）生成项目并使用特定平台的 CLI
构建项目有什么价值？以下是一些原因：

- **单个命令：** `tuist build` 确保在编译项目前根据需要生成项目。
- **美化输出：** Tuist 使用 [xcbeautify](https://github.com/cpisciotta/xcbeautify)
  等工具丰富输出结果，使输出结果更方便用户使用。
- <LocalizedLink href="/guides/features/cache"><bold>缓存：{1｝它通过确定性地重复使用远程缓存中的构建工件来优化构建过程。
- **分析：** 它收集并报告与其他数据点相关联的指标，为您提供可操作的信息，以便您做出明智的决策。

## 用法 {#usage｝

`tuist build` 在需要时生成项目，然后使用特定平台的构建工具进行构建。我们支持使用`--`
终结器，将所有后续参数直接转发给底层构建工具。当您需要传递`tuist build` 不支持但底层构建工具支持的参数时，这将非常有用。

代码组
```bash [Build a scheme]
tuist build MyScheme
```
```bash [Build a specific configuration]
tuist build MyScheme -- -configuration Debug
```
```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```
:::
