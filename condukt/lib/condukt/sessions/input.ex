defmodule Condukt.Sessions.Input do
  @moduledoc """
  Input submitted to a session by id with `Condukt.Sessions.submit/3`.

  A session takes each input once, by `:request_id`, as a user message that
  waits behind its running turn and any queued input, and starts a turn when
  the session is idle. The input is **settled** when the turn it started
  ends: with the turn's answer, its error, or `:aborted`. An input from
  another session (`:from`) can tell that session when it settles:

    * `:notify` - a key. The settled outcome is delivered to `:from` as a
      `Condukt.Sessions.Settled` signal under this key, which wakes a tool
      call parked on `{Condukt.Sessions.Settled, key}`.
    * `:report` - when `true`, an outcome that no parked call took is
      submitted back to `:from` as input, so the sender hears the answer
      even when it stopped waiting or was not running.

  Inputs are plain data, so an `Condukt.Sessions.Inbox` can store them.
  """

  @enforce_keys [:session_id, :request_id, :text]
  defstruct [:session_id, :request_id, :text, :from, :notify, report: false, submitted_at: nil]

  @options [:request_id, :from, :notify, :report]

  @doc false
  def new(session_id, text, opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
      nil -> validate(build(session_id, text, opts))
      key -> {:error, {:invalid_option, key}}
    end
  end

  defp build(session_id, text, opts) do
    %__MODULE__{
      session_id: session_id,
      request_id: Keyword.get(opts, :request_id),
      text: text,
      from: Keyword.get(opts, :from),
      notify: Keyword.get(opts, :notify),
      report: Keyword.get(opts, :report, false),
      submitted_at: DateTime.utc_now()
    }
  end

  defp validate(%__MODULE__{} = input) do
    checks = [
      session_id: id?(input.session_id),
      request_id: id?(input.request_id),
      text: id?(input.text),
      from: optional_id?(input.from),
      notify: optional_id?(input.notify),
      report: is_boolean(input.report)
    ]

    case Enum.find(checks, fn {_field, valid?} -> not valid? end) do
      {field, false} -> {:error, {:"invalid_#{field}", Map.fetch!(input, field)}}
      nil when is_nil(input.from) and (input.notify != nil or input.report) -> {:error, :reply_needs_from}
      nil -> {:ok, input}
    end
  end

  # Ids, keys, and text are non-empty strings.
  defp id?(value), do: is_binary(value) and value != ""
  defp optional_id?(value), do: is_nil(value) or id?(value)
end
