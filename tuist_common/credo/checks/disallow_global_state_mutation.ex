defmodule Credo.Checks.DisallowGlobalStateMutation do
  @moduledoc """
  Detect mutations of global state in test files.

  Calls to `Application.put_env/3`, `Application.delete_env/2`, and `Process.put/2`
  mutate shared global state and can cause flaky tests. Use Mimic stubs on a config
  module instead.
  """

  use Credo.Check,
    category: :warning,
    explanations: [
      check: """
      Do not use `Application.put_env/3`, `Application.delete_env/2`, or `Process.put/2`
      in tests. These functions mutate shared global state and can cause flaky tests.
      Use Mimic stubs on a config module instead.
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Application]}, :put_env]}, meta, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ [issue_for("Application.put_env/3", meta, issue_meta)]}
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Application]}, :delete_env]}, meta, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ [issue_for("Application.delete_env/2", meta, issue_meta)]}
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Process]}, :put]}, meta, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ [issue_for("Process.put/2", meta, issue_meta)]}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(function_name, meta, issue_meta) do
    format_issue(
      issue_meta,
      message:
        "Do not use `#{function_name}` in tests — it mutates shared global state and can cause flaky tests. Use Mimic stubs on a config module instead.",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
