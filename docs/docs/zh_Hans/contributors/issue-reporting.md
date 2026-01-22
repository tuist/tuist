---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# 问题报告{#issue-reporting}

作为 Tuist 的用户，您可能会遇到错误或意外行为。若发现此类问题，我们鼓励您提交报告以便我们及时修复。

## GitHub issues 是我们的工单平台{#github-issues-is-our-ticketing-platform}

问题应通过[GitHub
issues](https://github.com/tuist/tuist/issues)提交，而非Slack或其他平台。GitHub更利于问题追踪与管理，更贴近代码库，并能让我们实时掌握问题进展。此外，该平台鼓励用户详细描述问题，促使提交者深入思考并提供更多背景信息。

## 上下文至关重要{#context-is-crucial}

若问题描述缺乏足够上下文，将被视为不完整并要求作者补充说明。若未补充，该问题将被关闭。请理解：您提供的上下文越详尽，我们越能准确理解并解决问题。因此若希望问题得到解决，请尽可能提供完整背景信息。请尝试回答以下问题：

- 你原本想做什么？
- 你的图表看起来如何？
- 您正在使用哪个版本的Tuist？
- 这是否阻碍了您？

我们还要求您提供可复现的最小**项目：** 。

## 可重现项目{#reproducible-project}

### 什么是可重现项目？{#what-is-a-reproducible-project}

可复现项目是用于演示问题的Tuist小型项目——这类问题通常由Tuist中的漏洞引发。您的可复现项目应仅包含清晰演示该漏洞所需的最低限度功能。

### 为何需要创建可复现的测试案例？{#why-should-you-create-a-reproducible-test-case}

可复现的项目能帮助我们定位问题根源，这是解决问题的第一步！任何错误报告中最关键的部分，就是详细描述复现该错误的具体步骤。

可重现项目是分享导致错误的特定环境的绝佳方式。您的可重现项目是帮助那些想协助您的人的最佳途径。

### 创建可复现项目的步骤{#steps-to-create-a-reproducible-project}

- 创建一个新的Git仓库。
- 在项目仓库目录中使用`初始化项目：tuist init`
- 添加重现所见错误所需的代码。
- 发布代码（您的 GitHub 账户是理想发布平台），并在创建问题时提供代码链接。

### 可复现项目的优势{#benefits-of-reproducible-projects}

- **更小的表面积：** 通过仅保留错误信息，无需费力挖掘即可定位缺陷。
- **无需公开机密代码：**
  （注：此处保留原文链接格式）您可能因各种原因无法公开主网站。将其中一小部分重构为可复现的测试案例，即可在不泄露任何机密代码的前提下公开演示问题。
- **错误复现链接：** 某些错误可能由本地设备设置组合引发。可复现的测试案例能让贡献者下载您的构建版本并在其设备上测试，这有助于验证并缩小问题根源范围。
- **获取错误修复帮助：** 若他人能复现您的问题，他们通常有较高概率解决该问题。若无法复现错误，几乎不可能修复该问题。
