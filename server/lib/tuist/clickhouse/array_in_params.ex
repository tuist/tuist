defmodule Tuist.ClickHouse.ArrayInParams do
  @moduledoc """
  Binds the list of `expr in ^list` as a single `Array(T)` parameter.

  `ecto_ch` binds each element of a pinned `in` list as its own parameter, and
  ClickHouse receives every parameter as a separate HTTP form field. ClickHouse
  rejects requests with more than `http_max_fields` form fields, which defaults
  to 1,000 since ClickHouse 26.3. Ecto preloads over many parents filter with
  the same `in ^values` expression.

  Every ClickHouse repository `use`s this module after `use Ecto.Repo`. Ecto
  calls `prepare_query/3` on the repository that serves a query, which for
  `Tuist.ClickHouseRepo` is its dynamic repository: `Tuist.ShadowClickHouseRepo`
  once reads move to the in-cluster server, and `Tuist.IngestRepo` in tests.

  Only lists of integers and binaries are rewritten. `ecto_ch` derives an
  array parameter's type from its first element, which is exact for those but
  not for values such as datetimes of mixed precision.

  A single array parameter is still subject to `http_max_field_value_size`
  (128 KiB), which caps a list at roughly 3,000 UUIDs or 10,000 integers.
  Queries over lists that can grow past that must chunk them.
  """

  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.QueryExpr
  alias Ecto.SubQuery

  defmacro __using__(_opts) do
    quote do
      @impl Ecto.Repo
      def prepare_query(_operation, query, opts), do: {Tuist.ClickHouse.ArrayInParams.rewrite(query), opts}
    end
  end

  def rewrite(%Ecto.Query{} = query) do
    %{
      query
      | from: rewrite_from(query.from),
        joins: Enum.map(query.joins, &rewrite_join/1),
        wheres: Enum.map(query.wheres, &rewrite_expr/1),
        havings: Enum.map(query.havings, &rewrite_expr/1),
        combinations: Enum.map(query.combinations, fn {kind, combined} -> {kind, rewrite(combined)} end),
        with_ctes: rewrite_ctes(query.with_ctes)
    }
  end

  defp rewrite_from(%{source: %SubQuery{} = subquery} = from), do: %{from | source: rewrite_subquery(subquery)}
  defp rewrite_from(from), do: from

  defp rewrite_join(%JoinExpr{} = join) do
    source =
      case join.source do
        %SubQuery{} = subquery -> rewrite_subquery(subquery)
        source -> source
      end

    %{join | source: source, on: rewrite_expr(join.on)}
  end

  defp rewrite_ctes(nil), do: nil

  defp rewrite_ctes(%{queries: queries} = with_ctes) do
    queries =
      Enum.map(queries, fn
        {name, opts, %Ecto.Query{} = cte} -> {name, opts, rewrite(cte)}
        {name, %Ecto.Query{} = cte} -> {name, rewrite(cte)}
        other -> other
      end)

    %{with_ctes | queries: queries}
  end

  defp rewrite_subquery(%SubQuery{query: query} = subquery), do: %{subquery | query: rewrite(query)}

  defp rewrite_expr(%BooleanExpr{} = boolean_expr) do
    %{
      boolean_expr
      | expr: rewrite_in(boolean_expr.expr, boolean_expr.params),
        params: array_params(boolean_expr.params),
        subqueries: Enum.map(boolean_expr.subqueries, &rewrite_subquery/1)
    }
  end

  defp rewrite_expr(%QueryExpr{params: params} = query_expr) when is_list(params) do
    %{query_expr | expr: rewrite_in(query_expr.expr, params), params: array_params(params)}
  end

  defp rewrite_expr(expr), do: expr

  defp rewrite_in(expr, params) do
    Macro.prewalk(expr, fn
      {:in, meta, [left, {:^, _, [ix]} = param]} = in_expr ->
        if params |> Enum.at(ix) |> array_param?() do
          {:fragment, meta, [raw: "", expr: left, raw: " IN (", expr: param, raw: ")"]}
        else
          in_expr
        end

      other ->
        other
    end)
  end

  defp array_params(params) do
    Enum.map(params, fn
      {list, {:in, type}} = param -> if array_param?(param), do: {list, {:array, type}}, else: param
      param -> param
    end)
  end

  defp array_param?({[_ | _] = list, {:in, _type}}), do: Enum.all?(list, &(is_integer(&1) or is_binary(&1)))
  defp array_param?(_param), do: false
end
