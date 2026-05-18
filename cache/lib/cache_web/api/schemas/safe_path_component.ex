defmodule CacheWeb.API.Schemas.SafePathComponent do
  @moduledoc """
  Shared validation for request params that are used to construct storage paths.
  """

  alias OpenApiSpex.Schema

  @pattern "^(?!\\.{1,2}$)[^/\\\\\\x{0}]+$"
  @regex Regex.compile!(@pattern)
  @schema %Schema{
    type: :string,
    minLength: 1,
    pattern: @pattern
  }

  def schema, do: @schema

  def valid?(value) when is_binary(value), do: Regex.match?(@regex, value)
  def valid?(_), do: false

  def valid_all?(values) when is_list(values) do
    Enum.all?(values, &valid?/1)
  end
end
