defmodule Tuist.Tokens do
  @moduledoc ~S"""
  A module that provides functions for generating tokens.
  """

  def generate_token(size \\ 32) do
    size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim_trailing("=")
  end

  @doc """
  The digest legacy user and project tokens are stored and looked up by. They
  are 32 random bytes, so an unsalted SHA-256 is enough to keep a database
  reader from authenticating with them while still allowing a direct lookup.
  Matches PostgreSQL's `sha256(convert_to(token, 'UTF8'))`.
  """
  def legacy_token_hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)
end
