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
end
