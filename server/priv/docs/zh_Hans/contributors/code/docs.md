---
{
  "title": "文档",
  "titleTemplate": ":title · 代码 · 贡献者 · Tuist",
  "description": "为 Tuist 文档站点做出贡献。"
}
---
# 文档 {#docs}

来源：[github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## 用途 {#what-it-is-for}

文档站点托管 Tuist 的产品和贡献者文档。它是 Tuist 服务器（一个 Phoenix 应用）的一部分，负责渲染 `server/priv/docs/en` 下的 Markdown 页面，并在 `/docs` 提供访问。

## 如何贡献 {#how-to-contribute}

编辑 `server/priv/docs/en` 下的英文页面。翻译由单独的流程管理，因此不要编辑其他语言目录。侧边栏在 `server/lib/tuist/docs_sidebar.ex` 中定义；请在那里添加新页面，以便读者能够找到它们。

当多个页面共享相同的文本时（例如不同构建系统中的相同章节），将其放入一个文件名以 `_` 开头且与这些页面相邻的文件中，并通过指向该文件的 `@snippet:` HTML 注释进行引用，就像不稳定测试页面所做的那样。以 `_` 开头的文件不会作为独立页面发布。

### 本地设置 {#set-up-locally}

从 `server` 目录运行服务器，按照其[设置说明](https://github.com/tuist/tuist/blob/main/server/AGENTS.md)操作：

```bash
cd server
mise install
mise run dev
```

然后打开 [http://localhost:8080/en/docs](http://localhost:8080/en/docs)。

### 生成的内容 {#generated-content}

CLI 参考文档是根据最新 CLI 版本的命令规范生成的，因此无需在本地构建。

ProjectDescription API 参考文档作为 DocC 站点单独托管在 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。要在本地构建它，请从仓库根目录运行 `mise run docs:project-description`。
