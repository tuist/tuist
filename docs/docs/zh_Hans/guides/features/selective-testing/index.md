---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# 选择性测试{#selective-testing}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
<!-- -->
:::

要对生成的项目选择性运行测试，请使用`tuist test`
命令。该命令以与<LocalizedLink href="/guides/features/cache#cache-warming">预热缓存</LocalizedLink>相同的方式对Xcode项目进行<LocalizedLink href="/guides/features/projects/hashing">哈希处理</LocalizedLink>，成功后将哈希值持久化以供后续运行时检测变更。

在后续运行中，`tuist test` 会自动使用哈希值过滤测试，仅执行自上次成功测试以来发生变更的测试项。

例如，假设以下依赖关系图：

- `功能A` 包含测试`功能ATests` ，并依赖于`核心`
- `FeatureB` 包含测试`FeatureBTests` ，并依赖`核心`
- `核心库` 包含测试`CoreTests`

`tuist test` 将呈现如下效果：

| 操作            | 描述                                                   | 内部状态                                                                                     |
| ------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `tuist 测试` 调用 | 运行以下测试：`CoreTests` ` FeatureATests` ` FeatureBTests` | `的FeatureATests、` 的FeatureATests、`的FeatureBTests、` 的CoreTests以及`的CoreTests（` ）的哈希值已持久化存储 |
| `功能A` 已更新     | 开发者修改目标对象的代码                                         | 与之前相同                                                                                    |
| `tuist 测试` 调用 | 在`中运行FeatureATests测试` ，因其哈希值已变更                      | `FeatureATests的新哈希值` 已持久化存储                                                              |
| `核心` 已更新      | 开发者修改目标对象的代码                                         | 与之前相同                                                                                    |
| `tuist 测试` 调用 | 运行以下测试：`CoreTests` ` FeatureATests` ` FeatureBTests` | 新哈希值为：`FeatureATests` `FeatureBTests` 以及`CoreTests` 已持久化存储                               |

`tuist test`
直接集成二进制缓存功能，可调用本地或远程存储中的二进制文件，从而在运行测试套件时显著缩短构建时间。选择性测试与二进制缓存的结合，能大幅减少持续集成环境中的测试执行时长。

## 用户界面测试{#ui-tests}

Tuist支持选择性执行UI测试。但需提前指定目标路径。仅当您在`中添加` 参数时，Tuist才会选择性运行UI测试，例如：
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
