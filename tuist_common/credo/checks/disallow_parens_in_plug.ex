defmodule Credo.Checks.DisallowParensInPlug do
  @moduledoc """
  Ensure that local `plug` calls omit parentheses.
  """

  use Credo.Check,
    category: :warning,
    explanations: [
      check: """
      `plug` declarations should omit parentheses so they stay visually consistent
      across controllers, routers, endpoints, and tests.
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:plug, meta, _args} = ast, issues, issue_meta) do
    if Keyword.has_key?(meta, :closing) do
      {ast, issues ++ [issue_for(meta, issue_meta)]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(meta, issue_meta) do
    format_issue(
      issue_meta,
      message: "Omit parentheses in `plug` declarations to keep formatting deterministic.",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
