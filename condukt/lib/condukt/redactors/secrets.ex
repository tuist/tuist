defmodule Condukt.Redactors.Secrets do
  @moduledoc """
  Exact-match redactor for resolved session secrets.

  This redactor is built from a resolved `Condukt.Secrets` struct and is
  intended to be composed with any user-configured redactor. It replaces each
  resolved secret value with `[REDACTED:NAME]`, where `NAME` is the environment
  variable exposed to tools.
  """

  @behaviour Condukt.Redactor

  alias Condukt.Secrets

  @min_redacted_size 4

  @impl Condukt.Redactor
  def redact(text, opts) when is_binary(text) do
    opts
    |> Keyword.get(:secrets)
    |> Secrets.env()
    |> Enum.reduce(text, fn {name, value}, acc ->
      if redactable?(value) do
        String.replace(acc, value, "[REDACTED:#{name}]")
      else
        acc
      end
    end)
  end

  defp redactable?(value), do: is_binary(value) and byte_size(value) >= @min_redacted_size
end
