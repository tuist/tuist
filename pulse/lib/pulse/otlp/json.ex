defmodule Pulse.OTLP.JSON do
  @moduledoc false
  alias Pulse.Codec.NIF
  # Only OTLP receivers use schema-aware integral lexemes and signed zero.
  # The general JSON library and its fallback semantics remain unchanged.
  alias Pulse.OTLP.JSONReference

  def decode!(body, signal \\ :all) when signal in [:all, :logs, :metrics, :traces] do
    result = if signal == :all, do: NIF.otlp_json_decode(body), else: NIF.otlp_json_decode_scoped(body, signal)

    case result do
      {:ok, value} -> value
      :fallback -> JSONReference.decode!(body, signal)
    end
  end
end
