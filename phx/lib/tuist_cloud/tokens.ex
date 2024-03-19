defmodule TuistCloud.Tokens do
  @moduledoc ~S"""
  A module that provides functions for generating tokens.
  """

  def generate_authentication_token() do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim_trailing("=")
  end
end
