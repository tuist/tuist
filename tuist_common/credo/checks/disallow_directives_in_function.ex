defmodule Credo.Checks.DisallowDirectivesInFunction do
  @moduledoc """
  Ensure that `import`, `alias`, and `require` statements are not placed inside function bodies.

  These directives should be declared at the module level, not inside `def` or `defp` blocks.
  """

  use Credo.Check,
    category: :warning,
    explanations: [
      check: """
      `import`, `alias`, and `require` statements should be at the module level, not inside
      function bodies. Move them to the top of the module alongside other directives.
      """
    ]

  @directives [:import, :alias, :require]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.ast()
    |> find_directives_in_functions()
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp find_directives_in_functions({:ok, ast}), do: find_directives_in_functions(ast)

  defp find_directives_in_functions(ast) do
    {_ast, issues} = Macro.prewalk(ast, [], &do_traverse/2)
    issues
  end

  # def/defp with guards: def name(args) when guard do ... end
  defp do_traverse({op, _meta, [_name, _args, body]} = _ast, issues)
       when op in [:def, :defp] do
    {nil, issues ++ collect_directives(body)}
  end

  # def/defp without guards: def name do ... end / def name(args) do ... end
  defp do_traverse({op, _meta, [_name, body]} = _ast, issues)
       when op in [:def, :defp] do
    {nil, issues ++ collect_directives(body)}
  end

  defp do_traverse(ast, issues), do: {ast, issues}

  defp collect_directives(ast) do
    {_ast, directives} =
      Macro.prewalk(ast, [], fn
        # Skip directives inside quote blocks — these inject code into other modules
        {:quote, _meta, _args}, acc ->
          {nil, acc}

        {directive, meta, _args} = node, acc when directive in @directives ->
          {node, [{directive, meta} | acc]}

        node, acc ->
          {node, acc}
      end)

    directives
  end

  defp issue_for({directive, meta}, issue_meta) do
    format_issue(
      issue_meta,
      message: "Move `#{directive}` to the module level instead of inside a function body.",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
