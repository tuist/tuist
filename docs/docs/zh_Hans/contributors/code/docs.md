---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# 文档{#docs}

来源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途说明{#what-it-is-for}

文档网站托管Tuist的产品与贡献者文档，由VitePress构建而成。

## 如何贡献{#how-to-contribute}

### 本地设置{#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 可选生成数据{#optional-generated-data}

我们在文档中嵌入了部分生成数据：

- CLI参考数据：`mise run generate-cli-docs`
- 项目清单参考数据：`mise run generate-manifests-docs`

这些是可选的。文档在没有它们的情况下也能渲染，因此仅在需要刷新生成的内容时运行它们。
