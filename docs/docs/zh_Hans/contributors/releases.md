---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# 运行

Tuist 采用持续发布系统，每当有意义的变更合并到主分支时，系统就会自动发布新版本。这种方法可确保改进内容迅速送达用户，而无需维护人员进行人工干预。

## 概述

我们持续发布三个主要组件：
- **Tuist CLI** - 命令行工具
- **Tuist 服务器** - 后台服务
- **Tuist 应用程序** - macOS 和 iOS 应用程序（iOS 应用程序仅持续部署到 TestFlight，请参阅
  [此处](#app-store-release)）。

每个组件都有自己的发布管道，每次推送到主分支时都会自动运行。

## 工作原理

### 1.承诺公约

我们使用 [Conventional Commits](https://www.conventionalcommits.org/)
来构建提交信息。这样，我们的工具就能理解变更的性质，确定版本升级，并生成适当的变更日志。

格式：`类型（范围）：描述`

#### 承诺类型及其影响

| 类型    | 描述       | 版本影响           | 示例                             |
| ----- | -------- | -------------- | ------------------------------ |
| `绝技`  | 新功能或能力   | 小版本升级（x.Y.z）   | `feature(cli)：添加对 Swift 6 的支持` |
| `定格`  | 错误修复     | 补丁版本的提升（x.y.Z） | `fix(app): 解决打开项目时崩溃的问题`       |
| `文档`  | 文件更改     | 未发布            | `文档：更新安装指南`                    |
| `风格`  | 代码样式更改   | 未发布            | `style：用 swiftformat 格式化代码`    |
| `重构`  | 代码重构     | 未发布            | `重构（服务器）：简化认证逻辑`               |
| `敷衍`  | 性能改进     | 补丁版本提升         | `perf(cli): 优化依赖关系解析`          |
| `测试`  | 测试增加/更改  | 未发布            | `测试：为缓存添加单元测试`                 |
| `苦差事` | 维护任务     | 未发布            | `苦差事：更新依赖关系`                   |
| `ci`  | CI/CD 变化 | 未发布            | `CI：为发布添加工作流程`                 |

#### 突破性变化

破坏性修改会触发主要版本升级（X.0.0），应在提交正文中注明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2.变化检测

每个组件都使用 [git cliff](https://git-cliff.org/) 来运行：
- 分析自上次发布以来的提交情况
- 按范围（客户端、应用程序、服务器）过滤提交
- 确定是否存在可发布的变更
- 自动生成更新日志

### 3.释放管道

检测到可释放更改时：

1. **版本计算** ：流水线确定下一个版本号
2. **更新日志生成** ：git cliff 从提交信息中创建更新日志
3. **构建过程** ：构建和测试组件
4. **发布创建** ：创建包含工件的 GitHub 发布版本
5. **发布** ：更新推送至软件包管理器（如用于 CLI 的 Homebrew）

### 4.范围过滤

每个组件只有在有相关变更时才会发布：

- **CLI**: 提交范围为`(cli)` 或无范围
- **应用程序** ：包含`(app) 的提交` 范围
- **服务器** ：`(服务器)` 范围的提交

## 编写良好的提交信息

由于提交信息会直接影响发布说明，因此编写清晰、描述性强的信息非常重要：

### 做：
- 使用现在时态："添加功能 "而不是 "增加功能"
- 简明扼要，但要有描述性
- 当更改是针对特定组件时，应包括范围
- 适用时引用问题：`fix(cli)：解决构建缓存问题 (#1234)`

### 不要
- 使用 "修复错误 "或 "更新代码 "等含糊不清的信息
- 在一次提交中混合多个不相关的更改
- 忘记包含中断更改信息

### 突破性变化

对于破坏性更改，请在提交正文中包含`BREAKING CHANGE:` ：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 发布工作流程

发布工作流程在
- `.github/workflows/cli-release.yml` - CLI 版本
- `.github/workflows/app-release.yml` - 应用程序版本
- `.github/workflows/server-release.yml` - 服务器版本

每个工作流程：
- 通过推动主电源运行
- 可手动触发
- 使用 git cliff 进行变更检测
- 处理整个发布流程

## 监测释放情况

您可以通过以下方式监测发布情况：
- [GitHub发布页面](https://github.com/tuist/tuist/releases)。
- 工作流程运行的 GitHub 操作选项卡
- 每个组件目录中的更新日志文件

## 益处

这种持续发布方法提供了

- **快速交付** ：更改合并后立即送达用户
- **减少瓶颈** ：无需等待手动发布
- **清晰的沟通** ：从提交信息中自动生成更新日志
- **一致的流程** ：所有组件的发布流程相同
- **质量保证** ：只发布经过测试的更改

## 故障排除

如果释放失败：

1. 检查 GitHub 操作日志，查看工作流程是否失败
2. 确保提交信息遵循常规格式
3. 验证所有测试通过
4. 检查组件是否成功构建

用于需要立即发布的紧急修复：
1. 确保您的承诺有明确的范围
2. 合并后，监控发布工作流程
3. 如有需要，触发手动释放装置

## 应用商店发布

虽然 CLI 和服务器遵循上述持续发布流程，但**iOS 应用程序** 是一个例外，因为苹果公司的 App Store 审核流程是这样的：

- **手动发布** ：iOS 应用程序的发布需要手动提交到 App Store
- **审核延迟** ：每个版本都必须通过苹果公司的审核流程，可能需要 1-7 天的时间
- **批量更改** ：在每个 iOS 版本中，通常会将多个更改捆绑在一起
- **TestFlight** ：测试版可在应用商店发布前通过 TestFlight 发布
- **发布说明** ：必须专为应用程序商店指南编写

iOS 应用程序仍然遵循相同的提交约定，并使用 git cliff 生成更新日志，但实际向用户发布的频率较低，而且是手动发布。
