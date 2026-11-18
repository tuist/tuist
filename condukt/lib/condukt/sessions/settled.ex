defmodule Condukt.Sessions.Settled do
  @moduledoc """
  The signal kind that tells a session an input it submitted has settled.

  A session that submits input with `notify: key` (see
  `Condukt.Sessions.submit/3`) receives the outcome as a signal of this kind
  under `key` once the turn the input started ends. A tool call waits for it
  by parking on `{Condukt.Sessions.Settled, key}`:

      {:park, state, signals: [{Condukt.Sessions.Settled, key}], timeout: :timer.hours(1)}

  `wake/3` then receives `{:signal, {Condukt.Sessions.Settled, key}, value}`,
  where `value` is

      %{session_id: target_id, request_id: request_id, outcome: outcome}

  and `outcome` is `{:ok, answer}`, `{:error, reason}`, or `:aborted`.
  """

  @behaviour Condukt.Signal

  @impl true
  def cast(%{session_id: session_id, request_id: request_id, outcome: outcome} = value)
      when is_binary(session_id) and is_binary(request_id) do
    if outcome?(outcome),
      do: {:ok, Map.take(value, [:session_id, :request_id, :outcome])},
      else: {:error, {:invalid_outcome, outcome}}
  end

  def cast(_value), do: {:error, :expected_settled_submission}

  defp outcome?({:ok, answer}) when is_binary(answer), do: true
  defp outcome?({:error, _reason}), do: true
  defp outcome?(:aborted), do: true
  defp outcome?(_outcome), do: false
end
