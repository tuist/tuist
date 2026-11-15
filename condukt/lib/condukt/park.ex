defmodule Condukt.Park do
  @moduledoc """
  How a tool call waits for an outside event or a time.

  A tool parks by returning `{:park, state, opts}` from `c:Condukt.Tool.call/2`
  instead of a result, much as a `GenServer` callback returns
  `{:noreply, state, timeout}`:

      {:park, %{build_id: build.id},
       signals: [{MyApp.Signals.CiResult, "ci-" <> context.tool_call_id}],
       timeout: :timer.hours(2)}

  Options:

    * `:signals` - `{kind, key}` pairs to wake on, where `kind` is a
      `Condukt.Signal` module and `key` a string. The first one delivered
      wakes the call.
    * `:timeout` - milliseconds from now after which the call wakes anyway.
    * `:until` - a `DateTime` after which the call wakes anyway. Use either
      `:until` or `:timeout`, not both.

  A park needs signals, a deadline, or both, and the tool must implement
  `c:Condukt.Tool.wake/3`. While a call is parked no tool code runs: the
  turn's worker blocks in `receive`, the tool timeout does not apply, and the
  session holds the wait as data. When the call wakes, the session calls
  `wake/3` with `{:signal, {kind, key}, value}` or `:timeout`, and `state`.

  The deadline is stored as wall-clock time rather than as a timer, so it
  means the same thing after the session process that armed it is gone. A
  running session arms it with `Process.send_after/3`.

  See the [Waiting for Events](parking.md) guide.
  """

  alias Condukt.Signal

  defstruct signals: [], until: nil

  @options [:signals, :timeout, :until]

  @doc """
  Validates park options, returning `{:ok, park}` or `{:error, reason}`.

  `until` in the result is a Unix time in milliseconds, or `nil`.
  """
  def new(opts) when is_list(opts) do
    with :ok <- known_options(opts),
         {:ok, until} <- deadline(Keyword.get(opts, :until), Keyword.get(opts, :timeout)) do
      validate(%__MODULE__{signals: Keyword.get(opts, :signals, []), until: until})
    end
  end

  def new(other), do: {:error, {:invalid_options, other}}

  @doc false
  # The public view of a park or a parked call's wait, with the deadline as a
  # `DateTime`.
  def describe(%{signals: signals, until: until}), do: %{signals: signals, until: to_datetime(until)}

  @doc false
  def to_datetime(nil), do: nil
  def to_datetime(ms), do: DateTime.from_unix!(ms, :millisecond)

  defp known_options(opts) do
    if Keyword.keyword?(opts) do
      case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
        nil -> :ok
        key -> {:error, {:unknown_option, key}}
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  defp deadline(nil, nil), do: {:ok, nil}
  defp deadline(%DateTime{} = until, nil), do: {:ok, DateTime.to_unix(until, :millisecond)}
  defp deadline(nil, ms) when is_integer(ms) and ms >= 0, do: {:ok, System.os_time(:millisecond) + ms}
  defp deadline(nil, ms), do: {:error, {:invalid_timeout, ms}}
  defp deadline(until, nil), do: {:error, {:invalid_until, until}}
  defp deadline(_until, _timeout), do: {:error, :until_and_timeout}

  defp validate(%__MODULE__{signals: signals, until: until} = park) do
    cond do
      not is_list(signals) -> {:error, {:invalid_signals, signals}}
      invalid = Enum.find(signals, &(not signal_key?(&1))) -> {:error, {:invalid_signal, invalid}}
      length(Enum.uniq(signals)) != length(signals) -> {:error, :duplicate_signals}
      signals == [] and is_nil(until) -> {:error, :never_wakes}
      true -> {:ok, park}
    end
  end

  defp signal_key?({kind, key}) when is_binary(key), do: Signal.kind?(kind)
  defp signal_key?(_other), do: false
end
