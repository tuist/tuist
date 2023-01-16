---
title: tuist cloud init
slug: '/cloud/commands/init'
description: 'Use tuist cloud init to get started with Tuist Cloud faster than ever.'
---

While Tuist Cloud offers a web interface, we still want to provide a great experience from the CLI. And creating a new Tuist Cloud project is a part of that. To get full context on how to get started with Tuist Cloud, you can go [here](../get-started).

As mentioned there, to create a new Tuist Cloud project, you can run `tuist cloud init --name your-cloud-project`. However, you can also specify a different organization (even a completely new one!) via: `tuist cloud init --name your-cloud-project --owner organization-or-your-username`.

### Arguments

| Argument | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--name` | The name of the cloud project you want to initialize. | | Yes |
| `--owner` | The name of the username or organization you want to initialize the project with | Your username | No |
| `--url` | A custom URL. This can be useful if you don't use the official cloud.tuist.io project | https://cloud.tuist.io  | No |