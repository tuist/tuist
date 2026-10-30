---
{
  "title": "Gradle 测试洞察",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Gradle 测试分析数据，以监控测试性能。"
}
---
# Gradle 测试洞察 {#gradle-test-insights}

Tuist 的 Gradle 插件会在每次测试任务执行后自动上传测试结果，让你直接在 Tuist 仪表盘中查看测试性能和不稳定测试。

应用 Tuist Gradle 插件后会自动收集测试洞察——除了初始插件设置外，无需额外配置。

你可以在 Tuist 仪表盘中访问测试洞察，并查看其随时间的变化：

![带有测试洞察的仪表盘](/images/guides/features/build-insights/tests-dashboard.png)

## 跟踪内容 {#what-is-tracked}

该插件会收集所有 Gradle `Test` 任务的结果，包括：
- 单个测试用例的通过/失败状态和耗时
- 测试套件和类结构
- 跨运行检测不稳定测试

## 配置上传行为 {#configure-upload-behavior}

默认情况下：
- 本地构建的测试结果在后台上传。
- CI 运行的测试结果在前台上传，以避免在短暂存在的代理上丢失遥测数据。

你可以通过在 `settings.gradle.kts` 中的 `tuist` 块中使用 `uploadInBackground` 来覆盖此行为：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 历史 {#git-history}

在 CI 上，插件在报告测试运行时还会上传检出目录的提交历史：提交 SHA、其父提交、提交日期，以及运行所在分支及其拉取请求的基础分支。不会上传文件内容、提交消息或作者信息。这能让 Tuist 知道哪些提交已合并到你的默认分支，例如合并队列测试过的提交。插件会读取检出目录中已有的历史，如果检出目录中没有基础分支，则会向远程查询其最新提交（`git ls-remote`）。它不会获取历史记录。

| 变量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不读取或上传任何 Git 历史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 仅读取检出目录，不与远程通信。 |
