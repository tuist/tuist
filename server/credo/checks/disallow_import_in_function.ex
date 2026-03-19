defmodule Credo.Checks.DisallowImportInFunction do
  @moduledoc """
  Ensure that `import` statements are not placed inside function bodies.

  Imports should be declared at the module level, not inside `def` or `defp` blocks.
  """

  use Credo.Check,
    category: :warning,
    explanations: [
      check: """
      `import` statements should be at the module level, not inside function bodies.
      Move the import to the top of the module alongside other aliases and imports.
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.ast()
    |> find_imports_in_functions()
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp find_imports_in_functions({:ok, ast}), do: find_imports_in_functions(ast)

  defp find_imports_in_functions(ast) do
    {_ast, issues} = Macro.prewalk(ast, [], &do_traverse/2)
    issues
  end

  # def/defp with guards: def name(args) when guard do ... end
  defp do_traverse({op, _meta, [_name, _args, body]} = _ast, issues)
       when op in [:def, :defp] do
    inner_imports = collect_imports(body)
    {nil, issues ++ inner_imports}
  end

  # def/defp without guards: def name do ... end / def name(args) do ... end
  defp do_traverse({op, _meta, [_name, body]} = _ast, issues)
       when op in [:def, :defp] do
    inner_imports = collect_imports(body)
    {nil, issues ++ inner_imports}
  end

  defp do_traverse(ast, issues), do: {ast, issues}

  defp collect_imports(ast) do
    {_ast, imports} =
      Macro.prewalk(ast, [], fn
        # Skip imports inside quote blocks — these inject code into other modules
        {:quote, _meta, _args}, acc ->
          {nil, acc}

        {:import, meta, _args} = node, acc ->
          {node, [meta | acc]}

        node, acc ->
          {node, acc}
      end)

    imports
  end

  defp issue_for(meta, issue_meta) do
    format_issue(
      issue_meta,
      message: "Move `import` to the module level instead of inside a function body.",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
