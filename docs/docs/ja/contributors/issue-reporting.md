---
title: Issue報告
titleTemplate: :title · コントリビューター · Tuist
description: バグを報告してTuist に貢献する方法を学ぶ
---

# Issue の報告 {#issue-reporting}

Tuist のユーザーとして、バグや予期しない動作に遭遇することがあるかもしれません。
その場合は、ぜひ報告してください。私たちが修正に取り組みます。
その場合は、ぜひ報告してください。私たちが修正に取り組みます。

## GitHub Issues は当プロジェクトのチケット管理プラットフォームです {#github-issues-is-our-ticketing-platform}

問題は GitHub の [Issue](https://github.com/tuist/tuist/issues) として報告し、Slack など他のプラットフォームでは報告しないでください。 GitHub は、問題の追跡や管理に適しており、コードベースに近い場所で問題の進捗を追うことができます。 加えて、問題の詳細な説明が推奨されるため、報告者は問題について考え、より多くの背景情報を提供することが求められます。

## 背景情報が鍵 {#context-is-crucial}

背景情報が不十分な課題は不完全と見なされ、作成者は追加の情報を要求されます。 もし背景情報が提供されない場合、 Issue はクローズされます。 逆に言えば、背景情報を多く提供するほど、私たちが問題を理解し、解決するのが容易になります。 そのため、Issue を解決してほしい場合は、できるだけ詳しい情報を提供してください。 次の質問に答える形で情報を記載してください。

- 試したことは何か？
- プロジェクトの依存関係の状態はどうなっているのか？
- 使用している Tuist のバージョンは？
- この問題が作業の妨げになっているか

また、最小限の**再現可能なプロジェクト**の提供もお願いしています。

## 再現可能なプロジェクト {#reproducible-project}

### 再現可能なプロジェクトとは？ 再現可能なプロジェクトとは?

A reproducible project is a small Tuist project to demonstrate a problem - often this problem is caused by a bug in Tuist. Your reproducible project should contain the bare minimum features needed to clearly demonstrate the bug.

### Why should you create a reproducible test case? {#why-should-you-create-a-reproducible-test-case}

A reproducible projects lets us isolate the cause of a problem, which is the first step towards fixing it! The most important part of any bug report is to describe the exact steps needed to reproduce the bug.

A reproducible project is a great way to share a specific environment that causes a bug. Your reproducible project is the best way to help people that want to help you.

### Steps to create a reproducible project {#steps-to-create-a-reproducible-project}

- Create a new git repository.
- Initialize a project using `tuist init` in the repository directory.
- Add the code needed to recreate the error you’ve seen.
- Publish the code (your GitHub account is a good place to do this) and then link to it when creating an issue.

### Benefits of reproducible projects {#benefits-of-reproducible-projects}

- **Smaller surface area:** By removing everything but the error, you don’t have to dig to find the bug.
- **No need to publish secret code:** You might not be able to publish your main site (for many reasons). Remaking a small part of it as a reproducible test case allows you to publicly demonstrate a problem without exposing any secret code.
- **Proof of the bug:** Sometimes a bug is caused by some combination of settings on your machine. A reproducible test case allows contributors to pull down your build and test it on their machines as well. This helps verify and narrow down the cause of a problem.
- **Get help with fixing your bug:** If someone else can reproduce your problem, they often have a good chance of fixing the problem. It’s almost impossible to fix a bug without first being able to reproduce it.
