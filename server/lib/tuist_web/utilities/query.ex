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
end
