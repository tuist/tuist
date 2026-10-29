---
{
  "title": "文档",
  "titleTemplate": ":title · 代码 · 贡献者 · Tuist",
  "description": "为 Tuist 文档站点做出贡献。"
}
---
# 文档 {#docs}

来源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途 {#what-it-is-for}

该文档站点托管 Tuist 的产品和贡献者文档。它基于 VitePress 构建。

## 如何贡献 {#how-to-contribute}

### 本地设置 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 可选的生成数据 {#optional-generated-data}

我们在文档中嵌入了一些生成的数据：

- CLI 参考数据：`mise run generate-cli-docs`

这些是可选的。文档可以在没有它们的情况下渲染，因此仅在需要刷新生成内容时才运行它们。

ProjectDescription API 参考作为 DocC 站点单独托管在 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。要在本地构建它，请从仓库根目录运行 `mise run docs:project-description`。
