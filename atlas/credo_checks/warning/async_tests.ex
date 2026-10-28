defmodule Credo.Check.Warning.AsyncTests do
  use Credo.Check,
    id: "ATLAS002",
    base_priority: :high,
    explanations: [
      check: """
      Atlas test modules run concurrently.

      A test that needs `async: false` is a test that reaches shared state
      outside the SQL sandbox, and that shared state is what makes suites go
      flaky as they grow. Reach for a `Mimic` stub on a seam function instead
      of mutating the application environment, a named process, or an ETS
      table that the rest of the suite also sees.

      The rare test that genuinely cannot be isolated, such as one needing two
      real database connections to observe row locking, may opt out with

          # credo:disable-for-next-line Credo.Check.Warning.AsyncTests

      alongside a comment explaining what forces it.
      """
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    if test_module?(source_file) do
      ctx = Context.build(source_file, params, __MODULE__)
      Credo.Code.prewalk(source_file, &walk/2, ctx).issues
    else
      []
    end
  end

  defp test_module?(%SourceFile{filename: filename}) do
    String.ends_with?(filename, "_test.exs")
  end

  defp walk({:use, meta, [_case_template, opts]} = ast, ctx) when is_list(opts) do
    if Keyword.get(opts, :async) == false do
      {ast, put_issue(ctx, issue_for(ctx, meta))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message: "Test modules must run with `async: true`.",
      trigger: "async: false",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
