---
{
  "title": "发布",
  "titleTemplate": ":title | 贡献者 | Tuist",
  "description": "了解 Tuist 的持续发布流程如何运作"
}
---
# 发布

当变更合并到主分支时，Tuist 会自动发布新版本。CLI、服务器和 Kura 缓存服务器均通过发布渠道（canary、release candidate、stable）进行分发，以确保推荐安装的版本保持稳定且更新节奏平缓；生成 release candidate 并将其提升为 stable 是每周有计划地执行的步骤。应用持续发布（iOS 应用仅持续部署到 TestFlight，详见[此处](#app-store-release)）。

## 概览

我们发布以下主要组件：
- **Tuist CLI** - 命令行工具，通过 canary、release candidate 和 stable [渠道](#release-channels)分发
- **Tuist Server** - 后端服务，采用与 CLI 相同的渠道模型进行分发
- **Kura** - 缓存服务器，采用与 CLI 相同的渠道模型进行分发
- **Tuist App** - macOS 和 iOS 应用，持续发布（iOS 应用仅持续部署到 TestFlight，详见[此处](#app-store-release)）

每次向 `main` 推送都会为 CLI、服务器和 Kura 发布 canary 预发布版本。每个组件的 stable 版本仅在维护者将经过充分验证的 release candidate 提升时才会生成，并且每周的发布计划会同步触发这三条发布线（参见[发布渠道](#release-channels)）。应用在每次向 `main` 推送时都会发布 stable 版本。

## 工作原理

### 1. 提交规范

我们使用[Conventional Commits](https://www.conventionalcommits.org/)来组织提交消息。这使得我们的工具能够理解变更的性质、确定版本号升级，并生成相应的变更日志。

格式：`type(scope): description`

#### 提交类型及其影响

| 类型 | 描述 | 版本影响 | 示例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次版本号升级 (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 错误修复 | 补丁版本号升级 (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 文档变更 | 不发布 | `docs: update installation guide` |
| `style` | 代码风格变更 | 不发布 | `style: format code with swiftformat` |
| `refactor` | 代码重构 | 不发布 | `refactor(server): simplify auth logic` |
| `perf` | 性能改进 | 补丁版本号升级 | `perf(cli): optimize dependency resolution` |
| `test` | 测试添加/变更 | 不发布 | `test: add unit tests for cache` |
| `chore` | 维护任务 | 不发布 | `chore: update dependencies` |
| `ci` | CI/CD 变更 | 不发布 | `ci: add workflow for releases` |

对于 CLI，这些升级决定了 canary 版本号和变更日志分组。Stable CLI 版本是手动生成的次版本线 (`X.Y.0`)，而稳定补丁版本 (`X.Y.Z`) 仅来自向后移植，因此 `feat` 或 `fix` 会通过下方的渠道流程触达 CLI 用户，而不是作为即时的 stable 发布。

#### 破坏性变更

破坏性变更会触发主版本号升级 (X.0.0)，并应在提交正文中注明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 变更检测

每个组件都使用 [git cliff](https://git-cliff.org/) 来：
- 分析自上次发布以来的提交
- 按范围过滤提交（cli、app、server）
- 确定是否存在可发布的变更
- 自动生成变更日志

### 3. 发布流水线

当检测到可发布的变更时：

1. **版本计算**：流水线确定下一个版本号
2. **变更日志生成**：git cliff 根据提交消息创建变更日志
3. **构建过程**：构建并测试组件
4. **制品生成**：生成特定于发布的资产，例如 CLI 捆绑包、校验和，以及由 `tuist --experimental-dump-help` 生成的 `tuist.spec.json` CLI 规范
5. **创建发布**：创建包含制品的 GitHub 发布
6. **分发**：将更新推送到包管理器（例如，用于 CLI 的 Homebrew）

对于应用，每次合并都会生成一个 stable 发布。对于 CLI、服务器和 Kura，同一自动流水线仅生成 **canary** 预发布版本；release candidate 和 stable 发布是在每周的发布列车上生成的（参见[发布渠道](#release-channels)）。

### 4. 范围过滤

每个组件仅在存在相关变更时才发布：

- **CLI**：带有 `(cli)` 范围或无范围的提交
- **App**：带有 `(app)` 范围的提交
- **Server**：带有 `(server)` 范围的提交

## 发布渠道

CLI、服务器和 Kura 不会在每次向 `main` 推送时都提升为 stable 发布。每个组件都通过三个渠道分发，以确保推荐的安装版本保持稳定且更新缓慢，而早期采用者则保留每次提交的构建。面向用户的文档位于 <.localized_link href="/cli/release/channels">CLI 发布渠道</.localized_link> 和 <.localized_link href="/guides/server/self-host/release/channels">Server 发布渠道</.localized_link>；本节是维护者操作手册。

每个组件都使用相同的三个渠道：

| 渠道 | 版本 | 生成方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自动，在每次影响组件的推送到 `main` 时（`<component>-release.yml`；对于 Kura，当 `kura/` 变更时由 `server-production-deployment.yml` 调用） |
| Release candidate | `X.Y.0-rc.N` | 每周一，或手动，在 `releases/<component>-<major>.<minor>.x` 分支上（`<component>-rc.yml`） |
| Stable | `X.Y.Z` | 每周一，或手动，通过提升经过充分验证的 RC（`<component>-promote.yml`）；补丁通过 `<component>-backport.yml` |

Canary 和 RC 构建作为 GitHub 预发布版本发布（从不标记为“Latest”，从不移动 GHCR 上的 `:latest`，从不推送到用于 CLI 的 Homebrew），因此包管理器和镜像解析器仅在明确选择加入时才会获取它们。Canary 始终针对下一个未发布的次版本：一旦切出 RC 线，`main` 的 canary 就会推进到下一个次版本。

托管版 Tuist 不等待 stable 列车：服务器按提交部署，托管版 canary 和生产环境运行最新的 Kura canary。部署级联在部署之前先发布该 canary，因此 `kura-release.yml` 没有自己的触发器。仅对 Kura 发布工具链的变更（`mise/tasks/kura/**`、`kura-*.yml` 工作流）不会切出 canary。

你无需手动选择版本号。每个渠道的下一个版本都由 `mise/tasks/<component>/release/channel-version.sh` 从现有的 git 标签派生而来，下面的工作流会调用它。

发布分支按组件进行命名空间隔离（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 为 `releases/X.Y.x`），因此这三个组件的发布线永远不会在同一主版本下冲突。

### 每周计划

每周一 06:00 UTC，三个组件的提升任务同步运行：**CLI Promote to Stable**、**Server Promote to Stable** 和 **Kura Promote to Stable**。每个任务都会提升尚未成为 stable 的最新 RC 线，通常是前一周一切出的那条线。如果没有这样的线，则该任务不发布任何内容。

当提升完成时，无论结果如何，其匹配的 **Release Candidate** 工作流（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）都会通过 `workflow_run` 触发，并从 `main` 切出下一条线。

如果任何计划运行的任务失败或被取消，消息会发布到 Slack。如果发布分支在其最新 RC 之后还有提交，则提升会失败。要发布该行，请在其上切出一个新的 RC 并手动提升。否则，下个周一将提升更新的行。

### 切出 release candidate

若要在每周计划之外切出新线（请将下方替换为对应组件的工作流名称）：

1. 运行 **\<Component\> Release Candidate** 工作流（例如 `server-rc.yml`），并将 `branch` 输入留空。
2. 它会发布 `X.Y.0-rc.1`，并在成功后在构建的提交处创建受保护的 `releases/<component>-X.Y.x` 分支。

若要将关键修复或回归问题引入正在验证的发布线，请通过 PR 将其 cherry-pick 到发布分支上（流程与 backport 相同；CI 从不执行 cherry-pick），然后迭代 RC：

1. 从 `releases/<component>-X.Y.x` 创建分支，cherry-pick 该修复，向发布分支发起 PR，解决其中的任何冲突并合并。
2. 再次运行 **Release Candidate** 工作流，并设置 `branch=releases/<component>-X.Y.x`。它将从分支 HEAD 发布 `X.Y.0-rc.(N+1)`。

验证中的发布线处于功能冻结状态：仅允许纳入关键修复和回归修复。

### 提升为 stable

若要在每周计划之外提升某条发布线，需在其 RC 充分验证通过后：

1. 运行 **\<Component\> Promote to Stable** 工作流（例如 `server-promote.yml`），并设置 `branch=releases/<component>-X.Y.x`。
2. 它会使用 `make_latest=true` 发布带有语义化版本标签的镜像，同时移动 GHCR 上的 `:latest` 标签和 GitHub 的“Latest”指针。CLI 还会更新 Homebrew formula。

除非分支 HEAD 恰好是最新 RC 指向的提交，否则提升操作将拒绝运行。因此，如果在最后一个 RC 之后有任何修复合并到该线，你必须先切出一个新的 RC 并让其充分验证，然后才能作为 stable 发布。

### 将修复 backport 到 stable 线

一旦某条线进入 stable，即可通过仅限 CLI 的 **Backport Release** 工作流（`cli-backport.yml`）发布补丁：通过 PR 将修复 cherry-pick 到 `releases/X.Y.x`，然后使用该分支运行工作流以切出 `X.Y.(Z+1)`。Backport 从不移动“Latest”指针或更新 Homebrew formula。同时维护两条线：当前线接受回归修复和安全修复，前一条线仅接受关键修复和安全修复。其他错误修复不会 backport，而是随下一次次版本发布。

对于 Server 和 Kura，请使用 **Server Backport Release**（`server-backport.yml`）或 **Kura Backport Release**（`kura-backport.yml`）。提升操作仅发布 RC 的 `X.Y.0`；它无法对已稳定的线打补丁。

1. 从所选 `X.Y` 线上最新发布的 stable 组件标签开始，并向其现有的 `releases/server-X.Y.x` 或 `releases/kura-X.Y.x` 分支发起精准的修复 PR。更新的次版本或主版本发布不会阻碍对受维护线的补丁发布。请勿包含与 main 无关的变更。
2. 审查并合并源 PR。拉取远程发布分支，并对其 **最终合并尖端** 进行资格确认，包括组件支持的平台以及 TLS 的正负向控制。通过预合并检查的头部并不等同于对其他 squash 或合并提交的资格确认。
3. 在获得单独的发布批准后，**从 main** 调度匹配的 backport 工作流，将 `source_sha` 设置为该经过资格确认的确切合并尖端，并将 `base_tag` 设置为当前的 stable 标签，例如 `server@X.Y.Z` 或 `kura@X.Y.Z`。工作流会推导出 `X.Y.(Z+1)`；操作人员无需选择次版本升级或提升 canary 内容。

规划阶段会刷新确切的远程分支和基础标签，要求所选源等于分支尖端，拒绝未变更的源或组件之外的变更、其信任策略输入及验证，并锁定已解析的基础提交。源自 main 的控制会在版本化镜像和 GitHub 发布之前立即重复这些检查。如果源分支、stable 基础或可用版本发生变化，请停止并重新进行资格确认，而不是替换为新源。

Backport 使用现有的多平台发布器，且不移动 GitHub 的“Latest”指针或 GHCR `:latest`。发布与托管部署相互独立：这些工作流不会提升托管服务器或 Kura 集群，不会绕过 canary 验收，也不会对已安装的运行时进行资格确认。构建辅助工具和 Dockerfile 仍来自所选的 stable 源。这些控制是发布门禁，而非无需凭据的构建任务；构建可以在最终门禁之前上传未打标签的镜像摘要。镜像发布和 GitHub 发布并非原子操作：如果在镜像标签发布后后续门禁失败，请检查部分发布内容并保留其原始源和产物。切勿替换现有发布或在其标签下使用不同的字节内容。

## 编写优质的提交消息

由于提交消息直接影响发布说明，因此编写清晰、描述性的消息非常重要：

### 建议：
- 使用现在时：“add feature”而非“added feature”
- 简洁但具有描述性
- 当变更针对特定组件时，包含作用域
- 在适用时引用 issue：`fix(cli): resolve build cache issue (#1234)`

### 避免：
- 使用模糊的消息，如“fix bug”或“update code”
- 在一次提交中混合多个不相关的变更
- 忘记包含破坏性变更信息

### 破坏性变更

对于破坏性变更，请在提交正文中包含 `BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 发布工作流

CLI、Server 和 Kura 各自拥有一套渠道工作流，结构相同：

- `<component>-release.yml` - 在每次触及组件的推送至 `main` 时发布 canary（Kura 的是可复用工作流，由 `server-production-deployment.yml` 在 `kura/` 变更时调用）
- `<component>-rc.yml` - 每周一切出 release candidate（通过提升后的 `workflow_run` 触发），或手动切出或迭代
- `<component>-promote.yml` - 每周一 06:00 UTC 将待处理的 RC 提升为 stable，或手动提升经过充分验证的 RC
- `<component>-build-publish.yml` - 上述三个工作流调用的共享构建和发布流水线

CLI、Server 和 Kura 还拥有 `<component>-backport.yml`，用于在 stable 线上切出补丁。组件的所有工作流都通过一个 `<component>-publish` 并发组串行执行，因此版本解析和打标永远不会发生竞争。Kura 是例外：其 canary 使用 `kura-canary-publish`，而其 RC、提升和 backport 使用 `kura-stable-publish`，因此长时间的 stable 构建不会阻塞部署级联。标签命名空间互不相交，因此这两个组不会冲突。

Helm Chart 和基础设施镜像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍通过 `.github/workflows/server-production-deployment.yml` 发布。它在推送到 `main` 时运行，并为托管部署执行 canary → 验收测试 → production 的级联流程，同时在基础设施组件变更时发布它们。App、cache、Gradle plugin、skills、Noora 以及独立的基础设施控制器各自拥有专用的 `*-release.yml` 工作流。它们共享变更检测机制：`mise/tasks/release/components.json` 声明每个组件的标签前缀和包含路径，git cliff 将匹配的提交转换为发布说明。

CLI 构建（`cli-build-publish.yml`）还会生成并发布 `tuist.spec.json` 工件（由 `tuist --experimental-dump-help` 生成），以便下游工具可以使用命令接口。

## 监控发布

你可以通过以下方式监控发布：
- [GitHub Releases 页面](https://github.com/tuist/tuist/releases)
- GitHub Actions 标签页中的工作流运行记录
- 每个组件目录中的 Changelog 文件

## 优势

这种持续发布方法提供：

- **快速交付**：变更在合并后立即触达用户
- **减少瓶颈**：无需等待手动发布
- **清晰沟通**：根据提交消息自动生成 Changelog
- **流程一致**：所有组件使用相同的发布流程
- **质量保证**：仅发布经过测试的变更

## 故障排除

如果发布失败：

1. 检查失败工作流的 GitHub Actions 日志
2. 确保你的提交消息遵循约定格式
3. 验证所有测试是否通过
4. 检查组件是否成功构建

对于需要立即发布的紧急修复：
1. 确保你的提交具有明确的作用域
2. 合并后，监控发布工作流
3. 对于 Server 或 App，修复将在下次推送时交付；如有需要，触发手动发布
4. 对于 CLI，修复会自动进入 canary。若要将其交付给 stable 用户，请将其 backport 到维护中的 stable 分支（参见[将修复 backport 到 stable 分支](#backporting-fixes-to-a-stable-line)）

## App Store 发布

虽然 CLI 和 Server 遵循上述持续发布流程，但**iOS App**由于 Apple 的 App Store 审核流程而例外：

- **手动发布**：iOS App 发布需要手动提交至 App Store
- **审核延迟**：每次发布都必须经过 Apple 的审核流程，可能需要 1-7 天
- **批量变更**：多次变更通常打包在一次 iOS 发布中
- **TestFlight**：Beta 版本可能在 App Store 发布之前通过 TestFlight 分发
- **发布说明**：必须根据 App Store 指南专门编写

iOS App 仍然遵循相同的提交约定并使用 git cliff 生成 Changelog，但实际向用户发布发生在频率较低的手动计划中。
