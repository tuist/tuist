defmodule Credo.Checks.DisallowSpec do
  @moduledoc """
  Ensure that `@spec` annotations are not used.
  """

  use Credo.Check,
    category: :warning,
    explanations: [
      check: """
      The codebase does not allow `@spec` annotations.
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:@, meta, [{:spec, _spec_meta, _spec}]} = ast, issues, issue_meta) do
    {ast, issues ++ [issue_for(meta, issue_meta)]}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(meta, issue_meta) do
    format_issue(
      issue_meta,
      message: "Do not use `@spec` in this codebase.",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
