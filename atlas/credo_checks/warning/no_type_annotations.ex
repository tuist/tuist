defmodule Credo.Check.Warning.NoTypeAnnotations do
  use Credo.Check,
    id: "ATLAS001",
    base_priority: :high,
    explanations: [
      check: """
      Atlas does not use Elixir type or spec annotations.

      Avoid `@spec`, `@type`, `@typep`, `@opaque`, `@callback`, and
      `@macrocallback` annotations. Keep function contracts expressed through
      clear naming, validations, tests, and narrow data structures.
      """
    ]

  @annotations [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  defp walk({:@, meta, [{annotation, _annotation_meta, _args}]} = ast, ctx) when annotation in @annotations do
    {ast, put_issue(ctx, issue_for(ctx, meta, annotation))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, annotation) do
    trigger = "@#{annotation}"

    format_issue(
      ctx,
      message: "Elixir type and spec annotations are not allowed.",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
