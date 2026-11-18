defmodule Condukt.Sessions.Resumer do
  @moduledoc """
  Behaviour for starting a session that input was stored for while no node
  ran it.

  Where a session runs, and how starting one is scheduled, is the host's
  policy, separate from where its input is stored (`Condukt.Sessions.Inbox`).
  When `Condukt.Sessions.submit/3` has stored an input and finds no session
  running under its id, it calls `c:resume/2`. The resumed session takes its
  stored input as it starts.

      config :condukt, resumer: {MyApp.SessionResumer, []}

  `c:resume/2` runs in the process that submitted the input, so it should
  only start the session, or hand that to whatever the host schedules work
  with, and return. It may be called while the session is starting, or runs
  on a node the registry has not seen yet, so make it idempotent: work that
  finds the session already running calls `Condukt.Sessions.drain/1` instead
  of starting another.

  `Condukt.Sessions.submit/3` also takes a `:resumer` option, which may also be
  a function of the session id, for tests and single-node hosts. Without a
  resumer, input for a session that is not running waits until something
  starts it.
  """

  @doc "Starts the session `session_id`, or schedules that, and returns."
  @callback resume(session_id :: String.t(), opts :: keyword()) :: :ok

  @doc false
  def default, do: Application.get_env(:condukt, :resumer)

  @doc false
  def resume(nil, _session_id), do: :ok

  def resume(fun, session_id) when is_function(fun, 1) do
    _ = fun.(session_id)
    :ok
  end

  def resume({module, opts}, session_id) when is_atom(module) and is_list(opts) do
    _ = module.resume(session_id, opts)
    :ok
  end

  def resume(module, session_id) when is_atom(module), do: resume({module, []}, session_id)
end
