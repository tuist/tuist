---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 集成 {#github}

Git 仓库是绝大多数软件项目的核心。我们与 GitHub 集成，可直接在您的拉取请求中提供 Tuist 见解，并为您节省一些配置，如同步默认分支。

## 设置 {#setup}

安装 [Tuist GitHub 应用程序](https://github.com/marketplace/tuist)。安装后，您需要告诉 Tuist
您的版本库的 URL，例如

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
