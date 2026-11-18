## 自定义元数据 {#custom-metadata}

你可以通过环境变量为构建附加元数据，以改进过滤。

### 环境变量

| 变量 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗号分隔 | 在一个变量中包含多个标签。 |
| `TUIST_BUILD_VALUE_*` | 单个值 | 键值对，其中后缀作为键。 |

### 示例

在调用构建之前，在 CI 或你的 shell 中设置这些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
