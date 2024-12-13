defmodule Credo.Checks.TimestampsType do
  @moduledoc """
  Ensure that Ecto schemas use `utc_datetime` for timestamps.
  """
  use Boundary
  use Credo.Check,
    param_defaults: [allowed_type: :utc_datetime],
    category: :warning,
    explanations: [
      check: """
      The timestamps type in Ecto schema definitions should always be `utc_datetime` in schemas and `timestamptz` in migrations. This should be a default in Ecto, but it's not for backward compatibility reasons.

      See more at:
      - https://elixirforum.com/t/why-use-utc-datetime-over-naive-datetime-for-ecto/32532/4
      - https://www.amberbit.com/blog/2017/8/3/time-zones-in-postgresql-elixir-and-phoenix/
      """,
      params: [allowed_type: "The allowed type for timestamps"]
    ]

  def run(source_file, params \\ []) do
    allowed_type = Params.get(params, :allowed_type, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, allowed_type, issue_meta))
  end

  defp traverse(
         {:timestamps, meta, [opts]} = ast,
         issues,
         allowed_type,
         issue_meta
       ) do
    if Enum.any?(
         opts,
         fn
           {:type, ^allowed_type} ->
             true

           _ ->
             false
         end
       ) do
      {ast, issues}
    else
      {ast, issues ++ [issue_for(allowed_type, meta[:line], issue_meta)]}
    end
  end

  defp traverse(
         {:timestamps, meta, []} = ast,
         issues,
         allowed_type,
         issue_meta
       ) do
    {ast, issues ++ [issue_for(allowed_type, meta[:line], issue_meta)]}
  end

  defp traverse(ast, issues, _allowed_type, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(allowed_type, line_no, issue_meta) do
    format_issue(
      issue_meta,
      message: "Ecto's `timestamps/1` method should specify the `type: #{allowed_type}`.",
      line_no: line_no
    )
  end
end
