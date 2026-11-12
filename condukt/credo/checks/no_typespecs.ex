defmodule Condukt.Credo.Check.Readability.NoTypespecs do
  use Credo.Check,
    id: "EXC002",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Production Elixir code in this repo should avoid typespec
      annotations such as `@spec`, `@type`, `@typep`, and `@opaque`.

      Prefer clear names, guards, and runtime validation over typespec
      maintenance.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @forbidden_attributes [:spec, :type, :typep, :opaque]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if lib_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      {_ast, issues} = source_file |> Credo.Code.ast() |> Macro.prewalk([], &walk(&1, &2, issue_meta))
      Enum.reverse(issues)
    else
      []
    end
  end

  defp walk({:@, meta, [{attribute, _, _arguments}]} = ast, issues, issue_meta)
       when attribute in @forbidden_attributes do
    issue = issue_for(issue_meta, attribute, meta)
    {ast, [issue | issues]}
  end

  defp walk(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp lib_file?(filename) do
    String.starts_with?(filename, "lib/") or String.contains?(filename, "/lib/")
  end

  defp issue_for(issue_meta, attribute, meta) do
    format_issue(
      issue_meta,
      message: "Avoid #{inspect("@" <> Atom.to_string(attribute))} in lib files.",
      trigger: "@#{attribute}",
      line_no: Keyword.get(meta, :line)
    )
  end
end
