---
{
  "title": "缓存卷",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "在 GitHub Actions、Buildkite 和 GitLab CI 的 Tuist Linux 或 macOS Runner 任务之间，保留 Xcode、模块和 Gradle 缓存以及任何其他目录。"
}
---
# 缓存卷 {#cache-volumes}

Tuist runner 可在任务之间保留缓存，因此新的 runner 启动时已有预热内容。每个任务都会获得最新保存内容的私有可写副本。

- **托管缓存**通过各自的一步操作来维护 Xcode 编译缓存、Tuist 模块缓存以及 Gradle 缓存。Tuist 知道每种缓存的存放位置，并将其保存在自己的存储中。
- **自定义卷**可保留你指定键名下的任意其他目录，例如包管理器的下载缓存。

在检出代码之后、使用缓存的命令之前添加这些步骤。在非 Tuist runner 上，这些步骤不执行任何操作；缓存问题不会导致任务失败：该步骤会记录一条警告，任务将继续运行并使用空缓存。

## 托管缓存 {#managed-caches}

这些步骤仅决定缓存的存放位置。保留你现有的缓存配置：`tuist setup cache`或启用编译缓存的构建设置（参见<.localized_link href="/guides/features/cache/xcode-cache">Xcode 缓存指南</.localized_link>）、模块缓存的身份验证，以及用于 Gradle 远程构建缓存的<.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 插件</.localized_link>。在 GitLab CI 中，使用`!reference`组合代码片段，因为`extends`会替换`before_script`。

### Xcode 缓存 {#xcode-cache}

在 macOS runner 上保留 Xcode 编译缓存的存储。

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### 模块缓存 {#module-cache}

在 macOS runner 上保留 Tuist 的本地缓存：<.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link>二进制文件、已编译的清单、插件和选择性测试结果。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradle 缓存 {#gradle-cache}

在 Linux 和 macOS runner 上保留 Gradle 用户主目录中的`caches`和`wrapper`目录：依赖项、转换后的 jar 包、已编译的构建脚本以及 Gradle 发行版。如果你使用了自定义路径，请在此步骤之前设置`GRADLE_USER_HOME`，并关闭对这些目录的其他缓存，例如在`actions/setup-java`上使用`cache: gradle`。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## 自定义卷 {#custom-volumes}

选择一个稳定的`key`和一个`path`，然后在安装依赖之前挂载该卷。路径必须为空或不存在。移除任何会写入同一目录的归档缓存或构件恢复步骤。若要在一个卷中保留多个目录，请参阅[一个卷中的多个目录](#several-directories-in-one-volume)。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### 一个卷中的多个目录 {#several-directories-in-one-volume}

一个卷可以容纳多个目录。在 GitHub Actions 中，每行列出一个路径；在 Buildkite 中，将`path`设置为列表；在 GitLab CI 中，为每个目录传递一次`--path`。空行和周围的空白会被忽略。

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **共享容量。** 所有路径共享该卷的容量，并一起恢复和保存。
- **将小型且相关的目录归为一组。** 为体积较大或变化频繁的目录分配独立的卷。
- **禁止嵌套。** 同一卷中的路径不得相互包含。
- **更改列表会导致冷启动。** 每个路径都存储在卷内的独立目录中，由其书写方式标识。在单一路径与多个路径之间切换，或添加、删除、重写某个路径，都会改变该布局：变更后的首个任务会对受影响的路径以冷状态启动。不再列出的路径内容会保留在卷中，直到你清除该卷。

### 键的工作方式 {#how-keys-work}

键用于命名随时间变化的卷；它不是像`actions/cache`键那样的固定快照名称。

- **每个键对应一个卷。** 每个键的作用域限定于仓库（在 Buildkite 上为流水线；在 GitLab CI 上为项目）、平台、CPU 架构和用户。每个挂载该卷的任务都从最新保存的内容开始，符合条件的任务会将更改保存回同一卷。
- **保持键稳定。** 不要在键中包含版本号或锁文件哈希。使用`actions/cache`时，类似`deps-${{ hashFiles('Package.resolved') }}`的键会为每次变更创建新条目，而`restore-keys`会回退到较旧的条目。在这里，新键意味着一个新的空卷：每次变更后的首个任务都会冷启动，旧卷会保留直至过期。保留键并让你的工具更新内容；包管理器会复用仍然有效的部分。
- **不支持部分匹配。** 没有恢复键。尚未保存过的键会以空状态开始。
- **以`tuist-`开头的键被保留**供 Tuist 自身的缓存使用，并在挂载卷之前被拒绝。
- **有意重新开始。** 当你希望任务以空状态开始时，更改键或在仪表盘中清除卷。
- **将`tuist-`键留给 Tuist。** 托管缓存使用以`tuist-`开头的键，因此请为你的自定义卷选择不同的名称。

在 Linux 上，路径以普通目录形式挂载，因此工具可以使用其常规位置，例如`deps`、`_build`和`node_modules`。保留你常规的`.gitignore`规则。在 macOS 上，路径是符号链接：使用下载缓存，例如`~/.npm`；不支持`node_modules`以及会替换其缓存目录的工具。在`.gitignore`中忽略不带尾部斜杠的工作区链接。

## 保存更改 {#saving-changes}

托管缓存和自定义卷会保存来自你自己的仓库、在任何分支上成功运行的任务的更改：

| 提供商 | 保存更改的任务 |
| --- | --- |
| GitHub Actions | 来自仓库本身的推送、定时、手动触发和拉取请求任务 |
| Buildkite | 流水线仓库的 Webhook 和定时构建，包括其拉取请求 |
| GitLab CI | 项目的推送、定时和 Web 流水线，以及当连接拥有<.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 访问令牌</.localized_link>时其自身合并请求的流水线 |

其他任务可以使用缓存，但其更改会被丢弃。这些包括分叉拉取请求、`pull_request_target`任务、从 API 或仪表盘启动的 Buildkite 构建、来自分叉或缺少 API 访问令牌的 GitLab 合并请求，以及标签。未更改卷的任务会保留已保存的版本。你可以在运行器配置文件中限制哪些分支进行保存；请参阅[选择哪些分支进行保存](#choose-which-branches-save)。

并发任务独立工作；不同任务的更改不会合并。切勿缓存凭据或不可替换的数据。

### 选择哪些分支进行保存 {#choose-which-branches-save}

你可以更改哪些分支保存托管缓存和自定义卷。打开**运行器 → 配置文件**，编辑你的任务使用的配置文件，并展开**保存缓存来源**。任务使用其请求的配置文件：在 GitHub Actions 中为`runs-on:`，在 Buildkite 中为队列，或在 GitLab CI 中为`tags:`。这些设置适用于该配置文件上任务使用的每个卷，包括后来创建的卷。

![运行器配置文件表单，其中“保存缓存来源”部分已展开，“默认分支”已启用，并添加了 develop 和 release/* 作为额外分支](/images/guides/features/runners/save-cache-from.png)

默认情况下，仓库中每个成功的任务都会保存其更改。若仅从某些分支保存，请启用**限制到特定分支**：

- **默认分支**允许每个仓库默认分支上的任务进行保存。关闭它以仅从额外分支保存。
- 在**额外分支**下，添加最多 20 个也进行保存的分支名称。使用`*`作为通配符：`release/*`匹配`release/1.0`。

[保存更改](#saving-changes)中列出的任务在其分支匹配时会保存更改。在 GitHub Actions 推送和手动触发运行中，名称匹配的标签也会匹配。

其他分支上的任务仍可以使用缓存，但其更改会被丢弃。从不保存的任务（例如分叉拉取请求）即使在匹配的分支上也不会保存。缩小这些设置或删除配置文件会丢弃它们不再允许的待处理更改；删除的配置文件会回退到从每个分支保存。

## 容量和保留 {#capacity-and-retention}

Xcode 缓存起始大小为**30 GB**。模块缓存、Gradle 缓存和每个自定义卷起始大小为**20 GB**。设置大小可为缓存或卷赋予其他容量，范围为`1gb`到`100gb`的整数 GB：

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Gradle 缓存和自定义卷接受相同的`size`输入（GitLab CI 中的`TUIST_GRADLE_CACHE_SIZE`和`TUIST_VOLUME_SIZE`，`tuist-cache-volume`的`--size`）。较大的大小会从下一个任务开始扩大卷并保留其内容。较小的大小会在下次清除卷或卷过期后生效。当任务请求同一缓存的不同大小时，应用最大值，因此请在一处声明每个大小。

所有缓存在**7 天无任务挂载**后过期，过期后的下一个任务将以空卷开始。Tuist 会修剪 Xcode 和模块缓存以适应其容量，Gradle 缓存步骤会让 Gradle 在每次构建后移除七天未使用的条目。

自定义卷不会修剪旧依赖项：使用工具的清理设置以保持其小巧。写入已满的卷可能导致任务失败。当保存的内容达到卷容量的**80%** 且任务空间不足时，下一个任务将以空卷开始，其更改将开始新的保存状态。

## 检查和清除卷 {#inspecting-and-clearing-volumes}

打开**运行器 → 卷**以检查已用空间、缓存命中率和任务历史。账户管理员可以选择**清除卷**以使未来任务以空状态开始。正在运行的任务保留其私有副本，但无法将其保存回去。Xcode 和模块缓存也显示在此处，但无法清除。
