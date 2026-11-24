defmodule LuftServer.Agents.Kind do
  @moduledoc """
  Contract for a durable session hosted by `LuftServer.Agents.Runner`.
  Kinds are registered through the runner's `:kinds` option or application config.
  Callbacks must not wait for a session process to respond.
  """

  @doc "Starts and resumes a session with `SessionStore.store(kind, id, epoch)`."
  @callback start(id :: String.t(), epoch :: pos_integer()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Atomically stops if idle, sending `{LuftServer.Agents.Kind, :idle, pid, token}`
  to `reply_to` before exiting. Busy sessions ignore the request.
  """
  @callback stop_if_idle(pid(), reply_to :: pid(), token :: term()) :: :ok

  @doc "Stops for handoff, leaving external work for the next host to resume."
  @callback drain(pid()) :: :ok
end
