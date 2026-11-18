defmodule Condukt.Signal do
  @moduledoc """
  A kind of value delivered to a parked tool call from outside the session.

  A signal kind is a module that checks the values sent under it, such as a CI
  webhook's result or a person's answer. A tool parks on keys of a kind, and
  the host delivers a value with `Condukt.signal/4`:

      defmodule MyApp.Signals.CiResult do
        @behaviour Condukt.Signal

        @impl true
        def cast(%{"status" => status, "log_url" => url}) when status in ["passed", "failed"],
          do: {:ok, %{status: status, log_url: url}}

        def cast(_value), do: {:error, :expected_status_and_log_url}
      end

  `cast/1` runs in the process that delivers the signal, before the session
  sees it. A value it rejects is answered `{:error, {:invalid, reason}}` and kept
  nowhere. Keep values small: send a reference, such as a build id, for
  anything large.

  See the [Waiting for Events](parking.md) guide.
  """

  @doc """
  Checks and normalizes a delivered value.
  """
  @callback cast(value :: term()) :: {:ok, term()} | {:error, term()}

  @doc false
  def kind?(kind) when is_atom(kind), do: Code.ensure_loaded?(kind) and function_exported?(kind, :cast, 1)
  def kind?(_kind), do: false

  @doc false
  def cast(kind, key, value) do
    cond do
      not kind?(kind) -> {:error, {:not_a_signal_kind, kind}}
      not is_binary(key) -> {:error, {:invalid_key, key}}
      true -> cast_value(kind, value)
    end
  end

  defp cast_value(kind, value) do
    case kind.cast(value) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_cast_result, other}}
    end
  end
end
