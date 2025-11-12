defmodule TuistWeb.Utilities.Query do
  @moduledoc """
  Utilities for working with URI query parameters.

  This module provides functions to update and drop query parameters
  while handling encoding/decoding transparently.
  """

  @doc """
  Updates a query parameter with a new value.

  ## Parameters

    * `query` - Either an encoded query string or a decoded map
    * `key` - The parameter key to put
    * `value` - The new value for the parameter

  ## Examples

      iex> TuistWeb.Utilities.Query.put("foo=bar", "baz", "qux")
      "foo=bar&baz=qux"

      iex> TuistWeb.Utilities.Query.put("foo=bar&baz=old", "baz", "new")
      "foo=bar&baz=new"

      iex> TuistWeb.Utilities.Query.put(%{"foo" => "bar"}, "baz", "qux")
      "foo=bar&baz=qux"
  """
  @spec put(String.t() | map() | nil, String.t(), String.t()) :: String.t()
  def put(query, key, value) when is_binary(query) or is_nil(query) do
    (query || "")
    |> URI.decode_query()
    |> Map.put(key, value)
    |> URI.encode_query()
  end

  def put(query, key, value) when is_map(query) do
    query
    |> Map.put(key, value)
    |> URI.encode_query()
  end

  @doc """
  Drops a query parameter.

  ## Parameters

    * `query` - Either an encoded query string or a decoded map
    * `key` - The parameter key to drop

  ## Examples

      iex> TuistWeb.Utilities.Query.drop("foo=bar&baz=qux", "baz")
      "foo=bar"

      iex> TuistWeb.Utilities.Query.drop("foo=bar", "nonexistent")
      "foo=bar"

      iex> TuistWeb.Utilities.Query.drop(%{"foo" => "bar", "baz" => "qux"}, "baz")
      "foo=bar"
  """
  @spec drop(String.t() | map() | nil, String.t()) :: String.t()
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
  Checks if query parameters contain pagination parameters.

  Supports both cursor-based pagination (before/after) and limit/offset-based pagination.

  ## Parameters

    * `query` - Either an encoded query string or a decoded map

  ## Examples

      iex> TuistWeb.Utilities.Query.has_pagination_params?("foo=bar")
      false

      iex> TuistWeb.Utilities.Query.has_pagination_params?("foo=bar&after=cursor123")
      true

      iex> TuistWeb.Utilities.Query.has_pagination_params?("foo=bar&limit=10")
      true

      iex> TuistWeb.Utilities.Query.has_pagination_params?(%{"foo" => "bar", "offset" => "20"})
      true
  """
  @spec has_pagination_params?(String.t() | map() | nil) :: boolean()
  def has_pagination_params?(query) when is_binary(query) do
    decoded_query = URI.decode_query(query)
    has_cursor_pagination?(decoded_query) or has_limit_offset_pagination?(decoded_query)
  end

  def has_pagination_params?(query) when is_map(query) do
    has_cursor_pagination?(query) or has_limit_offset_pagination?(query)
  end

  def has_pagination_params?(nil), do: false

  defp has_cursor_pagination?(query) do
    Map.has_key?(query, "before") or Map.has_key?(query, "after")
  end

  defp has_limit_offset_pagination?(query) do
    Map.has_key?(query, "limit") or Map.has_key?(query, "offset")
  end

  @doc """
  Clears cursor pagination parameters (before/after) from query parameters.

  This is useful when sort order changes or filters are updated, as cursors
  become invalid when the underlying sort fields change.

  ## Parameters

    * `params` - A map of query parameters

  ## Examples

      iex> TuistWeb.Utilities.Query.clear_cursors(%{"foo" => "bar", "after" => "cursor123"})
      %{"foo" => "bar"}

      iex> TuistWeb.Utilities.Query.clear_cursors(%{"before" => "cursor", "after" => "cursor"})
      %{}
  """
  @spec clear_cursors(map()) :: map()
  def clear_cursors(params) when is_map(params) do
    params
    |> Map.delete("after")
    |> Map.delete("before")
  end

  @doc """
  Checks if query parameters contain cursor pagination parameters (before/after).

  ## Parameters

    * `params` - A map of query parameters

  ## Examples

      iex> TuistWeb.Utilities.Query.has_cursor?(%{"foo" => "bar"})
      false

      iex> TuistWeb.Utilities.Query.has_cursor?(%{"after" => "cursor123"})
      true

      iex> TuistWeb.Utilities.Query.has_cursor?(%{"before" => "cursor123"})
      true
  """
  @spec has_cursor?(map()) :: boolean()
  def has_cursor?(params) when is_map(params) do
    Map.has_key?(params, "after") or Map.has_key?(params, "before")
  end

  @doc """
  Checks if query parameters contain explicit sort parameters for a given prefix.

  Sort parameters can use either hyphens or underscores as separators, depending on the prefix format:
  - Hyphen format: `{prefix}-sort-by` and `{prefix}-sort-order`
  - Underscore format: `{prefix}_sort_by` and `{prefix}_sort_order`

  ## Parameters

    * `params` - A map of query parameters
    * `prefix` - An atom prefix that includes the separator (e.g., `:"build-runs"`, `:generate_runs`)

  ## Examples

      iex> TuistWeb.Utilities.Query.has_explicit_sort_params?(%{"build-runs-sort-by" => "duration"}, :"build-runs")
      true

      iex> TuistWeb.Utilities.Query.has_explicit_sort_params?(%{"generate_runs_sort_by" => "ran_at"}, :generate_runs)
      true

      iex> TuistWeb.Utilities.Query.has_explicit_sort_params?(%{"foo" => "bar"}, :"build-runs")
      false
  """
  @spec has_explicit_sort_params?(map(), atom()) :: boolean()
  def has_explicit_sort_params?(params, prefix) when is_map(params) and is_atom(prefix) do
    prefix_str = Atom.to_string(prefix)

    # Determine separator: if prefix contains underscore, use underscore format; otherwise use hyphen format
    {sort_by_key, sort_order_key} =
      if String.contains?(prefix_str, "_") do
        {"#{prefix_str}_sort_by", "#{prefix_str}_sort_order"}
      else
        {"#{prefix_str}-sort-by", "#{prefix_str}-sort-order"}
      end

    Map.has_key?(params, sort_by_key) or Map.has_key?(params, sort_order_key)
  end

  @doc """
  Checks if sort parameters have changed between requests.

  Compares the current sort parameters in the socket assigns with new values
  from the request params. Sort parameters follow the pattern `{prefix}_sort_by`
  and `{prefix}_sort_order`.

  ## Parameters

    * `socket` - The LiveView socket with assigns
    * `new_sort_by` - The new sort_by value from params
    * `new_sort_order` - The new sort_order value from params
    * `prefix` - An atom prefix for the sort parameters (e.g., `:build_runs`, `:bundles`)

  ## Examples

      iex> socket = %{assigns: %{build_runs_sort_by: "duration", build_runs_sort_order: "desc"}}
      iex> TuistWeb.Utilities.Query.sort_changed?(socket, "duration", "asc", :build_runs)
      true

      iex> socket = %{assigns: %{build_runs_sort_by: "duration", build_runs_sort_order: "asc"}}
      iex> TuistWeb.Utilities.Query.sort_changed?(socket, "duration", "asc", :build_runs)
      false
  """
  @spec sort_changed?(Phoenix.LiveView.Socket.t(), String.t(), String.t(), atom()) :: boolean()
  def sort_changed?(socket, new_sort_by, new_sort_order, prefix) when is_atom(prefix) do
    sort_by_key = :"#{prefix}_sort_by"
    sort_order_key = :"#{prefix}_sort_order"

    Map.has_key?(socket.assigns, sort_by_key) and
      (Map.get(socket.assigns, sort_by_key) != new_sort_by or
         Map.get(socket.assigns, sort_order_key) != new_sort_order)
  end
end
