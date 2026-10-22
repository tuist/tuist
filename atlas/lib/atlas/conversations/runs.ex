defmodule Atlas.Conversations.Runs do
  @moduledoc """
  Durable, fenced assistant runs.

  A run is queued in the same transaction as the message that triggered it and
  executed by `Atlas.Conversations.Workers.RunConversation`. Only a queued run
  can start, so duplicate or rescued jobs are no-ops.

  ## Attempts and fencing

  Each start of a run is an attempt identified by `resume_count`. Every write
  an attempt makes (tool cards, ratchet, reply, checkpoint, final status) runs
  through `with_attempt/3`, which locks the conversation and then the run, the
  order used everywhere, and refuses to write unless the run is still `running`
  under the same attempt. Heartbeats are a single conditional update on that
  attempt. A superseded worker therefore cannot write into its successor,
  finish it, or checkpoint it.

  ## Surviving deploys and lost replicas

  On graceful shutdown the worker checkpoints its attempt: the run goes back to
  `queued` with the next attempt number and a resume job is enqueued for another
  replica. If a replica dies without shutting down, the sweeper finds the stale
  heartbeat, re-checks it under the locks, and does the same. After
  `@max_resumes` checkpoints a run is marked `interrupted`. A crash of the run
  itself (not a shutdown) fails the run with a notice instead of looping. Human
  messages are never lost: they live in the conversation log, and any addressed
  after a run's trigger start a follow-up run.

  Resumption restores the latest per-turn Condukt snapshot recorded for the run
  (`Atlas.Conversations.Checkpoints`): the exact protocol messages handed to the
  model at the start of its last turn, including the triggering request and the
  results of tools that completed in earlier turns. The model call that was in
  flight, and any tool calls it requested, are made again. That is safe because
  every conversation tool is read-only; write actions will be approval items
  that never execute automatically. When no snapshot exists (the attempt stopped
  before its first model call) or it cannot be decoded, the run restarts from
  the bounded conversation transcript, which lists this run's completed tool
  calls with their bounded results. That is a restart with context, not an
  exact continuation.

  Runs use the inference profile bound to the `conversations` role through the
  in-process relay. There is no fallback to any other profile.
  """

  import Ecto.Query

  alias Atlas.Agents.Sessions
  alias Atlas.Conversations
  alias Atlas.Conversations.Access
  alias Atlas.Conversations.Agent
  alias Atlas.Conversations.Checkpoints
  alias Atlas.Conversations.Conversation
  alias Atlas.Conversations.Message
  alias Atlas.Conversations.ModelFence
  alias Atlas.Conversations.Rendering
  alias Atlas.Conversations.Run
  alias Atlas.Conversations.Tools
  alias Atlas.Conversations.Workers.RunConversation
  alias Atlas.Inference
  alias Atlas.LLMs.Runner
  alias Atlas.Repo
  alias Atlas.Users.User

  require Logger

  @heartbeat_interval :timer.seconds(5)
  # A lease lasts 60 seconds of database time after the last renewal. A worker
  # stops itself 45 seconds after starting its last successful renewal, so it
  # is gone before the lease can transfer to another replica.
  @stale_after_seconds 60
  @self_fence_after :timer.seconds(45)
  @max_duration :timer.minutes(4)
  @max_turns 8
  @max_tokens 2_048
  @reply_limit 16_000
  @max_resumes 3
  @transcript_messages 40

  def max_resumes, do: @max_resumes
  def stale_after_seconds, do: @stale_after_seconds

  ## Fencing

  @doc """
  Runs `fun.(conversation, run)` holding the conversation lock and then the run
  lock, only while the run is `running` under `attempt`. Returns `{:ok, value}`,
  `{:error, :stale}`, or `{:error, reason}` when `fun` rolls back.
  """
  def with_attempt(run_id, attempt, fun) when is_function(fun, 2) do
    case conversation_id(run_id) do
      nil ->
        {:error, :stale}

      conversation_id ->
        Repo.transaction(fn ->
          conversation = Conversations.lock!(conversation_id)
          run = lock_run!(run_id)

          if run.status == "running" and run.resume_count == attempt,
            do: fun.(conversation, run),
            else: Repo.rollback(:stale)
        end)
    end
  end

  defp lock_run!(run_id), do: Repo.one!(from run in Run, where: run.id == ^run_id, lock: "FOR UPDATE")

  ## Execution

  @doc """
  Executes a queued run. `opts[:client_opts]` replaces the model client options
  in tests; production always uses the conversations profile.
  """
  def execute(run_id, opts \\ []) do
    case start(run_id) do
      {:ok, run} -> supervise(run, opts)
      :skip -> :ok
    end
  end

  defp start(run_id) do
    with conversation_id when is_binary(conversation_id) <- conversation_id(run_id),
         {:ok, result} <- Repo.transaction(fn -> start_locked(conversation_id, run_id) end) do
      case result do
        %Run{} = run ->
          Conversations.notify_changed(run.conversation_id)
          {:ok, run}

        :finalized ->
          Conversations.notify_changed(conversation_id)
          follow_up(conversation_id)
          :skip

        :skip ->
          :skip
      end
    else
      _ -> :skip
    end
  end

  defp start_locked(conversation_id, run_id) do
    conversation = Conversations.lock!(conversation_id)
    run = lock_run!(run_id)

    case startable(conversation, run) do
      :ok ->
        mark_running!(run)

      :not_queued ->
        :skip

      :cancelled ->
        finalize!(run, "cancelled", nil, "Stopped before the assistant started.", conversation)
        :finalized

      :access_changed ->
        finalize!(
          run,
          "cancelled",
          "access_changed",
          "Stopped because access to this conversation changed.",
          conversation
        )

        :finalized
    end
  end

  defp startable(conversation, run) do
    acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)

    cond do
      run.status != "queued" -> :not_queued
      not is_nil(run.cancel_requested_at) -> :cancelled
      conversation.status != "active" or not Access.can_read?(conversation, acting_user) -> :access_changed
      true -> :ok
    end
  end

  defp mark_running!(run) do
    binding_id =
      case Inference.fetch_atlas_role(:conversations) do
        {:ok, binding, _token} -> binding.id
        _ -> run.model_binding_id
      end

    run =
      run
      |> Ecto.Changeset.change(
        status: "running",
        started_at: run.started_at || DateTime.utc_now(),
        session_id: Condukt.SessionID.generate(),
        model_binding_id: binding_id
      )
      |> Repo.update!()

    Repo.update_all(
      from(r in Run, where: r.id == ^run.id, update: [set: [heartbeat_at: fragment("clock_timestamp()")]]),
      []
    )

    run
  end

  defp supervise(run, opts) do
    # The Oban job process traps exits so a deploy's shutdown signal reaches the
    # await loop as a message and the attempt can be checkpointed.
    # The run task is linked to this job process and the model session is linked
    # to the task, so if this worker dies for any reason its model and tool calls
    # die with it: no orphaned session keeps running beside a successor.
    Process.flag(:trap_exit, true)
    Conversations.subscribe_run(run.id)
    parent = self()
    task = Task.Supervisor.async(Atlas.TaskSupervisor, fn -> invoke(run, parent, opts) end)
    Process.send_after(self(), :heartbeat, Keyword.get(opts, :heartbeat_interval, @heartbeat_interval))
    deadline = Process.send_after(self(), :deadline, Keyword.get(opts, :max_duration, @max_duration))

    outcome =
      await(%{
        task: task,
        session: nil,
        run: run,
        timed_out: false,
        opts: opts,
        renewed_at: System.monotonic_time(:millisecond),
        model_processes: MapSet.new(),
        stopping: false
      })

    Process.cancel_timer(deadline)

    case outcome do
      :checkpoint -> checkpoint(run.id, run.resume_count)
      :stale -> :stale
      result -> complete(run.id, run.resume_count, result)
    end

    :ok
  end

  defp await(%{task: %Task{ref: ref}} = state) do
    receive do
      {^ref, result} ->
        Process.demonitor(ref, [:flush])
        if state.timed_out, do: {:error, :timeout}, else: result

      {:DOWN, ^ref, :process, _pid, reason} ->
        task_down(state, reason)

      {:EXIT, from, reason} ->
        exited(state, from, reason)

      {:conversation_session, pid} ->
        await(%{state | session: pid})

      {:conversation_model_process, pid} ->
        await(%{state | model_processes: MapSet.put(state.model_processes, pid)})

      :heartbeat ->
        heartbeat_tick(state)

      :cancel ->
        await(stop_session(state))

      :deadline ->
        await(%{stop_session(state) | timed_out: true})
    end
  end

  # Atlas.TaskSupervisor starts after Oban, so during a deploy it shuts down
  # first while the repository and Oban are still available. The session is
  # linked to the run task, so a stop this worker initiated (cancel, deadline,
  # lost access) can also take the task down.
  defp task_down(state, reason) do
    cond do
      state.stopping and state.timed_out -> {:error, :timeout}
      state.stopping -> {:error, :stopped}
      shutdown?(reason) or reason == :killed -> checkpoint_after(stop_session(state))
      true -> crashed(stop_session(state))
    end
  end

  # Exits from processes this worker owns (the run task, the session, model
  # loops it killed) are expected. A shutdown from anywhere else is a deploy.
  defp exited(state, from, reason) do
    cond do
      owned?(state, from) -> await(state)
      shutdown?(reason) -> checkpoint_after(abandon(state))
      true -> await(state)
    end
  end

  defp heartbeat_tick(state) do
    attempted_at = System.monotonic_time(:millisecond)

    case renew(state, attempted_at) do
      :ok ->
        Process.send_after(self(), :heartbeat, Keyword.get(state.opts, :heartbeat_interval, @heartbeat_interval))
        await(%{state | renewed_at: attempted_at})

      :cancel ->
        await(stop_session(state))

      :stale ->
        abandon(state)
        :stale
    end
  end

  # Self-fencing: a worker that has not renewed within the fence window stops
  # without touching the database, before its lease can be taken over.
  defp renew(state, attempted_at) do
    if attempted_at - state.renewed_at > Keyword.get(state.opts, :self_fence_after, @self_fence_after),
      do: :stale,
      else: heartbeat(state.run)
  end

  defp shutdown?(reason), do: reason == :shutdown or match?({:shutdown, _}, reason)

  defp owned?(state, pid), do: pid in [state.task.pid, state.session] or MapSet.member?(state.model_processes, pid)

  # Renews this attempt's heartbeat. `:stale` means another attempt owns the
  # run; `:cancel` means it was cancelled or the acting user lost access.
  defp heartbeat(%Run{id: run_id, resume_count: attempt}) do
    {renewed, _} =
      Repo.update_all(
        from(run in Run,
          where: run.id == ^run_id and run.status == "running" and run.resume_count == ^attempt,
          update: [set: [heartbeat_at: fragment("clock_timestamp()")]]
        ),
        []
      )

    with 1 <- renewed,
         %Run{cancel_requested_at: nil} = run <- Repo.get(Run, run_id),
         %Conversation{status: "active"} = conversation <- Repo.get(Conversation, run.conversation_id),
         %User{} = acting_user <- run.acting_user_id && Repo.get(User, run.acting_user_id),
         true <- Access.can_read?(conversation, acting_user) do
      :ok
    else
      0 ->
        :stale

      _ ->
        Repo.update_all(from(run in Run, where: run.id == ^run_id and is_nil(run.cancel_requested_at)),
          set: [cancel_requested_at: DateTime.utc_now()]
        )

        :cancel
    end
  end

  # Kills the model loop and the session. Condukt runs the loop in an unlinked
  # process, which `ModelFence` reports on every model request; killing it ends
  # any model or tool call in flight, and Condukt.run in the task then returns a
  # session-exit error.
  defp stop_session(state) do
    Enum.each(state.model_processes, &Process.exit(&1, :kill))
    if is_pid(state.session), do: Process.exit(state.session, :kill)
    %{state | stopping: true}
  end

  defp abandon(state) do
    stop_session(state)
    Process.demonitor(state.task.ref, [:flush])
    Process.exit(state.task.pid, :kill)
    state
  end

  defp checkpoint_after(_state), do: :checkpoint
  defp crashed(_state), do: {:error, :crashed}

  defp invoke(run, parent, opts) do
    conversation = Repo.get!(Conversation, run.conversation_id)
    audience = Access.audience(conversation)

    client_opts =
      opts
      |> Keyword.get_lazy(:client_opts, fn -> Runner.profile_client_opts(:conversations, timeout: @max_duration) end)
      |> ModelFence.wrap(run, parent)

    {prompt, store_opts} =
      case Checkpoints.load(run) do
        {:ok, snapshot} -> {resume_prompt(), [session_store: {Checkpoints.Store, snapshot: snapshot}]}
        :none -> {Agent.transcript(transcript_messages(conversation, run), run.id), []}
      end

    session_opts =
      client_opts ++
        store_opts ++
        [
          tools: Tools.build(run),
          system_prompt: Agent.system_prompt(conversation, audience),
          load_project_instructions: false,
          max_tokens: @max_tokens
        ]

    # The audited session row stores a label instead of the transcript, and the
    # telemetry handler keeps only tool names and timings for this agent, so
    # conversation content never reaches /admin/sessions.
    Sessions.with_session(Agent, "conversation_run:#{run.id}", [id: run.session_id], fn condukt_opts ->
      result =
        Condukt.Session.with_transient(Agent, session_opts ++ condukt_opts, fn pid ->
          # Condukt starts sessions unlinked; the session does not trap exits.
          Process.link(pid)
          send(parent, {:conversation_session, pid})
          Condukt.run(pid, prompt, max_turns: @max_turns, timeout: @max_duration)
        end)

      Process.put({__MODULE__, :result}, result)

      # Provider errors can echo request content, so the audited session only
      # records the bounded category.
      case result do
        {:ok, _text} -> {:ok, %{"conversation_run_id" => run.id}}
        {:error, reason} -> {:error, error_category(reason)}
      end
    end)

    Process.get({__MODULE__, :result})
  end

  defp resume_prompt do
    "You were interrupted by a server restart while answering. Continue from where you left off and answer the request above."
  end

  # The most recent messages, plus every message addressed to the assistant
  # since this run's trigger, so a run with many tool calls never loses the
  # request it is answering.
  defp transcript_messages(conversation, run) do
    recent =
      Message
      |> where([message], message.conversation_id == ^conversation.id)
      |> order_by(desc: :position)
      |> limit(@transcript_messages)
      |> Repo.all()

    requests =
      Repo.all(
        from message in Message,
          where:
            message.conversation_id == ^conversation.id and message.address_agent == true and
              message.position >= ^run.trigger_seq
      )

    (recent ++ requests)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.position)
  end

  ## Completion

  @doc """
  Finishes `attempt`. The reply is written only while the attempt still owns
  the run, the run was not cancelled, the conversation is active, and the
  acting user can still read it. Readers are recomputed under the conversation
  lock from the ratcheted scopes, so the reply reaches only people who hold
  every scope this run's tools required. A superseded attempt writes nothing.
  """
  def complete(run_id, attempt, result) do
    outcome =
      with_attempt(run_id, attempt, fn conversation, run ->
        acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)

        cond do
          not is_nil(run.cancel_requested_at) ->
            finalize!(run, "cancelled", nil, "Stopped. The assistant's reply was discarded.", conversation)

          conversation.status != "active" or not Access.can_read?(conversation, acting_user) ->
            finalize!(
              run,
              "cancelled",
              "access_changed",
              "Access to this conversation changed, so the assistant's reply was discarded.",
              conversation
            )

          true ->
            finish!(run, conversation, result)
        end
      end)

    case outcome do
      {:ok, _} ->
        conversation_id = conversation_id(run_id)
        Conversations.notify_changed(conversation_id)
        follow_up(conversation_id)
        :ok

      {:error, :stale} ->
        :stale
    end
  end

  defp finish!(run, conversation, {:ok, text}) when is_binary(text) and text != "" do
    Conversations.append!(conversation, %{
      kind: "agent",
      run_id: run.id,
      body: Rendering.truncate(text, @reply_limit),
      author_name: Conversations.agent_name()
    })

    finalize!(run, "succeeded", nil, nil, conversation)
  end

  defp finish!(run, conversation, {:ok, _empty}) do
    finalize!(run, "failed", "empty_response", "The assistant did not reply. Try again.", conversation)
  end

  defp finish!(run, conversation, {:error, reason}) do
    category = error_category(reason)
    Logger.warning("conversation run failed: #{category}")
    finalize!(run, "failed", category, failure_message(category), conversation)
  end

  defp finish!(run, conversation, _other), do: finish!(run, conversation, {:error, :invalid_result})

  # Terminal statuses drop the cached snapshot; the log is the durable record.
  defp finalize!(run, status, category, notice, conversation) do
    run
    |> Ecto.Changeset.change(
      status: status,
      error_category: category,
      finished_at: DateTime.utc_now(),
      checkpoint: nil,
      checkpoint_turn: nil
    )
    |> Repo.update!()

    Repo.update_all(from(message in Message, where: message.run_id == ^run.id), set: [tool_result: nil])
    if notice, do: Conversations.append!(conversation, %{kind: "system", run_id: run.id, body: notice})
    :ok
  end

  ## Checkpoints

  @doc """
  Checkpoints `attempt` so another replica resumes the run. With
  `only_if_expired: true` (the sweeper) it acts only if the lease is still
  expired by the database clock under the locks, so a renewal that landed after
  the sweeper's scan wins. Returns `:requeued`, `:finalized`, `:fresh`, or
  `:stale`.
  """
  def checkpoint(run_id, attempt, opts \\ []) do
    only_if_expired? = Keyword.get(opts, :only_if_expired, false)

    run_id
    |> with_attempt(attempt, &checkpoint_locked(&1, &2, only_if_expired?))
    |> case do
      {:ok, :fresh} ->
        :fresh

      {:ok, :finalized} ->
        conversation_id = conversation_id(run_id)
        Conversations.notify_changed(conversation_id)
        follow_up(conversation_id)
        :finalized

      {:ok, result} ->
        Conversations.notify_changed(conversation_id(run_id))
        result

      {:error, :stale} ->
        :stale
    end
  end

  defp checkpoint_locked(conversation, run, only_if_expired?) do
    if only_if_expired? and not lease_expired?(run.id) do
      :fresh
    else
      close_running_tools!(run)

      cond do
        not is_nil(run.cancel_requested_at) ->
          finalize!(run, "cancelled", nil, "Stopped. The assistant's reply was discarded.", conversation)
          :finalized

        run.resume_count >= @max_resumes ->
          finalize!(
            run,
            "interrupted",
            "interrupted",
            "The assistant was interrupted. Ask again to retry.",
            conversation
          )

          :finalized

        true ->
          requeue!(run)
      end
    end
  end

  defp lease_expired?(run_id) do
    Repo.exists?(
      from run in Run,
        where:
          run.id == ^run_id and
            (is_nil(run.heartbeat_at) or
               run.heartbeat_at < fragment("clock_timestamp() - make_interval(secs => ?)", ^@stale_after_seconds))
    )
  end

  defp requeue!(run) do
    resume = run.resume_count + 1

    run
    |> Ecto.Changeset.change(status: "queued", resume_count: resume, heartbeat_at: nil, session_id: nil)
    |> Repo.update!()

    {:ok, _job} = %{"run_id" => run.id, "resume" => resume} |> RunConversation.new() |> Oban.insert()
    :requeued
  end

  defp close_running_tools!(run) do
    Message
    |> where([message], message.run_id == ^run.id and message.tool_status == "running")
    |> Repo.all()
    |> Enum.each(&Conversations.touch!(&1, %{tool_status: "cancelled", tool_output: "Interrupted by a restart."}))
  end

  @doc "Checkpoints running runs whose lease expired, for example after a replica was lost."
  def resume_stale do
    Run
    |> where(
      [run],
      run.status == "running" and
        run.heartbeat_at < fragment("clock_timestamp() - make_interval(secs => ?)", ^@stale_after_seconds)
    )
    |> select([run], {run.id, run.resume_count})
    |> Repo.all()
    |> Enum.each(fn {run_id, attempt} -> checkpoint(run_id, attempt, only_if_expired: true) end)
  end

  @doc """
  Re-enqueues queued runs that have had no pending job for a minute, for
  example when a job was discarded or lost. Duplicate jobs are harmless: only
  one can move a queued run to running.
  """
  def recover_queued do
    pending_jobs =
      from job in Oban.Job,
        where:
          job.worker == "Atlas.Conversations.Workers.RunConversation" and
            job.state in ["available", "scheduled", "executing", "retryable", "suspended"] and
            fragment("?->>'run_id'", job.args) == type(parent_as(:run).id, :string)

    from(run in Run, as: :run)
    |> where([run], run.status == "queued" and run.updated_at < fragment("now() - interval '60 seconds'"))
    |> where([run], not exists(pending_jobs))
    |> select([run], {run.id, run.resume_count})
    |> Repo.all()
    |> Enum.each(fn {run_id, resume} ->
      %{"run_id" => run_id, "resume" => resume} |> RunConversation.new() |> Oban.insert()
    end)
  end

  ## Follow-ups

  @doc """
  Starts a follow-up run when messages addressed to the assistant arrived after
  the last run's trigger.
  """
  def follow_up(nil), do: :ok

  def follow_up(conversation_id) do
    Repo.transaction(fn ->
      conversation = Conversations.lock!(conversation_id)

      with nil <- Conversations.active_run(conversation),
           true <- conversation.status == "active",
           true <- Conversations.agent_configured?(),
           %Message{} = pending <- pending_message(conversation),
           %User{} = acting_user <- acting_user_for(conversation, pending),
           true <- Access.can_read?(conversation, acting_user) do
        initiator = if pending.kind == "human", do: acting_user
        Conversations.start_run!(conversation, pending.position, initiator, acting_user)
      else
        _ -> :none
      end
    end)
    |> case do
      {:ok, %Run{conversation_id: id}} -> Conversations.notify_changed(id)
      _ -> :ok
    end
  end

  defp pending_message(conversation) do
    last_trigger =
      Repo.one(from run in Run, where: run.conversation_id == ^conversation.id, select: max(run.trigger_seq)) || 0

    Repo.one(
      from message in Message,
        where:
          message.conversation_id == ^conversation.id and message.address_agent == true and
            message.position > ^last_trigger,
        order_by: [desc: message.position],
        limit: 1
    )
  end

  # Human messages act as their author; signal notices act as the owner.
  defp acting_user_for(_conversation, %Message{kind: "human", author_id: id}) when is_binary(id), do: Repo.get(User, id)
  defp acting_user_for(%Conversation{owner_id: id}, _message) when is_binary(id), do: Repo.get(User, id)
  defp acting_user_for(_conversation, _message), do: nil

  defp conversation_id(run_id) do
    Repo.one(from run in Run, where: run.id == ^run_id, select: run.conversation_id)
  end

  ## Errors

  defp error_category(:timeout), do: "timeout"
  defp error_category(:crashed), do: "crashed"
  defp error_category({:session_exit, _}), do: "session_exit"
  defp error_category(%{status: status}) when status in [401, 403], do: "provider_auth"
  defp error_category(%{status: 402}), do: "provider_billing"
  defp error_category(%{status: 429}), do: "provider_rate_limited"
  defp error_category(%{status: 503}), do: "not_configured"
  defp error_category(%{status: status}) when is_integer(status) and status >= 500, do: "provider_unavailable"
  defp error_category(_reason), do: "failed"

  defp failure_message("not_configured"),
    do:
      "The assistant is not configured on this Atlas server. An administrator can assign an inference profile to conversations."

  defp failure_message("timeout"), do: "The assistant took too long and was stopped. Try a narrower question."
  defp failure_message(_category), do: "The assistant could not reply. Try again in a moment."
end
