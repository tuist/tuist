---
{
  "title": "Elixir 测试分片",
  "titleTemplate": ":title · 测试分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 测试分片将 Elixir 项目的测试分发到多个 CI 运行器上。"
}
---
# Elixir 测试分片 {#elixir-test-sharding}

Tuist Hex 包内置支持对 Elixir 项目的测试进行分片。它利用 Tuist 服务器根据历史耗时数据创建均衡的分片计划，并仅编译一次项目，使每个运行器可以直接执行测试。

> [!IMPORTANT] REQUIREMENTS
> - 在配置 CI 分片任务之前，请先完成<.localized_link href="/guides/get-started/elixir-project">共享的 Elixir 设置</.localized_link>

## 工作原理 {#how-it-works}

测试分片遵循两阶段工作流：

1. **构建阶段：** Tuist 为测试编译你的项目，枚举测试文件，并在服务器上创建**分片计划**。服务器使用过去 30 天的历史测试耗时数据将测试分配到各个分片，使每个分片的耗时大致相同。构建阶段会上传构建产物，并输出一个**分片矩阵**，供你的 CI 系统用来生成并行运行器。
2. **测试阶段：** 每个 CI 运行器接收一个**分片索引**，下载构建产物，并仅执行分配给该分片的测试。

测试按文件分发：同一文件中的所有测试都在同一个分片上运行。对于 Tuist 尚未见过的测试，系统会使用估算值，因此项目的首批分片计划的均衡性不如后续计划。

## 构建阶段 {#build-phase}

使用 `tuist.test.build` 任务准备测试分片：

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

在调用分片任务之前，先通过共享设置安装的别名进行编译。在冷检出环境下，Mix 可能在发现 `tuist.test.build` 时编译依赖项，而此时 Tuist 的依赖缓存尚未有机会恢复它们。显式编译在与分片任务相同的测试环境中运行。

此任务：
1. 在测试环境中编译项目
2. 使用历史耗时数据在 Tuist 服务器上创建分片计划
3. 上传构建产物，避免各分片重复编译
4. 为你的 CI 系统输出分片矩阵

### 构建选项 {#build-options}

| 选项 | 描述 |
|--------|-------------|
| `--shard-max <N>` | 最大分片数（默认值：2） |
| `--shard-min <N>` | 最小分片数 |
| `--shard-total <N>` | 精确的分片数量，而非范围 |
| `--shard-max-duration <MS>` | 每个分片的目标最大持续时间（毫秒） |
| `--shard-reference <REF>` | 分片查找计划所使用的名称 |
| `--no-upload` | 规划分片但不上传构建产物；此时每个分片将自行编译 |

所有其他参数都会转发给 `mix compile`。

分片引用会自动从 CI 环境变量（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）中派生，或者可以通过 `TUIST_SHARD_REFERENCE` 环境变量显式设置。在这些提供商之外，你必须将其设置为构建阶段和同一管道运行的各分片共享的值。在 GitHub Actions 上，引用还包含运行尝试：当仅重新运行失败的任务时，请传递原始构建任务的引用，而不是在分片任务中派生新的引用。

## 测试阶段 {#test-phase}

当设置 `TUIST_SHARD_INDEX` 时，包会从服务器获取分片分配，下载构建产物，并仅运行分配的测试文件而无需编译。在冷运行器上，请在调用任务之前引导 SDK 并加载其路径：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

在 Mix 的工作进程中编译 SDK 不会将其加载到父进程中。显式的 `deps.loadpaths` 步骤可防止在下载构建产物之前因任务发现而编译剩余依赖项。这种单命令形式保留了项目的测试准备别名。如果其设置命令触发编译，请使用下面的单独设置序列。

你传入的任何测试文件或目录都会进一步缩小分片范围：只有既在分片中又在你的选择范围内的文件才会运行。如果某个分片最终没有测试，它会成功退出。

所有分片的结果会在仪表板上作为单次测试运行呈现，其**分片**部分显示每个分片的耗时。

如果必须在测试之前运行设置，请先下载构建产物而不启动应用程序：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

在禁用编译的情况下，在单独的进程中运行你的设置。例如，Ecto 项目可以使用以下命令创建并迁移其数据库：

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

在此阶段保留任何其他项目特定的准备工作。你的编译别名在执行引导工作之前也必须遵守 `--no-compile`：Mix 仅将标志转发给列表别名的最后一个任务，因此较早的无条件 `deps.compile` 仍会运行。请参阅 <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">手动编译集成</.localized_link> 中的受保护别名。

然后在执行分片之前加载已恢复的 SDK 而不进行编译。这还可以防止当路径依赖的源比下载的构建产物更新时，因任务发现而编译该路径依赖：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

两个命令都需要相同的分片引用。`--prepare-only` 需要已上传的构建产物，如果缺少已准备的应用程序构件，`--no-download` 会失败。`--no-download` 会显式跳过项目的测试准备别名（包括重试时），并在跳过设置步骤时打印通知。常规运行会保留其别名，即使你转发了 `--no-compile --no-deps-check`。将数据库迁移放在单独的进程中还可以避免当迁移回归测试自行加载这些模块时出现模块重定义警告。

在测试不同环境时，传递稳定的 `--scheme` 标签，例如 `--scheme clickhouse-current` 或 `--scheme clickhouse-floor`。带有不同标签的结果不会被视作同一配置的不稳定重跑。

### 分片所需条件 {#what-the-shards-need}

上传的构建产物是 `_build/test` 目录。每个分片运行器仍然需要：
- 与构建阶段相同的检出代码
- 相同的 Elixir 和 Erlang/OTP 版本
- 依赖源代码，来自 `mix deps.get`

尚不支持从 umbrella 项目的根目录进行分片。请在其中一个应用程序内运行这两个阶段。

## 持续集成 {#continuous-integration}

### GitHub Actions {#github-actions}

在 GitHub Actions 上，构建阶段会将分片索引写入其步骤的 `matrix` 输出。使用矩阵策略并行运行分片：

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - id: build
        run: mix tuist.test.build --shard-max 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
      # Ecto example: keep all project-specific test preparation here.
      # The project's compile alias must honor --no-compile (see above).
      - run: mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
      - run: mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

### 其他提供商 {#other-providers}

在 GitHub Actions 之外，构建阶段会将计划写入 `.tuist-shard-matrix.json`：

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

使用 `shard_count` 设置你的并行作业，并为每个作业分配其 `TUIST_SHARD_INDEX`，范围从 `0` 到 `shard_count - 1`。对于 Tuist 无法从中派生引用的提供商，还需为每个作业提供相同的 `TUIST_SHARD_REFERENCE`。
