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
end
