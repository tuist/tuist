---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# 生成的项目 {#generated-projects}

警告要求
<!-- -->
- 一个<LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>
<!-- -->
:::

要在生成的项目中有选择地运行测试，请使用`tuist test`
命令。该命令<LocalizedLink href="/guides/features/projects/hashing">散列</LocalizedLink>你的
Xcode
项目，就像<LocalizedLink href="/guides/features/cache#cache-warming">预热缓存</LocalizedLink>一样，一旦成功，它就会持续散列，以确定未来运行中的变化。

在以后的运行中，`tuist test` 会透明地使用哈希值来过滤测试，只运行自上次成功运行测试以来发生变化的测试。

例如，假设依赖关系图如下：

- `FeatureA` 有测试`FeatureATests` ，并依赖于`核心`
- `FeatureB` 有测试`FeatureBTests` ，并依赖于`核心`
- `核心` 有测试`CoreTests`

`tuist 测试` 也将如此：

| 行动                      | 描述                                                  | 内部状态                                                      |
| ----------------------- | --------------------------------------------------- | --------------------------------------------------------- |
| `tuist test` invocation | 运行`CoreTests`,`FeatureATests` 和`FeatureBTests 中的测试` | `FeatureATests` 、`FeatureBTests` 和`CoreTests` 的哈希值被持久化。   |
| `功能A` 已更新               | 开发人员修改目标代码                                          | 和以前一样                                                     |
| `tuist test` invocation | 运行`FeatureATests` 中的测试，因为它的哈希值已更改                   | `FeatureATests` 的新散列值被持久化                                 |
| `核心` 已更新                | 开发人员修改目标代码                                          | 和以前一样                                                     |
| `tuist test` invocation | 运行`CoreTests`,`FeatureATests` 和`FeatureBTests 中的测试` | `FeatureATests` `FeatureBTests` ，以及`CoreTests` 的新散列值被持久化。 |

`tuist test`
与二进制缓存直接集成，可从本地或远程存储中使用尽可能多的二进制文件，从而在运行测试套件时缩短构建时间。选择性测试与二进制缓存相结合，可大大缩短在 CI
上运行测试所需的时间。

## 用户界面测试{#ui-tests}

Tuist 支持用户界面测试的选择性测试。不过，Tuist 需要提前知道目的地。只有指定`目的地` 参数，Tuist 才会有选择地运行用户界面测试，如
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
