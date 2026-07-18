defmodule Tuist.MCP.Components.Prompts.AskTuist do
  @moduledoc """
  Guides evidence-backed answers to questions about Tuist.
  """

  use Tuist.MCP.Prompt,
    name: "ask_tuist",
    arguments: [
      %{
        name: "question",
        description: "The question about Tuist to answer.",
        required: true
      }
    ]

  @impl EMCP.Prompt
  def description do
    "Answer a Tuist question using documentation and source-of-truth implementation evidence."
  end

  @impl EMCP.Prompt
  def template(_conn, args) do
    question = Map.get(args, "question", "the user's question about Tuist")

    %{
      messages: [
        Tuist.MCP.Prompt.message("""
        # Answer a Tuist Question

        Answer this question: #{question}

        Find the most accurate and useful answer. Use Tuist's public material for explanations and terminology. Use the implementation and focused tests as the source of truth when the answer depends on current behavior.

        ## Workflow

        1. Identify what the question is asking, then use `search_tuist` to find relevant documentation, reference material, releases, community discussions, or issues. Restrict `source` only when it helps narrow the search.
        2. Consult the source code when the question depends on current behavior, defaults, configuration, feature gates, error handling, or details that public material does not establish. The goal is to answer the question, not to produce a codebase tour.
        3. Use `search_tuist_code` with literal identifiers, configuration keys, command names, or error messages. Start with a narrow `path` or `file_glob` when the likely subsystem is known. Use regular expressions only when literal searches are insufficient.
        4. Use `list_tuist_files` when you need to discover a subsystem or nearby tests. Do not list the whole repository at high depth.
        5. Use `read_tuist_file` for the smallest relevant line ranges around matches. Follow `next_start_line` only when more of the same file is needed.
        6. Inspect implementation call sites and focused tests before concluding how behavior works. A definition alone might not show defaults, feature gates, or error handling.
        7. If a search or listing response has `truncated=true`, treat it as partial. Narrow the path, file pattern, or search terms and try again. Never describe a truncated result as exhaustive.
        8. Cite the returned public and source links. Include the source revision when it affects the conclusion.
        9. If public material and implementation differ, explain the difference explicitly. Treat the implementation and tests as the source of truth for current behavior while distinguishing that behavior from the documented contract.

        Answer the question directly before adding supporting detail. Keep the final answer focused and do not invent behavior that the available evidence does not establish.
        """)
      ]
    }
  end
end
