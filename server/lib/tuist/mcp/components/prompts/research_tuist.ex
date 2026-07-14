defmodule Tuist.MCP.Components.Prompts.ResearchTuist do
  @moduledoc """
  Guides an investigation across Tuist documentation and source code.
  """

  use Tuist.MCP.Prompt,
    name: "research_tuist",
    arguments: [
      %{
        name: "question",
        description: "The Tuist behavior or implementation detail to investigate.",
        required: true
      }
    ]

  @impl EMCP.Prompt
  def description do
    "Research a Tuist behavior using documentation search and bounded source-code tools."
  end

  @impl EMCP.Prompt
  def template(_conn, args) do
    question = Map.get(args, "question", "the user's Tuist implementation question")

    %{
      messages: [
        Tuist.MCP.Prompt.message("""
        # Research Tuist

        Investigate this question: #{question}

        Use the Tuist documentation and source-code tools to produce an evidence-backed answer.

        ## Workflow

        1. Use `search_tuist` with `source=docs` to find the documented public behavior and terminology.
        2. Use `search_tuist_code` with literal identifiers, configuration keys, command names, or error messages. Start with a narrow `path` or `file_glob` when the likely subsystem is known. Use regular expressions only when literal searches are insufficient.
        3. Use `list_tuist_files` when you need to discover a subsystem or nearby tests. Do not list the whole repository at high depth.
        4. Use `read_tuist_file` for the smallest relevant line ranges around matches. Follow `next_start_line` only when more of the same file is needed.
        5. Inspect implementation call sites and focused tests before concluding how behavior works. A definition alone might not show defaults, feature gates, or error handling.
        6. If a search or listing response has `truncated=true`, treat it as partial. Narrow the path, file pattern, or search terms and try again. Never describe a truncated result as exhaustive.
        7. Cite the returned source links and documentation links. Include the source revision when it affects the conclusion.
        8. If documentation and implementation differ, explain the difference explicitly and distinguish the documented contract from current implementation behavior.

        Keep the final answer focused on the question. Do not invent behavior that the available evidence does not establish.
        """)
      ]
    }
  end
end
