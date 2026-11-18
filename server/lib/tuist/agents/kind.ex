defmodule Tuist.Agents.Kind do
  @moduledoc """
  What a product feature implements to have its durable sessions hosted by
  `Tuist.Agents.Runner`. A session's `kind` in `agent_sessions` names the
  module, through the runner's `:kinds` option or `config :tuist, Tuist.Agents.Runner, kinds: %{...}`.

  The runner never waits on a session's process: it asks with messages and
  learns the outcome from replies and the process's exit, so one slow
  session cannot hold up the renewal of every other lease on the node.
  """

  @doc """
  Starts the session `id` under the lease `epoch`, with
  `Tuist.Agents.SessionStore.store(kind, id, epoch)` as its store,
  and has it continue any run it was interrupted in. Returns the session's pid.
  """
  @callback start(id :: String.t(), epoch :: pos_integer()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Asks the session to stop if it has nothing to do. Deciding and stopping
  must be one step of the session's process, so work that arrives in
  between is never stopped with it. A session that stops sends
  `{Tuist.Agents.Kind, :idle, pid, token}` to `reply_to` before it exits;
  a busy one ignores the request.
  """
  @callback stop_if_idle(pid(), reply_to :: pid(), token :: term()) :: :ok

  @doc """
  Asks the session to hand itself to another host: stop at once and leave
  its work, such as sandbox commands, for the next host to resume. It exits
  when done.
  """
  @callback drain(pid()) :: :ok
end
