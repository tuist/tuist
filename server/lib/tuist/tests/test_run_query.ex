defmodule Tuist.Tests.TestRunQuery do
  @moduledoc false

  @query_filter_regex ~r/(^|\s+)(-?)([a-z_]+)(:|~)"((?:\\"|[^"])*)"/
  @query_filter_fields %{
    "git_branch" => :git_branch,
    "scheme" => :scheme,
    "status" => :status
  }

  def filters(nil), do: {:ok, []}
  def filters(""), do: {:ok, []}

  def filters(query) do
    captures = Regex.scan(@query_filter_regex, query)

    consumed_query =
      captures
      |> Enum.map_join(&Enum.at(&1, 0))
      |> String.trim()

    if consumed_query == String.trim(query) do
      filters =
        Enum.map(captures, fn [_match, _separator, negation, field, operator, value] ->
          %{
            field: Map.fetch!(@query_filter_fields, field),
            op: query_operator(operator, negation),
            value: unescape_query_value(value)
          }
        end)

      {:ok, filters}
    else
      {:error, :invalid_query}
    end
  rescue
    KeyError -> {:error, :invalid_query}
  end

  defp query_operator(":", ""), do: :==
  defp query_operator(":", "-"), do: :!=
  defp query_operator("~", ""), do: :ilike
  defp query_operator("~", "-"), do: :not_ilike

  defp unescape_query_value(value), do: String.replace(value, ~S(\"), ~S("))
end
