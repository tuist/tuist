---
title: Championing projects
slug: /contributors/championing-projects
description: This documents describes a framework for proposing and executing projects.
---

This page proposes a light-weight framework to propose, execute, and roll-out projects in Tuist. Projects move through 2 phases: **Explore** and **Build**.

### Explore

This phase starts with an idea. It's usually a user need or problem to be tackled. The goal of this phase is three-fold:

1. Identify **what** we are trying to solve.
2. Justify **why** it's worth to solve it.
3. **Align the core team** with a proposed solution.

The outcome of this phase must be a discussions on the RFCs category of the [community forum](https://github.com/tuist/tuist/discussions/categories/rfcs). The proposal should follow the [default template](https://github.com/tuist/tuist/discussions/2189). The Tuist core team, maintainers, and contributors will dump any concerns or thoughts about the proposed solution. The goal of the discussion is to seek alignment and introduce any necessary modifications to achieve that.

#### Roles

As part of the explore phase, you should identify who will be the **steward**, and if there are **contributors** that want to join the project. The list below describes what the responsibilities of each role are:

- **Champion:** It's the person proposing the project, and they'll be responsible for ensuring that the project moves forward.
- **Contributor:** Contributors are Tuist users or contributors interested in the proposed solution and would like to participate in its execution.
- **Steward:** A person from the core team that ensures that the project's execution aligns with Tuist’s design principles and best practices. It’s also the point person to answer any question that might arise.

### Build

The goal of this phase is to implement the proposed solution. You must create a **GitHub Milestone** with the project's name and a reference to the topic on Discourse. Moreover, you must break down the project into **small tasks represented by GitHub issues** and assign them to the milestone. If there are contributors to the project other than the champion, we recommend creating a public channel in Slack with the following naming convention `#project-xxx`.

A project is **done** when the code is implemented, well structured and written, tested, and follows Tuist's conventions and best practices. Moreover, the documentation must be updated accordingly.
