defmodule Credo.Checks.DisallowJason do
  @moduledoc """
  Ensure that the `Jason` library is not used directly.

  Prefer Elixir's built-in `JSON` module for encoding and decoding JSON.
  """

  use Credo.Check,
    category: :warning,
    explanations: [
      check: """
      Direct calls to the `Jason` module are not allowed. Use Elixir's built-in
      `JSON` module instead.

      Examples:

          # Disallowed
          Jason.encode!(value)
          Jason.decode!(binary)

          # Preferred
          JSON.encode!(value)
          JSON.decode!(binary)
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({{:., meta, [{:__aliases__, _alias_meta, [:Jason | _]}, _fun]}, _call_meta, _args} = ast, issues, issue_meta) do
    {ast, issues ++ [issue_for(meta, issue_meta)]}
  end

  defp traverse({:%, meta, [{:__aliases__, _alias_meta, [:Jason | _]}, _]} = ast, issues, issue_meta) do
    {ast, issues ++ [issue_for(meta, issue_meta)]}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(meta, issue_meta) do
    format_issue(
      issue_meta,
      message: "Use Elixir's built-in `JSON` module instead of `Jason`.",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
