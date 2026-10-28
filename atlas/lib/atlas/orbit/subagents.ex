defmodule Atlas.Orbit.Subagents do
  @moduledoc """
  Durable, read-only research delegation within an existing Orbit run.

  Register `tool(run)` alongside `Tools.build(run)`, never Condukt's raw
  `:subagents` option. Children use the same agent and fenced provider as their
  parent, but receive only explicitly built, audience-checked read tools.
  """

  @behaviour Plug

  import Ecto.Query

  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.ModelFence
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Tools
  alias Atlas.Repo
  alias Atlas.Users.User
  alias Condukt.Compactor.ToolResultPrune
  alias Condukt.Tools.Subagent

  @timeout :timer.seconds(60)
  @failed "The research task failed or was interrupted."

  def tool(%Run{} = run) do
    Condukt.tool(
      name: "task",
      description:
        "Delegate one bounded, independent Atlas research question to a read-only helper. " <>
          "Its lookups appear nested under this task. At most two helpers at once and four per run. " <>
          "Helpers cannot delegate, write, browse the web, or execute commands.",
      parameters: %{
        "type" => "object",
        "properties" => %{"task" => %{"type" => "string", "minLength" => 1, "maxLength" => 4_000}},
        "required" => ["task"],
        "additionalProperties" => false
      },
      call: fn args, context -> Tools.task(run, args, context) end
    )
  end

  @doc false
  def valid_args?(%{"task" => task} = args) when map_size(args) == 1 and is_binary(task) do
    byte_size(task) <= 16_000 and String.valid?(task) and String.length(task) <= 4_000 and String.trim(task) != ""
  end

  def valid_args?(_args), do: false

  @doc false
  def reserve!(run) do
    tasks = from message in Message, where: message.run_id == ^run.id and message.tool_name == "task"

    if Repo.aggregate(tasks, :count) >= 4 or
         Repo.aggregate(where(tasks, [message], message.tool_status == "running"), :count) >= 2 do
      Repo.rollback(:subagent_budget)
    end
  end

  @doc false
  def recorded_error(%Message{tool_status: "running"}), do: "This research task is already in progress."
  def recorded_error(_message), do: @failed

  @doc false
  def authorize_parent!(thread, run, parent_message_id) do
    if !parent_active?(thread, run, parent_message_id), do: Repo.rollback(:unavailable)
  end

  @doc false
  def parent_active?(_thread, _run, nil), do: true

  def parent_active?(thread, run, parent_message_id) do
    case Repo.get(Message, parent_message_id) do
      %Message{kind: "tool", tool_name: "task", tool_status: "running", parent_message_id: nil, author_id: nil} = parent ->
        parent.run_id == run.id and parent.thread_id == thread.id and
          DateTime.diff(DateTime.utc_now(), parent.inserted_at, :millisecond) < @timeout

      _ ->
        false
    end
  end

  @doc false
  def execute(run, message, %{"task" => task}, context) do
    with true <- fenced_context?(context),
         {:ok, prompt} <- authorize(run, message.id) do
      owner = self()
      deadline = System.monotonic_time(:millisecond) + @timeout
      guardian = spawn_link(fn -> guard(owner, deadline) end)
      monitor = Process.monitor(guardian)
      {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

      try do
        child_opts = [
          tools: Tools.build(run, message.id),
          system_prompt: prompt,
          load_project_instructions: false,
          subagents: [],
          session_store: nil,
          compactor: {ToolResultPrune, keep_recent: 2, max_size: 4_000},
          llm_request_options: child_request_options(context, guardian, run, message.id),
          timeout: @timeout,
          max_turns: 6
        ]

        context =
          context
          |> Map.put(:opts, [])
          |> Map.put(:subagents, research: {Agent, child_opts})
          |> Map.put(:subagent_supervisor, supervisor)

        case Subagent.call(%{"role" => "research", "task" => task}, context) do
          {:ok, result} when is_binary(result) and result != "" -> {:ok, result}
          _ -> {:error, @failed}
        end
      rescue
        _ -> {:error, @failed}
      catch
        :exit, _ -> {:error, @failed}
      after
        # Condukt's model loop is unlinked from its session. The guardian also
        # owns those loops, so timeout and normal session cleanup cannot orphan
        # a blocked provider request or subsequent child tool calls.
        send(guardian, :stop)

        receive do
          {:DOWN, ^monitor, :process, ^guardian, _reason} -> :ok
        end

        if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
      end
    else
      _ -> {:error, @failed}
    end
  end

  defp fenced_context?(context) do
    match?(
      {ModelFence, _opts},
      get_in(context, [:llm_request_options, :req_http_options, :plug])
    )
  end

  defp authorize(run, parent_message_id) do
    Runs.with_attempt(run.id, run.resume_count, fn thread, current_run ->
      authorize_parent!(thread, current_run, parent_message_id)
      acting_user = current_run.acting_user_id && Repo.get(User, current_run.acting_user_id)

      with nil <- current_run.cancel_requested_at,
           "active" <- thread.status,
           {:ok, audience} <- Access.authorize_tool(thread, acting_user, []) do
        Agent.system_prompt(thread, audience) <>
          "\nYou are Pip's research helper. Answer only the delegated question with evidence. " <>
          "You have no authority to delegate, write, approve, browse, or execute commands. " <>
          "Return findings to Pip, not a final reply to the people in the thread."
      else
        _ -> Repo.rollback(:unavailable)
      end
    end)
  end

  defp child_request_options(context, guardian, run, parent_message_id) do
    Keyword.update!(context.llm_request_options, :req_http_options, fn options ->
      Keyword.update!(options, :plug, fn inner ->
        {__MODULE__, guardian: guardian, run: run, parent_message_id: parent_message_id, inner: inner}
      end)
    end)
  end

  @doc false
  def register_tool(context) do
    case get_in(context, [:llm_request_options, :req_http_options, :plug]) do
      {__MODULE__, opts} -> register_model(Keyword.fetch!(opts, :guardian))
      _ -> :ok
    end
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    guardian = Keyword.fetch!(opts, :guardian)

    with :ok <- register_model(guardian),
         {:ok, _prompt} <- authorize(Keyword.fetch!(opts, :run), Keyword.fetch!(opts, :parent_message_id)) do
      {module, inner_opts} = Keyword.fetch!(opts, :inner)
      module.call(conn, module.init(inner_opts))
    else
      _ ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(409, JSON.encode!(%{error: %{message: @failed, type: "fenced"}}))
    end
  end

  defp register_model(guardian) do
    ref = Process.monitor(guardian)
    send(guardian, {:model, self(), ref})

    receive do
      {^ref, :ok} ->
        Process.demonitor(ref, [:flush])
        :ok

      {:DOWN, ^ref, :process, ^guardian, _reason} ->
        :error
    end
  end

  defp guard(owner, deadline) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)
    guard(owner, monitor, deadline, MapSet.new())
  end

  defp guard(owner, monitor, deadline, models) do
    receive do
      {:model, pid, ref} ->
        Process.link(pid)
        send(pid, {ref, :ok})
        guard(owner, monitor, deadline, MapSet.put(models, pid))

      :stop ->
        stop_models(models)

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        stop_models(models)

      {:EXIT, ^owner, _reason} ->
        stop_models(models)

      {:EXIT, pid, _reason} ->
        guard(owner, monitor, deadline, MapSet.delete(models, pid))
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> stop_models(models)
    end
  end

  defp stop_models(models), do: Enum.each(models, &Process.exit(&1, :kill))
end
