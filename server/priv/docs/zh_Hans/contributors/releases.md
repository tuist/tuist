---
{
  "title": "发布版本",
  "titleTemplate": ":title | 贡献者 | Tuist",
  "description": "了解 Tuist 的持续发布流程如何运作"
}
---
# 发布

当变更合并到主分支时，Tuist 会自动发布新版本。CLI、服务器和 Kura 缓存服务器都通过发布渠道（canary、release candidate、stable）进行交付，以确保推荐安装的版本保持稳定且更新节奏平缓；切出 release candidate 并将其提升为 stable 是每周有计划地执行的步骤。应用持续发布（iOS 应用仅持续部署到 TestFlight，详见[此处](#app-store-release)）。

## 概览

我们发布以下主要组件：
- **Tuist CLI** - 命令行工具，通过 canary、release candidate 和 stable [渠道](#release-channels)交付
- **Tuist Server** - 后端服务，采用与 CLI 相同的渠道模型交付
- **Kura** - 缓存服务器，采用与 CLI 相同的渠道模型交付
- **Tuist App** - macOS 和 iOS 应用，持续发布（iOS 应用仅持续部署到 TestFlight，详见[此处](#app-store-release)）

每次向 `main` 推送都会为 CLI、服务器和 Kura 发布 canary 预发布版本。只有当维护者将经过充分验证的 release candidate 提升时，才会为这些组件切出 stable 版本，并且每周的计划会同步触发这三条发布线（参见[发布渠道](#release-channels)）。应用在每次向 `main` 推送时都会发布 stable 版本。

## 工作原理

### 1. 提交规范

我们使用[Conventional Commits](https://www.conventionalcommits.org/)来组织提交信息。这使得我们的工具能够理解变更的性质、确定版本号升级，并生成相应的变更日志。

格式：`type(scope): description`

#### 提交类型及其影响

| 类型 | 描述 | 版本影响 | 示例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或新能力 | 次版本号升级 (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 缺陷修复 | 补丁版本号升级 (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 文档变更 | 不发布 | `docs: update installation guide` |
| `style` | 代码风格变更 | 不发布 | `style: format code with swiftformat` |
| `refactor` | 代码重构 | 不发布 | `refactor(server): simplify auth logic` |
| `perf` | 性能改进 | 补丁版本号升级 | `perf(cli): optimize dependency resolution` |
| `test` | 测试新增/变更 | 不发布 | `test: add unit tests for cache` |
| `chore` | 维护任务 | 不发布 | `chore: update dependencies` |
| `ci` | CI/CD 变更 | 不发布 | `ci: add workflow for releases` |

对于 CLI，这些升级决定了 canary 版本和变更日志分组。Stable CLI 版本是手动切出的次版本线 (`X.Y.0`)，而 stable 补丁版本 (`X.Y.Z`) 仅来自回溯合并，因此 `feat` 或 `fix` 会通过下方的渠道流程触达 CLI 用户，而不是立即作为 stable 版本发布。

#### 破坏性变更

破坏性变更会触发主版本号升级 (X.0.0)，并应在提交正文中注明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 变更检测

每个组件都使用[git cliff](https://git-cliff.org/)来：
- 分析自上次发布以来的提交
- 按作用域过滤提交（cli、app、server）
- 确定是否存在可发布的变更
- 自动生成变更日志

### 3. 发布流水线

当检测到可发布的变更时：

1. **版本计算**：流水线确定下一个版本号
2. **变更日志生成**：git cliff 根据提交信息创建变更日志
3. **构建流程**：构建并测试组件
4. **制品生成**：生成特定于发布的资产，例如 CLI 捆绑包、校验和，以及从`tuist --experimental-dump-help`生成的`tuist.spec.json`CLI 规范
5. **创建发布**：创建包含制品的 GitHub 发布
6. **分发**：将更新推送到包管理器（例如，用于 CLI 的 Homebrew）

对于应用，每次合并都会产生一个 stable 版本。对于 CLI、服务器和 Kura，同一自动流水线仅产生**canary**预发布版本；release candidate 和 stable 版本在每周的发布列车上切出（参见[发布渠道](#release-channels)）。

### 4. 作用域过滤

每个组件仅在存在相关变更时才发布：

- **CLI**：带有`(cli)`作用域或无作用域的提交
- **App**：带有`(app)`作用域的提交
- **Server**：带有`(server)`作用域的提交

## 发布渠道

CLI、服务器和 Kura 不会在每次向`main`推送时都提升为 stable 版本。每个组件都通过三个渠道交付，以确保推荐安装的版本保持稳定且更新缓慢，而早期采用者则保留每次提交的构建。面向用户的文档位于<.localized_link href="/cli/release-channels">CLI 发布渠道</.localized_link>和<.localized_link href="/guides/server/self-host/release-channels">Server 发布渠道</.localized_link>；本节是维护者操作手册。

每个组件都使用相同的三个渠道：

| 渠道 | 版本 | 切出方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自动执行，在每次触及组件的推送到`main`时触发（`<component>-release.yml`；对于 Kura，由`server-production-deployment.yml`在`kura/`变更时调用） |
| Release candidate | `X.Y.0-rc.N` | 每周一，或手动在`releases/<component>-<major>.<minor>.x`分支上执行（`<component>-rc.yml`） |
| Stable | `X.Y.Z` | 每周一，或通过提升经过充分验证的 RC 手动执行（`<component>-promote.yml`）；补丁通过`<component>-backport.yml` |

Canary 和 RC 构建作为 GitHub 预发布版本发布（从不标记为“Latest”，从不移动 GHCR 上的`:latest`，从不推送到 CLI 的 Homebrew），因此包管理器和镜像解析器仅在显式选择加入时才会获取它们。Canary 始终针对下一个未发布的次版本：一旦切出 RC 线，`main`的 canary 就会推进到下一个次版本。

托管 Tuist 不等待 stable 列车：服务器按提交部署，托管 canary 和生产环境运行最新的 Kura canary。部署级联在部署之前先发布该 canary 本身，因此`kura-release.yml`没有自己的触发器。仅更改 Kura 发布工具链（`mise/tasks/kura/**`、`kura-*.yml`工作流）不会切出 canary。

你永远不会手动挑选版本号。每个渠道的下一个版本都由`mise/tasks/<component>/release/channel-version.sh`从现有 git 标签派生而来，下面的工作流会调用它。

发布分支按组件进行命名空间隔离（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 为`releases/X.Y.x`），因此这三个组件的线永远不会在同一主版本上冲突。

### 每周计划

每周一 06:00 UTC，三个组件的提升作业同步运行：**CLI Promote to Stable**、**Server Promote to Stable**和**Kura Promote to Stable**。每个作业都会提升尚未成为 stable 的最新 RC 线，通常是前一周一切出的线。如果没有这样的线，该作业不会发布任何内容。

当提升完成时，无论结果如何，其匹配的**Release Candidate**工作流（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）都会通过`workflow_run`触发，并从`main`切出下一条线。

如果任一计划运行失败或被取消，消息会发布到 Slack。当发布分支在其最新 RC 之后还有提交时，提升会失败。要发布该行，请在其上切出新的 RC 并手动提升。否则，下周一将提升更新的行。

### 切出 release candidate

要在每周计划之外切出新线（将下面的组件工作流名称替换为对应组件）：

1. 使用空的`branch`输入运行 **\<Component\> Release Candidate**工作流（例如`server-rc.yml`）。
2. 它会发布`X.Y.0-rc.1`，并在成功后在构建的提交处创建受保护的`releases/<component>-X.Y.x`分支。

要将关键修复或回归引入浸泡线，请通过 PR 将其 cherry-pick 到发布分支上（与 backport 流程相同；CI 从不执行 cherry-pick），然后迭代 RC：

1. 从`releases/<component>-X.Y.x`分出分支，cherry-pick 该修复，向发布分支发起 PR，解决其中的任何冲突并合并。
2. 再次使用`branch=releases/<component>-X.Y.x`运行**Release Candidate**工作流。它会从分支 HEAD 发布`X.Y.0-rc.(N+1)`。

浸泡线处于功能冻结状态：只有关键修复和回归才会进入其中。

### 提升到 stable

要在每周计划之外提升某条线，需在其 RC 充分验证通过后：

1. 使用`branch=releases/<component>-X.Y.x`运行 **\<Component\> Promote to Stable**工作流（例如`server-promote.yml`）。
2. 它会以`make_latest=true`发布带有 semver 标签的镜像，移动 GHCR 的`:latest`标签和 GitHub 的“Latest”指针。CLI 还会更新 Homebrew formula。

除非分支 HEAD 正好是最新 RC 指向的提交，否则提升不会运行。因此，如果在最后一个 RC 之后有任何修复合并到该行，你必须切出新的 RC 并让其浸泡，然后才能作为 stable 发布。

### 将修复 backport 到 stable 线

一旦某条线成为 stable，就使用仅限 CLI 的**Backport Release**工作流（`cli-backport.yml`）发布补丁：通过 PR 将修复 cherry-pick 到`releases/X.Y.x`，然后使用该分支运行工作流以切出`X.Y.(Z+1)`。Backport 永远不会移动“Latest”指针或 Homebrew formula。同时维护两条线：当前线接受回归和安全修复，前一条线仅接受关键和安全修复。其他错误修复不会 backport，而是随下一次 minor 发布。

对于 server 和 Kura，目前的 backport 是通过针对较旧的发布分支运行提升工作流来切出的。后续工作将添加与 CLI 类似的专用 backport 工作流。

## 编写良好的提交消息

由于提交消息直接影响发布说明，因此编写清晰、描述性的消息非常重要：

### 建议：
- 使用现在时：“add feature”而非“added feature”
- 简洁但具有描述性
- 当更改特定于组件时，包含作用域
- 在适用时引用 issue：`fix(cli): resolve build cache issue (#1234)`

### 避免：
- 使用模糊的消息，如“fix bug”或“update code”
- 在一次提交中混合多个不相关的更改
- 忘记包含破坏性变更信息

### 破坏性变更

对于破坏性变更，请在提交正文中包含`BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 发布工作流

CLI、server 和 Kura 各自拥有一套渠道工作流，结构相同：

- `<component>-release.yml` - 在每次触及组件的推送到`main`时发布 canary（Kura 的是一个可重用工作流，当`kura/`发生变化时由`server-production-deployment.yml`调用）
- `<component>-rc.yml` - 每周一切出 release candidate（通过提升后的`workflow_run`触发），或手动切出或迭代一个
- `<component>-promote.yml` - 每周一 06:00 UTC 将待处理的 RC 提升为 stable，或手动提升经过充分验证的 RC
- `<component>-build-publish.yml` - 上述三个工作流调用的共享构建和发布流水线

CLI 还有`cli-backport.yml`用于在 stable 线上切出补丁。组件的所有工作流都通过一个`<component>-publish`并发组序列化，因此版本解析和标记永远不会竞争。Kura 是例外：其 canary 使用`kura-canary-publish`，其 RC 和提升使用`kura-stable-publish`，因此长时间的 RC 或提升构建不会阻碍部署级联。标签命名空间互不相交，因此这两个组不会冲突。

Helm chart 和基础设施镜像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍通过`.github/workflows/server-production-deployment.yml`发布。它在推送到`main`时运行，并为托管部署级联 canary → 验收测试 → 生产环境，并在这些基础设施组件发生变化时发布它们。app、cache、Gradle plugin、skills、Noora 以及独立的基础设施控制器各自拥有专用的`*-release.yml`工作流。它们都共享变更检测：`mise/tasks/release/components.json`声明每个组件的标签前缀和包含路径，git cliff 将匹配的提交转换为发布说明。

CLI 构建（`cli-build-publish.yml`）还会生成并发布一个`tuist.spec.json`工件（由`tuist --experimental-dump-help`生成），以便下游工具可以使用命令接口。

## 监控发布

你可以通过以下方式监控发布：
- [GitHub Releases page](https://github.com/tuist/tuist/releases)
- GitHub Actions 标签页中的工作流运行记录
- 每个组件目录中的变更日志文件

## 优势

这种持续发布方法提供：

- **快速交付**：更改在合并后立即触达用户
- **减少瓶颈**：无需等待手动发布
- **清晰沟通**：根据提交消息自动生成变更日志
- **流程一致**：所有组件采用相同的发布流程
- **质量保证**：仅发布经过测试的更改

## 故障排除

如果发布失败：

1. 检查 GitHub Actions 中失败工作流的日志
2. 确保你的提交消息遵循约定格式
3. 验证所有测试均通过
4. 确认组件能够成功构建

对于需要立即发布的紧急修复：
1. 确保你的提交具有明确的作用域
2. 合并后，监控发布工作流
3. 对于 server 或 app，修复将在下一次推送时发布；如有需要，触发手动发布
4. 对于 CLI，修复会自动进入 canary。若要将其提供给 stable 用户，请将其回溯到受维护的 stable 分支（参见[将修复回溯到 stable 分支](#backporting-fixes-to-a-stable-line)）

## App Store 发布

虽然 CLI 和 Server 遵循上述持续发布流程，但**iOS app**因 Apple 的 App Store 审核流程而例外：

- **手动发布**：iOS app 发布需要手动提交至 App Store
- **审核延迟**：每次发布都必须经过 Apple 的审核流程，可能需要 1-7 天
- **批量更改**：多个更改通常打包在一次 iOS 发布中
- **TestFlight**：Beta 版本可能在 App Store 发布之前通过 TestFlight 分发
- **发布说明**：必须根据 App Store 指南专门编写

iOS app 仍然遵循相同的提交约定并使用 git cliff 生成变更日志，但实际向用户发布的频率较低，且为手动安排。
