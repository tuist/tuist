---
{
  "title": "Debugging",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Use coding agents and local runs to debug issues in Tuist."
}
---
# 调试 {#debugging}

开放性具有实际优势：代码开源可见，可本地运行，还能借助编码助手更快解答问题，并调试代码库中的潜在漏洞。

若在调试过程中发现文档缺失或不完整，请更新英文文档（路径：`docs/` ），并提交PR。

## 使用编码代理{#use-coding-agents}

编码代理适用于：

- 扫描代码库以定位行为的实现位置。
- 本地复现问题并快速迭代。
- 追踪输入数据在Tuist中的流转路径以定位根本原因。

请提供最简化的复现案例，并指明具体组件（CLI、服务器、缓存、文档或手册）。范围越聚焦，调试过程越快速准确。

### 常用提示语 (FNP){#frequently-needed-prompts}

#### 意外的项目生成{#unexpected-project-generation}

项目生成结果与预期不符。请在我的项目目录下运行 Tuist CLI：`/path/to/project`
以查明原因。请追踪生成器管道并定位导致该输出的代码路径。

#### 生成项目中的可复现错误{#reproducible-bug-in-generated-projects}

这似乎是生成项目中的一个错误。请在`examples/` 下创建可复现的项目，参考现有示例。添加一个失败的验收测试，通过`xcodebuild`
运行（仅选中该测试），修复问题后重新运行测试确认通过，最后提交 PR。
