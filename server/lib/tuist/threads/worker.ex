defmodule Tuist.Threads.Worker do
  @moduledoc "A short-lived Condukt session per durably leased run, not per stored thread."
  use Oban.Worker,
    queue: :threads,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:run_id, :attempt], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Accounts
  alias Tuist.Repo
  alias Tuist.Threads
  alias Tuist.Threads.Agent
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Checkpoints
  alias Tuist.Threads.Checkpoints.Store
  alias Tuist.Threads.MCP
  alias Tuist.Threads.ModelFence
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.ToolLog
  alias Tuist.Threads.Workspace

  # Condukt's built-in tools, run in the thread's sandbox through
  # `Tuist.Threads.Sandbox`. `ToolLog` records their calls on the thread.
  @repository_tools [
    Condukt.Tools.Read,
    Condukt.Tools.Glob,
    Condukt.Tools.Grep,
    Condukt.Tools.Write,
    Condukt.Tools.Edit,
    Condukt.Tools.Bash
  ]
  @logged_tools Enum.map(@repository_tools, & &1.name())

  # A run's whole budget, then how much of it stays after the session answers,
  # to record the outcome, and after the last command it runs ends, for the
  # model to answer. A command's timeout is cut to end before the session's
  # call does, so a long build ends with a result rather than an abort that
  # leaves its call's outcome unknown.
  @run_ms 900_000
  @finish_ms 30_000
  @answer_ms 60_000

  @impl true
  def perform(%Oban.Job{args: %{"run_id" => id}}) do
    case Threads.claim(id) do
      {:ok, {run, thread}} -> execute(run, thread)
      {:error, :stale_run} -> :ok
      {:error, :forbidden} -> :ok
    end
  end

  defp execute(run, thread) do
    Process.flag(:trap_exit, true)
    parent = self()

    now = System.monotonic_time(:millisecond)
    deadline = now + @run_ms

    task =
      Task.Supervisor.async_nolink(Tuist.Threads.Tasks, fn ->
        Process.link(parent)
        run(run, thread, parent, deadline)
      end)

    try do
      await(task, run, deadline, now + 5_000, [])
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp await(task, run, deadline, heartbeat_at, models) do
    now = System.monotonic_time(:millisecond)

    # Check the absolute heartbeat deadline before receiving another message.
    # Model-process notifications must not postpone renewal of the shared lease.
    if now >= heartbeat_at do
      if now < deadline and Threads.heartbeat(run) == :ok and Threads.owns_run?(run.id, run.attempt) do
        await(task, run, deadline, System.monotonic_time(:millisecond) + 5_000, models)
      else
        stop_models(models)
        :ok
      end
    else
      await_message(task, run, deadline, heartbeat_at, models, heartbeat_at - now)
    end
  end

  defp await_message(task, run, deadline, heartbeat_at, models, timeout) do
    receive do
      {ref, result} when ref == task.ref ->
        Process.demonitor(task.ref, [:flush])
        stop_models(models)
        Threads.finish(run, result)
        :ok

      {:thread_model_process, pid} ->
        await(task, run, deadline, heartbeat_at, [pid | models])

      {:DOWN, ref, :process, _pid, _reason} when ref == task.ref ->
        stop_models(models)
        # Retain the last checkpoint and reservations. The shared lease sweeper
        # decides whether a safe resume is possible after this worker dies.
        :ok

      {:EXIT, _pid, :normal} ->
        await(task, run, deadline, heartbeat_at, models)

      {:EXIT, _pid, _reason} ->
        stop_models(models)
        :ok
    after
      timeout -> await(task, run, deadline, heartbeat_at, models)
    end
  end

  defp stop_models(models), do: Enum.each(models, &Process.exit(&1, :kill))

  defp run(%{kind: "ship", approval_id: id} = run, thread, _parent, _deadline),
    do: Shipping.execute(thread, Repo.get!(Approval, id), run)

  defp run(run, %{repository: nil} = thread, parent, deadline), do: infer(run, thread, nil, parent, deadline)

  defp run(run, thread, parent, deadline) do
    with {:ok, context} <- Workspace.prepare(thread, run) do
      try do
        infer(run, context.thread, context, parent, deadline)
      after
        Workspace.release(context)
      end
    end
  end

  defp infer(run, thread, context, parent, deadline) do
    user = Accounts.get_user_by_id(thread.owner_id)

    with {:ok, prompt, store_opts} <- conversation(run, thread),
         {:ok, client_opts} <- Provider.client_opts(user, thread),
         {:ok, mcp_tools} <- mcp_tools(user, run) do
      opts =
        ModelFence.wrap(client_opts, run, parent) ++
          store_opts ++
          [
            id: run.session_id,
            system_prompt: if(context, do: Agent.prompt(thread), else: Agent.system_prompt()),
            tools: tools(run, context) ++ mcp_tools,
            hooks: [{ToolLog, run: run, tools: @logged_tools}],
            load_project_instructions: false,
            max_tokens: 8192
          ] ++ sandbox(thread, context, deadline)

      # Registered under its id in the cluster-wide registry (see
      # `config/config.exs`), so a parked command's exit reaches it from any
      # node (`Tuist.Threads.ExitWatchWorker`).
      with {:ok, pid} <- Condukt.Sessions.start(Agent, opts) do
        Process.link(pid)

        try do
          # Taken from the deadline now, after the setup above, which the
          # budget does not count, so the session answers before it.
          Condukt.run(pid, prompt, max_turns: 12, timeout: left(deadline, @finish_ms))
        after
          Process.unlink(pid)
          # Stopping aborts calls still running or parked, and their commands.
          Condukt.Sessions.stop(run.session_id)
          Threads.cancel_tool_calls(run, @logged_tools)
        end
      end
    end
  end

  defp left(deadline, margin), do: max(deadline - margin - System.monotonic_time(:millisecond), 1)

  defp sandbox(_thread, nil, _deadline), do: []

  defp sandbox(thread, context, deadline) do
    [
      cwd: "/workspace/repository",
      sandbox:
        {Tuist.Threads.Sandbox,
         sandbox_id: context.sandbox.id,
         account_id: thread.account_id,
         residency: context.residency,
         cwd: "/workspace/repository",
         commands_end_by: System.os_time(:millisecond) + left(deadline, @finish_ms + @answer_ms)}
    ]
  end

  defp mcp_tools(user, run) do
    case MCP.discover(user, run) do
      {:ok, tools} -> {:ok, tools}
      {:error, :stale_run} = error -> error
      # Profile integrations are optional. Their discovery failures must not
      # prevent the durable run from answering with its built-in tools.
      {:error, _} -> {:ok, []}
    end
  end

  defp conversation(run, thread) do
    case Checkpoints.load(run) do
      {:ok, snapshot} ->
        {:ok, "Continue the interrupted request. Never repeat an uncertain tool effect.",
         [session_store: {Store, snapshot: snapshot}]}

      :none ->
        {:ok, Agent.transcript(Threads.history(thread).messages), []}

      {:error, _} = error ->
        # Starting fresh could regenerate effects recorded only in the snapshot.
        error
    end
  end

  defp tools(run, context) do
    naming =
      Condukt.tool(
        name: "set_thread_name",
        description: "Give this Thread a concise descriptive title.",
        parameters: schema(%{name: %{type: "string", maxLength: 120}}),
        call: fn args, _ -> Threads.rename(run, args["name"]) end
      )

    if context, do: [naming | @repository_tools], else: [naming]
  end

  defp schema(properties),
    do: %{type: "object", properties: properties, required: Map.keys(properties), additionalProperties: false}
end
