defmodule Tuist.Jams.Worker do
  @moduledoc "A short-lived Condukt session per durably leased run, not per stored jam."
  use Oban.Worker,
    queue: :jams,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:run_id, :attempt], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Accounts
  alias Tuist.Jams
  alias Tuist.Jams.Agent
  alias Tuist.Jams.Approval
  alias Tuist.Jams.Checkpoints
  alias Tuist.Jams.Checkpoints.Store
  alias Tuist.Jams.MCP
  alias Tuist.Jams.ModelFence
  alias Tuist.Jams.Provider
  alias Tuist.Jams.Shipping
  alias Tuist.Jams.Workspace
  alias Tuist.Repo

  @impl true
  def perform(%Oban.Job{args: %{"run_id" => id}}) do
    case Jams.claim(id) do
      {:ok, {run, jam}} -> execute(run, jam)
      {:error, :stale_run} -> :ok
      {:error, :forbidden} -> :ok
    end
  end

  defp execute(run, jam) do
    Process.flag(:trap_exit, true)
    parent = self()

    task =
      Task.Supervisor.async_nolink(Tuist.Jams.Tasks, fn ->
        Process.link(parent)
        run(run, jam, parent)
      end)

    try do
      now = System.monotonic_time(:millisecond)
      await(task, run, now + 900_000, now + 5_000, [])
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp await(task, run, deadline, heartbeat_at, models) do
    now = System.monotonic_time(:millisecond)

    # Check the absolute heartbeat deadline before receiving another message.
    # Model-process notifications must not postpone renewal of the shared lease.
    if now >= heartbeat_at do
      if now < deadline and Jams.heartbeat(run) == :ok and Jams.owns_run?(run.id, run.attempt) do
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
        Jams.finish(run, result)
        :ok

      {:jam_model_process, pid} ->
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

  defp run(%{kind: "ship", approval_id: id} = run, jam, _parent), do: Shipping.execute(jam, Repo.get!(Approval, id), run)

  defp run(run, %{repository: nil} = jam, parent), do: infer(run, jam, nil, parent)

  defp run(run, jam, parent) do
    with {:ok, context} <- Workspace.prepare(jam, run) do
      try do
        infer(run, context.jam, context, parent)
      after
        Workspace.release(context)
      end
    end
  end

  defp infer(run, jam, context, parent) do
    user = Accounts.get_user_by_id(jam.owner_id)

    with {:ok, prompt, store_opts} <- conversation(run, jam),
         {:ok, client_opts} <- Provider.client_opts(user, jam),
         {:ok, mcp_tools} <- MCP.discover(user, run) do
      opts =
        ModelFence.wrap(client_opts, run, parent) ++
          store_opts ++
          [
            id: run.session_id,
            system_prompt: if(context, do: Agent.prompt(jam), else: Agent.system_prompt()),
            tools: tools(run, context) ++ mcp_tools,
            load_project_instructions: false,
            max_tokens: 8192
          ]

      Condukt.Session.with_transient(Agent, opts, fn pid ->
        Process.link(pid)
        Condukt.run(pid, prompt, max_turns: 12, timeout: 240_000)
      end)
    end
  end

  defp conversation(run, jam) do
    case Checkpoints.load(run) do
      {:ok, snapshot} ->
        {:ok, "Continue the interrupted request. Never repeat an uncertain tool effect.",
         [session_store: {Store, snapshot: snapshot}]}

      :none ->
        {:ok, Agent.transcript(Jams.history(jam).messages), []}

      {:error, _} = error ->
        # Starting fresh could regenerate effects recorded only in the snapshot.
        error
    end
  end

  defp tools(run, context) do
    naming =
      Condukt.tool(
        name: "set_jam_name",
        description: "Give this Jam a concise descriptive title.",
        parameters: schema(%{name: %{type: "string", maxLength: 120}}),
        call: fn args, _ -> Jams.rename(run, args["name"]) end
      )

    if context do
      [
        naming
        | Enum.map(
            [
              {"read", "Read a UTF-8 file relative to the repository.", %{path: %{type: "string"}}},
              {"write", "Write a UTF-8 file relative to the repository.",
               %{path: %{type: "string"}, content: %{type: "string"}}},
              {"edit", "Replace one unique exact occurrence in a repository file.",
               %{path: %{type: "string"}, old_text: %{type: "string"}, new_text: %{type: "string"}}},
              {"bash", "Run a bounded shell command in the repository. No push, deployment or external writes.",
               %{command: %{type: "string"}}}
            ],
            fn {name, description, properties} ->
              Condukt.tool(
                name: name,
                description: description,
                parameters: schema(properties),
                call: fn args, _ ->
                  Jams.call_tool(run, Map.put(context, :invocation_id, Ecto.UUID.generate()), name, args)
                end
              )
            end
          )
      ]
    else
      [naming]
    end
  end

  defp schema(properties),
    do: %{type: "object", properties: properties, required: Map.keys(properties), additionalProperties: false}
end
