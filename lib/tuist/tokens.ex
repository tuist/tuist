defmodule Tuist.Tokens do
  @moduledoc ~S"""
  A module that provides functions for generating tokens.
  """

  def generate_token(size \\ 32) do
    :crypto.strong_rand_bytes(size)
    |> Base.url_encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim_trailing("=")
  end
end
