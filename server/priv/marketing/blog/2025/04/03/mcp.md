---
title: "Transform your LLM into an Xcode project copilot"
category: "product"
tags: ["LLMs", "MCP", "Xcode", "Copilot", "Virtual platform team", "Platform team"]
excerpt: "Master your projects with the Tuist CLI MCP server by leveraging LLMs."
author: pepicrft
highlighted: true
---

Since its inception, Tuist has placed a strong emphasis on understanding Xcode projects and workspaces, helping teams manage them by conceptually simplifying their complexities. This complexity arose from modularization, which was necessary to support the wide range of products and platforms available in today's Apple ecosystem.

To assist teams with challenges related to generated projects, we created [XcodeGraph](https://github.com/tuist/XcodeGraph), a data structure that standardizes the representation of Xcode projects and workspaces. This enabled us to extend some of our solutions—such as our graph visualization tool and selective testing—from generated projects to any Xcode project.

We knew it would be a powerful tool, but its potential exceeded our expectations. With the emergence of LLM-based technologies and, more recently, the [MCP](https://modelcontextprotocol.io/introduction) protocol standardized by Claude—which [Mattt](https://nshipster.com/authors/mattt/) [discussed](https://nshipster.com/model-context-protocol/) on his popular blog [NSHipster](https://nshipster.com/model-context-protocol/)—we couldn’t help but wonder: Could we leverage MCP to transform developers’ LLM-based chat apps and code editors, like Cursor, into Xcode project experts capable of answering questions that would otherwise be difficult or impossible? The answer is yes.

In this blog post, I’m excited to announce a new CLI feature: the Tuist MCP server, which allows you to chat with your Xcode projects and workspaces.

## What is MCP?

MCP is a protocol proposed by [Claude](https://claude.ai/) that enables LLMs to interface with the outside world. Editors like [Cursor](https://www.cursor.com/) or [Zed](https://zed.dev/), as well as chat apps like [Claude](https://claude.ai/)—acting as **clients**—can interact with MCP servers using various transport protocols, including standard input. In simpler terms, a client can spawn a process and communicate with the server through its standard input pipeline.

The server can provide [resources](https://modelcontextprotocol.io/docs/concepts/resources), [prompts](https://modelcontextprotocol.io/docs/concepts/prompts), and [tools](https://modelcontextprotocol.io/docs/concepts/tools) to respond to actions (e.g., building an app). It can even enable more agentic behaviors by allowing the server to interact with the model via [sampling](https://modelcontextprotocol.io/docs/concepts/sampling).

This might sound abstract, so let’s make it practical. LLMs lack knowledge of your specific development environment, including your projects, but they do understand Xcode projects and workspaces in general. What if you could let them "see" your projects and workspaces? That’s where resources come in. Tuist can transform your Xcode projects and workspaces into a serializable graph and share it with the LLM, allowing you to tap into its expertise to better understand your projects.

Still sounding abstract? Let’s explore a concrete example together.

## Setting up your environment

Install the latest version of Tuist and run any of the following commands to configure either Claude to connect to the Tuist MCP server:

```bash
tuist mcp setup claude
```

For any other clients that support the Model Context Protocol protocol, you can configure them using the `tuist mcp` command with standard input as the transport protocol. The Tuist MCP will list projects you’ve recently interacted with as resources. Select the one you want to use to provide context, and then try asking questions like:

- What are the direct and transitive dependencies of a specific target?
- Which target has the most source files, and how many does it include?
- What are all the static products (e.g., static libraries or frameworks) in the graph?
- Can you list all targets, sorted alphabetically, along with their names and product types (e.g., app, framework, unit test)?
- Which targets depend on a particular framework or external dependency?
- What’s the total number of source files across all targets in the project?
- Are there any circular dependencies between targets, and if so, where?
- Which targets use a specific resource (e.g., an image or plist file)?
- What’s the deepest dependency chain in the graph, and which targets are involved?
- Can you show me all the test targets and their associated app or framework targets?
- Which targets have the longest build times based on recent interactions?
- What are the differences in dependencies between two specific targets?
- Are there any unused source files or resources in the project?
- Which targets share common dependencies, and what are they?

You can watch the video in action here:

<iframe title="Transform your LLM into an Xcode project copilot" width="560" height="315" src="https://videos.tuist.dev/videos/embed/hnwUYxkbaeLn3WjZSc533s" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

## Closing thoughts

Languages as an interface to technology are not only here to stay but are poised to redefine how we interact with the digital world—and we’re only beginning to unlock their vast potential. At Tuist, we’re excited to empower you to bridge this emerging landscape with your projects and development environment. Our commitment is to keep you in full control, ensuring you decide precisely what data you share and with whom.

Exposing the graph of your most recently accessed projects is just the first step in this journey. Looking ahead, we plan to expand the scope of available information, incorporating details automatically gathered by the server from your build and test runs, as well as the resulting artifacts. As always, our mission is to handle the heavy lifting behind the scenes, freeing you to concentrate on what truly matters: crafting exceptional applications with greater speed and efficiency.

If this piques your interest, we invite you to explore [our implementation](https://github.com/tuist/tuist/pull/7366) and consider contributing new resources or tools to the server. Your input can help us enhance the features we deliver to the Tuist community. Additionally, we’ve created a dedicated repository, [awesome-swift-mcp](https://github.com/tuist/awesome-swift-mcp), with other valuable MCP-related resources in the context of development with Swift.

Stay tuned for more exciting developments from the Tuist team as we continue to push the boundaries of MCP awesomeness. We’re eager to see how you’ll harness these tools to shape the future of app development!
