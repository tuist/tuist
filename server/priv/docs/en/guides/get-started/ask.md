---
{
  "title": "Ask",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Give coding agents access to Tuist project data so they can answer questions and support engineering decisions."
}
---
# Ask {#ask}

Coding agents understand the files available in their working directory, but many engineering decisions also depend on what happens when the project builds, tests, and ships. Tuist gives agents access to that operational context so you can ask questions about the project using evidence from real runs instead of relying only on the source code.

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) is an open standard for connecting artificial intelligence agents to external services and data. Tuist hosts a Model Context Protocol server that lets an authenticated coding agent inspect the Tuist projects you can access, search current documentation and source, and reason about build, test, cache, and bundle data.

## Connect project context {#connect-project-context}

Source code explains how a project is designed. Tuist data explains how that design behaves across developer machines and continuous integration. Giving an agent access to both helps it connect a local change with the wider behavior of the project.

Through Tuist, an agent can investigate:

- Xcode and Gradle build runs, including durations, failures, tasks, targets, and cache activity.
- Test runs, slow tests, failures, flaky behavior, and changes in reliability.
- Bundle contents and size changes.
- Tuist documentation, releases, community discussions, and the source revision deployed with the service.

Most Model Context Protocol tools are read-only and every request applies the same authorization rules as the Tuist dashboard. This lets an agent gather context and explain its reasoning before you decide whether any change should be made.

## Ask questions that lead to decisions {#ask-questions-that-lead-to-decisions}

Start with the decision you need to make, then let the agent gather the relevant evidence. For example:

- Which targets account for most of the build duration, and are their compilation tasks hitting the cache?
- Which tests are consistently slow, and which failures appear to be flaky?
- Did build or test duration regress after a particular change?
- Would caching, selective testing, or test sharding address the current bottleneck?
- Which files or dependencies contributed to a bundle size increase?

Ask the agent to cite the runs, tests, or source files behind its answer. Evidence makes assumptions visible, gives the team something concrete to verify, and helps distinguish a recurring pattern from a single unusual run.

## Connect your coding agent {#connect-your-coding-agent}

Follow the <.localized_link href="/guides/features/agentic-coding/mcp">Tuist Model Context Protocol guide</.localized_link> to connect a supported coding agent to `https://tuist.dev/mcp` and authenticate with your Tuist account. The guide includes configuration for Codex, Claude Code, Cursor, Visual Studio Code, and other clients.

After connecting, ask the agent to list the Tuist projects it can access and select the project you want to understand. Begin with a focused question about a recent build or test run so you can confirm that the agent is using the intended project and data.

## Turn the discussion into action {#turn-the-discussion-into-action}

Use the answer to choose the next path:

- Follow <.localized_link href="/guides/get-started/observability">Observe</.localized_link> when the project needs a clearer baseline or more build and test data.
- Follow <.localized_link href="/guides/get-started/optimization">Optimize</.localized_link> when the evidence points to repeated build work, unnecessary tests, or a test suite that needs to run in parallel.
- Follow <.localized_link href="/guides/get-started/tuist-runners">Run</.localized_link> when the team wants managed compute close to the same cache and insights infrastructure.

Keep the agent involved after the change by asking it to compare the same automation with the original runs. This closes the loop between understanding the project, making a decision, and verifying the outcome.
