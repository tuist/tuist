defmodule AtlasWeb.Utilities.Query do
  @moduledoc """
  Utilities for working with URI query parameters.

  Mirrors the small surface used by paginated/filtered LiveView pages so
  templates can compose patch URLs like
  `Query.put(@uri.query, "page", page)`.
  """

  @doc """
  Updates a query parameter with a new value.

  ## Examples

      iex> AtlasWeb.Utilities.Query.put("foo=bar", "baz", "qux")
      "baz=qux&foo=bar"

      iex> AtlasWeb.Utilities.Query.put("foo=bar&baz=old", "baz", "new")
      "baz=new&foo=bar"

      iex> AtlasWeb.Utilities.Query.put(nil, "page", 2)
      "page=2"
  """
  def put(query, key, value) when is_binary(query) or is_nil(query) do
    (query || "")
    |> URI.decode_query()
    |> Map.put(key, to_string(value))
    |> URI.encode_query()
  end

  def put(query, key, value) when is_map(query) do
    query
    |> Map.put(key, to_string(value))
    |> URI.encode_query()
  end

  @doc """
  Puts a query parameter when the value is present.

  Nil and blank string values are ignored.
  """
  def put_present(params, _key, nil) when is_map(params), do: params
  def put_present(params, _key, "") when is_map(params), do: params

  def put_present(params, key, value) when is_map(params) do
    Map.put(params, key, value)
  end

  @doc """
  Copies a legacy search/query parameter into its current key when the current
  key is absent or blank.
  """
  def copy_legacy_search(params, legacy_key, current_key) when is_map(params) do
    current_value = present_string(params[current_key])
    legacy_value = present_string(params[legacy_key])

    cond do
      not is_nil(current_value) -> params
      is_nil(legacy_value) -> params
      true -> Map.put(params, current_key, legacy_value)
    end
  end

  @doc """
  Copies legacy flat filter params into Noora's filter query shape.

  Existing Noora filter params always win. `legacy_params` lets callers preserve
  the original source of legacy values while threading an already-normalized map.
  """
  def copy_legacy_filters(params, filter_ids, legacy_params \\ nil) when is_map(params) and is_list(filter_ids) do
    legacy_params = legacy_params || params

    Enum.reduce(filter_ids, params, fn filter_id, acc ->
      copy_legacy_filter(acc, filter_id, legacy_params[filter_id])
    end)
  end

  @doc """
  Drops a query parameter.

  ## Examples

      iex> AtlasWeb.Utilities.Query.drop("foo=bar&baz=qux", "baz")
      "foo=bar"

      iex> AtlasWeb.Utilities.Query.drop("foo=bar", "missing")
      "foo=bar"
  """
  def drop(query, key) when is_binary(query) or is_nil(query) do
    (query || "")
    |> URI.decode_query()
    |> Map.delete(key)
    |> URI.encode_query()
  end

  def drop(query, key) when is_map(query) do
    query
    |> Map.delete(key)
    |> URI.encode_query()
  end

  @doc """
  Extracts decoded query parameters from a URI string.

  ## Examples

      iex> AtlasWeb.Utilities.Query.query_params("/admin/sessions?page=2")
      %{"page" => "2"}

      iex> AtlasWeb.Utilities.Query.query_params("/admin/sessions")
      %{}

      iex> AtlasWeb.Utilities.Query.query_params(nil)
      %{}
  """
  def query_params(uri) when is_binary(uri) do
    case URI.parse(uri).query do
      nil -> %{}
      query -> URI.decode_query(query)
    end
  end

  def query_params(nil), do: %{}

  @doc """
  Parses a positive page number, defaulting invalid values to 1.
  """
  def parse_page(nil), do: 1
  def parse_page(page) when is_integer(page) and page >= 1, do: page

  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number >= 1 -> number
      _other -> 1
    end
  end

  def parse_page(_page), do: 1

  @doc """
  Normalizes blank strings to nil and trims present strings.
  """
  def present_string(nil), do: nil

  def present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def present_string(_value), do: nil

  defp copy_legacy_filter(params, _filter_id, nil), do: params
  defp copy_legacy_filter(params, _filter_id, ""), do: params

  defp copy_legacy_filter(params, filter_id, value) do
    value = present_string(value)

    cond do
      is_nil(value) ->
        params

      Map.has_key?(params, "filter_#{filter_id}_op") or Map.has_key?(params, "filter_#{filter_id}_val") ->
        params

      true ->
        params
        |> Map.put("filter_#{filter_id}_op", "==")
        |> Map.put("filter_#{filter_id}_val", value)
    end
  end
end
