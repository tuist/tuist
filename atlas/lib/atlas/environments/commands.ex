defmodule Atlas.Environments.Commands do
  @moduledoc """
  The durable, at-most-once executor dispatch boundary.

  Delivery adapters poll or subscribe to the same ledger, then claim, report
  progress and settle results. They never execute tools in the model process.
  Commands stay bound to the selected environment/project and configuration
  version. A claim is never reassigned, including to another provider.
  """
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Environments
  alias Atlas.Environments.Command
  alias Atlas.Environments.Environment
  alias Atlas.Environments.ProviderWorker
  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.EnvironmentTools
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Rendering
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Thread
  alias Atlas.Repo
  alias Atlas.Users.User

  @unknown "The environment command outcome is unknown. It will not be retried automatically."
  @unavailable "The personal environment is unavailable."
  @active ~w(queued claimed)
  @terminal ~w(environment_terminal bash)
  @mutating ~w(environment_terminal bash edit write)

  def unknown, do: @unknown

  # Called inside Tools' thread/run attempt transaction. message_id is a
  # unique ledger key, not an attempt key, and survives deployments.
  def reserve!(thread, run, message, args) do
    authorize!(thread, run)

    case Repo.get_by(Command, message_id: message.id) do
      %Command{} = command ->
        command

      nil ->
        reserve_new!(thread, run, message, args)
    end
  end

  defp reserve_new!(thread, run, message, args) do
    if EnvironmentTools.mutating?(message.tool_name) and mutation_pending?(thread.id),
      do: Repo.rollback(:command_outcome_unknown)

    environment = Environments.owned_enabled!(thread.owner_id, run.environment_id, run.project_id)
    if not Environments.online?(environment), do: Repo.rollback(:environment_offline)

    project = Enum.find(environment.projects, &(&1["id"] == run.project_id))
    ensure_tool!(environment, project, message.tool_name)

    arguments = Map.put(args, "project_id", run.project_id)

    arguments =
      if EnvironmentTools.coding?(message.tool_name),
        do: Map.merge(arguments, %{"thread_id" => thread.id, "title" => thread.title}),
        else: arguments

    id = Ecto.UUID.generate()
    terminal = EnvironmentTools.terminal?(message.tool_name)
    timeout = execution_timeout(message.tool_name, environment)

    digest = digest({id, environment.id, environment.version, run.project_id, message.tool_name, arguments, timeout})

    command =
      Repo.insert!(%Command{
        id: id,
        environment_id: environment.id,
        environment_version: environment.version,
        thread_id: thread.id,
        run_id: run.id,
        message_id: message.id,
        tool: message.tool_name,
        arguments: JSON.encode!(arguments),
        status: "queued",
        environment_name: environment.name,
        project_id: run.project_id,
        project_name: project["name"],
        execution_timeout_seconds: timeout,
        digest: digest,
        expires_at: DateTime.add(DateTime.utc_now(), if(terminal, do: 600, else: 60), :second)
      })

    thread |> Ecto.Changeset.change(personal_environment_dispatched: true) |> Repo.update!()

    if environment.provider != "native" do
      %{environment_id: environment.id, command_id: command.id} |> ProviderWorker.new() |> Oban.insert!()
    end

    audit(command, "queued", run.acting_user_id, "worker")
    command
  end

  defp ensure_tool!(environment, project, tool) do
    if (EnvironmentTools.mutating?(tool) or EnvironmentTools.coding?(tool)) and not environment.terminal,
      do: Repo.rollback(:environment_terminal_disabled)

    if EnvironmentTools.coding?(tool) and (environment.provider != "native" or project["coding"] != true),
      do: Repo.rollback(:environment_project_unavailable)
  end

  defp execution_timeout(tool, %{provider: "native"}) when tool in @terminal, do: 1_800
  defp execution_timeout(tool, _environment) when tool in @terminal, do: 600
  defp execution_timeout(_tool, _environment), do: 60

  defp mutation_pending?(thread_id) do
    Repo.exists?(
      from c in Command,
        where:
          c.thread_id == ^thread_id and c.tool in ^@mutating and
            c.status in ["queued", "claimed", "unknown"]
    )
  end

  def queued(user, client_id, environment_id) do
    case Environments.uuid(environment_id) do
      {:ok, environment_id} ->
        Repo.transaction(fn ->
          environment = Environments.bound!(user, client_id, environment_id)
          if not Environments.online?(environment), do: Repo.rollback(:environment_disabled)

          commands = Repo.all(queued_query(environment, user))

          # Private history access can still be revoked by loss of ratcheted scopes.
          commands |> Enum.filter(&Access.can_read?(Repo.get!(Thread, &1.thread_id), user)) |> Enum.map(&envelope/1)
        end)

      _ ->
        {:error, :invalid_params}
    end
  end

  defp queued_query(environment, user) do
    from c in dispatchable_query(environment),
      join: r in Run,
      on: r.id == c.run_id,
      join: t in Thread,
      on: t.id == c.thread_id,
      where: r.status == "running" or (c.tool in ^@terminal and r.status in ["queued", "succeeded"]),
      where: is_nil(r.cancel_requested_at) and t.status == "active" and t.kind == "private" and t.owner_id == ^user.id,
      order_by: [asc: c.inserted_at],
      limit: 8
  end

  defp dispatchable_query(environment) do
    from c in Command,
      where:
        c.environment_id == ^environment.id and c.environment_version == ^environment.version and
          c.status == "queued" and c.expires_at > ^DateTime.utc_now(),
      where: not c.cancel_requested
  end

  def claim(user, client_id, environment_id, command_id, params) do
    if valid_claim?(params) do
      bound_command(user, client_id, environment_id, command_id, fn environment, command, thread, run ->
        ensure_live!(environment, command, thread, run)
        if command.status != "queued", do: Repo.rollback(:command_claimed_or_settled)
        if not Environments.online?(environment), do: Repo.rollback(:environment_offline)
        if params["digest"] != command.digest, do: Repo.rollback(:command_digest_mismatch)

        deadline = DateTime.add(DateTime.utc_now(), command.execution_timeout_seconds, :second)

        command =
          command
          |> Ecto.Changeset.change(
            status: "claimed",
            claim_token: Ecto.UUID.generate(),
            execution_deadline: deadline,
            result_deadline:
              if(command.tool in @terminal,
                do: DateTime.add(deadline, 300, :second),
                else: command.expires_at
              )
          )
          |> Repo.update!()

        audit(command, "claimed", user.id, "api")
        %{command: Map.put(envelope(command), :claim_token, command.claim_token)}
      end)
    else
      {:error, :invalid_params}
    end
  end

  defp valid_claim?(params) do
    Environments.exact_keys?(params, ~w(digest)) and valid_digest?(params["digest"])
  end

  defp valid_digest?(value), do: is_binary(value) and byte_size(value) == 64

  def cancel(user, thread_id, command_id, params) do
    if Environments.exact_keys?(params, ~w(digest)) and valid_digest?(params["digest"]) do
      owner_command(user, thread_id, command_id, fn _environment, command, _thread, _run ->
        check_digest!(command, params)

        if command.status in @active do
          command
          |> Ecto.Changeset.change(
            cancel_requested: true,
            status: if(command.status == "claimed", do: "claimed", else: "cancelled")
          )
          |> Repo.update!()

          audit(command, "cancel_requested", user.id, "api")
        end

        %{received: true}
      end)
    else
      {:error, :invalid_params}
    end
  end

  defp check_digest!(command, params) do
    if command.digest != params["digest"], do: Repo.rollback(:command_digest_mismatch)
  end

  defp owner_command(user, thread_id, command_id, fun) do
    with {:ok, thread_id} <- Environments.uuid(thread_id),
         {:ok, command_id} <- Environments.uuid(command_id),
         %Command{tool: tool} = initial when tool in @terminal <-
           Repo.get_by(Command, id: command_id, thread_id: thread_id) do
      Repo.transaction(fn ->
        thread = owner_thread!(user, thread_id)
        run = Repo.one!(from r in Run, where: r.id == ^initial.run_id, lock: "FOR UPDATE")
        environment = Repo.one(from e in Environment, where: e.id == ^initial.environment_id, lock: "FOR UPDATE")
        command = Repo.one!(from c in Command, where: c.id == ^command_id, lock: "FOR UPDATE")
        fun.(environment, command, thread, run)
      end)
      |> changed(thread_id)
    else
      _ -> {:error, :not_found}
    end
  end

  defp owner_thread!(user, id) do
    thread = Repo.one(from t in Thread, where: t.id == ^id, lock: "FOR UPDATE")

    if is_nil(thread) or thread.kind != "private" or thread.owner_id != user.id or not Access.can_read?(thread, user),
      do: Repo.rollback(:not_found)

    thread
  end

  def list(user, thread_id) do
    case Environments.uuid(thread_id) do
      {:ok, thread_id} ->
        Repo.transaction(fn ->
          owner_thread!(user, thread_id)

          commands =
            Repo.all(
              from c in Command,
                where: c.thread_id == ^thread_id and c.tool in ^@terminal,
                order_by: [desc: fragment("? = ANY(?)", c.status, ^@active), desc: c.inserted_at, desc: c.id],
                limit: 32
            )

          %{commands: bounded_entries(commands)}
        end)

      _ ->
        {:error, :not_found}
    end
  end

  defp bounded_entries(commands) do
    {entries, _output_budget, _wire_budget} =
      Enum.reduce_while(commands, {[], 262_144, 950_000}, fn command, {entries, output_budget, wire_budget} ->
        entry = activity(command)
        entry = %{entry | output: tail(entry.output, min(49_152, output_budget))}
        base_bytes = byte_size(JSON.encode!(%{entry | output: ""})) + 1

        if base_bytes > wire_budget do
          {:halt, {entries, output_budget, wire_budget}}
        else
          # JSON control-character escaping can use six bytes per input byte.
          # Preserve exact commands, trimming tails/older settled rows instead.
          entry =
            if byte_size(JSON.encode!(entry)) + 1 > wire_budget,
              do: %{entry | output: tail(entry.output, div(wire_budget - base_bytes, 6))},
              else: entry

          bytes = byte_size(JSON.encode!(entry)) + 1
          {:cont, {[entry | entries], output_budget - byte_size(entry.output), wire_budget - bytes}}
        end
      end)

    Enum.reverse(entries)
  end

  defp activity(command) do
    result = command.result && JSON.decode!(command.result)

    %{
      id: command.id,
      message_id: command.message_id,
      environment_id: command.environment_id,
      environment_name: String.slice(command.environment_name || "Environment", 0, 120),
      project_id: command.project_id || JSON.decode!(command.arguments)["project_id"],
      project_name: String.slice(command.project_name || "Project", 0, 120),
      digest: command.digest,
      command: JSON.decode!(command.arguments)["command"],
      status: command.status,
      output: if(result, do: result["output"], else: command.progress_output || ""),
      success: if(result, do: result["success"]),
      cancel_requested: command.cancel_requested,
      progress_sequence: command.progress_sequence,
      execution_timeout_seconds: command.execution_timeout_seconds
    }
  end

  defp tail(text, limit) when byte_size(text) <= limit, do: text
  defp tail(text, limit), do: text |> binary_part(byte_size(text) - limit, limit) |> valid_tail()
  defp valid_tail(<<byte, rest::binary>>) when byte in 128..191, do: valid_tail(rest)
  defp valid_tail(text), do: text

  def progress(user, client_id, environment_id, command_id, params) do
    with true <- Environments.exact_keys?(params, ~w(claim_token sequence output)),
         {:ok, token} <- Environments.uuid(params["claim_token"]),
         true <- valid_progress?(params) do
      bound_command(user, client_id, environment_id, command_id, fn environment, command, thread, run ->
        ensure_source!(thread, run, command)
        ensure_configuration!(environment, command)
        if command.claim_token != token, do: Repo.rollback(:command_claim_mismatch)
        if command.status != "claimed", do: Repo.rollback(:command_claimed_or_settled)
        if expired?(command.execution_deadline), do: Repo.rollback(:command_expired)
        persist_progress!(command, params["sequence"], params["output"])
        %{received: true, cancel_requested: command.cancel_requested}
      end)
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp valid_progress?(params) do
    is_integer(params["sequence"]) and params["sequence"] in 1..9_223_372_036_854_775_807 and
      is_binary(params["output"]) and String.valid?(params["output"]) and byte_size(params["output"]) <= 49_152
  end

  defp persist_progress!(command, sequence, output) do
    cond do
      sequence > command.progress_sequence ->
        command |> Ecto.Changeset.change(progress_sequence: sequence, progress_output: output) |> Repo.update!()

      sequence == command.progress_sequence and command.progress_output != output ->
        Repo.rollback(:command_progress_conflict)

      true ->
        :ok
    end
  end

  def complete(user, client_id, environment_id, command_id, params) do
    with true <- Environments.exact_keys?(params, ~w(claim_token success output)),
         {:ok, token} <- Environments.uuid(params["claim_token"]),
         true <-
           is_boolean(params["success"]) and is_binary(params["output"]) and
             byte_size(params["output"]) <= 65_536 and String.valid?(params["output"]) do
      bound_command(user, client_id, environment_id, command_id, fn environment, command, thread, run ->
        if is_nil(command.claim_token) or command.claim_token != token, do: Repo.rollback(:command_claim_mismatch)
        payload = Map.take(params, ~w(success output))
        store_result!(environment, command, thread, run, payload, user.id)
        %{received: true}
      end)
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp store_result!(_environment, %Command{status: "settled"} = command, _thread, _run, payload, _user_id) do
    if JSON.decode!(command.result) != payload, do: Repo.rollback(:command_result_conflict)
  end

  defp store_result!(environment, command, thread, run, payload, user_id) do
    ensure_source!(thread, run, command)
    ensure_configuration!(environment, command)
    deadline = if command.tool in @terminal, do: command.result_deadline, else: command.expires_at
    if expired?(deadline), do: Repo.rollback(:command_expired)
    if command.status != "claimed", do: Repo.rollback(:command_claimed_or_settled)
    command = command |> Ecto.Changeset.change(status: "settled", result: JSON.encode!(payload)) |> Repo.update!()
    if command.tool in @terminal, do: completed_terminal!(command, thread, payload)
    audit(command, "settled", user_id, "api")
  end

  defp completed_terminal!(command, thread, payload) do
    output = terminal_evidence(command, payload)
    message = Repo.get!(Message, command.message_id)

    Orbit.touch!(message, %{
      device_output: output,
      tool_output: "",
      tool_status: if(payload["success"], do: "succeeded", else: "failed")
    })

    # No output in the plaintext notice or job args. The encrypted evidence on
    # this recent notice also reaches a fresh server-only/other-Mac run, even
    # when the original card has fallen outside the recent transcript window.
    notice =
      Orbit.append!(thread, %{
        kind: "system",
        body: "A personal terminal job returned a confirmed result.",
        device_output: output,
        address_agent: not command.cancel_requested
      })

    command |> Ecto.Changeset.change(continuation_message_id: notice.id) |> Repo.update!()
    if not command.cancel_requested, do: Runs.follow_up(thread.id)
  end

  # Completion may race the originating model's ticket settlement. A confirmed
  # result must win over that earlier reservation rendering on the original card.
  def completed_card_attrs(%Message{tool_name: tool, id: id}) when tool in @terminal do
    case Repo.get_by(Command, message_id: id, status: "settled") do
      %Command{result: result} = command ->
        payload = JSON.decode!(result)

        %{
          device_output: terminal_evidence(command, payload),
          tool_status: if(payload["success"], do: "succeeded", else: "failed")
        }

      _ ->
        %{}
    end
  end

  def completed_card_attrs(_message), do: %{}

  defp terminal_evidence(command, payload) do
    # Identity and outcome must precede any long/truncated device output.
    Rendering.truncate(
      "Terminal job #{command.id}; success: #{payload["success"]}\n" <> Rendering.output(payload["output"]),
      4_000
    )
  end

  # Generic human/signal triggers are unaffected. Automatic terminal
  # continuations recheck their frozen source, not the thread's new selection.
  def continuation_allowed?(thread, trigger_seq) do
    command =
      Repo.one(
        from c in Command,
          join: m in Message,
          on: m.id == c.continuation_message_id,
          where: c.thread_id == ^thread.id and m.position == ^trigger_seq
      )

    case command do
      nil ->
        true

      command ->
        run = Repo.get(Run, command.run_id)
        environment = Repo.get(Environment, command.environment_id)

        command.status == "settled" and not command.cancel_requested and not is_nil(run) and
          source_live?(thread, run, command) and current_configuration?(environment, command)
    end
  end

  defp bound_command(user, client_id, environment_id, command_id, fun) do
    with {:ok, environment_id} <- Environments.uuid(environment_id),
         {:ok, command_id} <- Environments.uuid(command_id),
         %Command{} = initial <- Repo.get_by(Command, id: command_id, environment_id: environment_id) do
      Repo.transaction(fn ->
        # Same lock order as every Orbit callback. No transaction waits on
        # a thread while holding the environment row.
        thread = Orbit.lock!(initial.thread_id)
        run = Repo.one!(from r in Run, where: r.id == ^initial.run_id, lock: "FOR UPDATE")
        environment = Environments.bound!(user, client_id, environment_id)
        command = Repo.one!(from c in Command, where: c.id == ^command_id, lock: "FOR UPDATE")
        fun.(environment, command, thread, run)
      end)
      |> changed(initial.thread_id)
    else
      _ -> {:error, :not_found}
    end
  end

  defp ensure_live!(environment, command, thread, run) do
    ensure_source!(thread, run, command)
    ensure_configuration!(environment, command)
    if command.cancel_requested, do: Repo.rollback(:command_cancelled)
    if expired?(command.expires_at), do: Repo.rollback(:command_expired)
  end

  defp ensure_configuration!(environment, command) do
    if not current_configuration?(environment, command), do: Repo.rollback(:environment_disabled)

    if command.tool in @mutating and not environment.terminal,
      do: Repo.rollback(:environment_terminal_disabled)
  end

  defp ensure_source!(thread, run, command) do
    if not source_live?(thread, run, command), do: Repo.rollback(:command_cancelled)
  end

  defp source_live?(thread, run, command) do
    user = run.acting_user_id && Repo.get(User, run.acting_user_id)

    statuses =
      if command.tool in @terminal, do: ["succeeded" | Run.active_statuses()], else: Run.active_statuses()

    private_run?(thread, run) and thread.status == "active" and run.status in statuses and
      is_nil(run.cancel_requested_at) and not is_nil(user) and Access.can_read?(thread, user)
  end

  defp authorize!(thread, run) do
    user = run.acting_user_id && Repo.get(User, run.acting_user_id)

    if not private_run?(thread, run) or
         thread.status != "active" or run.status not in Run.active_statuses() or
         not is_nil(run.cancel_requested_at) or
         is_nil(user) or not Access.can_read?(thread, user), do: Repo.rollback(:command_cancelled)
  end

  defp private_run?(thread, run) do
    thread.kind == "private" and thread.owner_id == run.acting_user_id and
      is_binary(run.environment_id) and is_binary(run.project_id)
  end

  # Resume only the wait for the original command. Neither disconnect nor
  # attempt transfer can turn a claimed command back into a queued command.
  def await(run_id, attempt, command_id) do
    deadline = System.monotonic_time(:millisecond) + 61_000
    await_until(run_id, attempt, command_id, deadline)
  end

  defp await_until(run_id, attempt, command_id, deadline) do
    case outcome(run_id, attempt, command_id) do
      {:ok, :waiting} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, @unknown}
        else
          receive do
          after
            250 -> await_until(run_id, attempt, command_id, deadline)
          end
        end

      {:ok, outcome} ->
        outcome

      {:error, _reason} ->
        {:error, @unavailable}
    end
  end

  def outcome(run_id, attempt, command_id) do
    Runs.with_attempt(run_id, attempt, fn thread, run ->
      authorize!(thread, run)
      command = Repo.one!(from c in Command, where: c.id == ^command_id and c.run_id == ^run_id, lock: "FOR UPDATE")

      case command do
        %Command{status: "settled", result: result} ->
          stored_outcome(result)

        %Command{status: status} when status in ["unknown", "expired", "cancelled"] ->
          {:error, @unknown}

        _ ->
          environment = Repo.get(Environment, command.environment_id)

          if DateTime.compare(command.expires_at, DateTime.utc_now()) != :gt or
               not current_configuration?(environment, command) do
            command
            |> Ecto.Changeset.change(status: if(command.status == "claimed", do: "unknown", else: "expired"))
            |> Repo.update!()

            {:error, @unknown}
          else
            :waiting
          end
      end
    end)
  end

  defp current_configuration?(nil, _command), do: false

  defp current_configuration?(environment, command),
    do: environment.enabled and environment.version == command.environment_version

  defp stored_outcome(result) do
    case JSON.decode!(result) do
      %{"success" => true, "output" => output} -> {:ok, output}
      %{"output" => output} -> {:error, output}
    end
  end

  def envelope(command) do
    %{
      id: command.id,
      tool: command.tool,
      arguments: JSON.decode!(command.arguments),
      execution_timeout_seconds: command.execution_timeout_seconds,
      digest: command.digest
    }
  end

  # Returned promptly to the model, not an execution result.
  def ticket(command) do
    case command.status do
      "settled" ->
        stored_outcome(command.result)

      status when status in ["unknown", "expired", "cancelled"] ->
        {:error, @unknown}

      _ ->
        {:ok,
         %{
           command_id: command.id,
           status: command.status,
           notice:
             "Durable terminal job queued on the selected execution environment. Do not poll, retry or reserve another command; its confirmed result will continue this conversation."
         }}
    end
  end

  defp expired?(nil), do: true
  defp expired?(deadline), do: DateTime.compare(deadline, DateTime.utc_now()) != :gt

  defp changed({:ok, _} = result, thread_id) do
    Orbit.notify_changed(thread_id)
    result
  end

  defp changed(result, _thread_id), do: result

  # Called under the existing thread/run lock. Succeeded model runs detach
  # their terminal jobs; every other final outcome permanently fences them.
  def cancel_run!(run_id) do
    cancel_scope!(from(c in Command, where: c.run_id == ^run_id))
  end

  def archive!(thread_id) do
    cancel_scope!(from(c in Command, where: c.thread_id == ^thread_id))

    notices = from c in Command, where: c.thread_id == ^thread_id, select: c.continuation_message_id
    Repo.update_all(from(m in Message, where: m.id in subquery(notices)), set: [address_agent: false])
  end

  defp cancel_scope!(query) do
    Repo.update_all(where(query, [c], c.status == "claimed"),
      set: [cancel_requested: true, status: "unknown"]
    )

    Repo.update_all(where(query, [c], c.status == "queued"),
      set: [cancel_requested: true, status: "cancelled"]
    )
  end

  # Expiry and revoked/configuration-changed sources reconcile independently
  # of model sessions. Bounded scan with a rotating updated_at cursor prevents
  # online healthy jobs starving later commands. No command is ever requeued.
  def sweep do
    Repo.all(from c in Command, where: c.status in ^@active, order_by: [asc: c.updated_at, asc: c.id], limit: 128)
    |> Enum.each(fn initial ->
      Repo.transaction(fn -> sweep_locked!(initial) end)
      |> changed(initial.thread_id)
    end)

    recover_continuations()
  end

  # A replica can die after the active run commits its final state but before
  # its ordinary follow_up call. The command-owned notice is the durable outbox
  # for that gap, not just for a lost Oban job after a follow-up already exists.
  defp recover_continuations do
    Repo.all(
      from c in Command,
        join: m in Message,
        on: m.id == c.continuation_message_id,
        left_join: r in Run,
        on: r.thread_id == c.thread_id and r.trigger_seq >= m.position,
        where: c.status == "settled" and not c.cancel_requested and m.address_agent == true and is_nil(r.id),
        order_by: [asc: c.updated_at, asc: c.id],
        limit: 128
    )
    |> Enum.each(fn initial ->
      Repo.transaction(fn -> recover_continuation_locked!(initial) end)
      |> changed(initial.thread_id)
    end)
  end

  defp recover_continuation_locked!(initial) do
    thread = Orbit.lock!(initial.thread_id)
    run = Repo.one!(from r in Run, where: r.id == ^initial.run_id, lock: "FOR UPDATE")
    environment = Repo.one(from e in Environment, where: e.id == ^initial.environment_id, lock: "FOR UPDATE")
    command = Repo.one!(from c in Command, where: c.id == ^initial.id, lock: "FOR UPDATE")
    notice = Repo.get!(Message, command.continuation_message_id)

    if not source_live?(thread, run, command) or not current_configuration?(environment, command) do
      Orbit.touch!(notice, %{address_agent: false})
    else
      if notice.address_agent, do: Runs.follow_up(thread.id)
    end

    # Rotate even while another run/provider prevents starting the continuation.
    command |> Ecto.Changeset.change(updated_at: DateTime.utc_now()) |> Repo.update!()
  end

  defp sweep_locked!(initial) do
    thread = Orbit.lock!(initial.thread_id)
    run = Repo.one!(from r in Run, where: r.id == ^initial.run_id, lock: "FOR UPDATE")
    environment = Repo.one(from e in Environment, where: e.id == ^initial.environment_id, lock: "FOR UPDATE")
    command = Repo.one!(from c in Command, where: c.id == ^initial.id, lock: "FOR UPDATE")

    if command.status in @active do
      invalid = not source_live?(thread, run, command) or not current_configuration?(environment, command)

      command
      |> Ecto.Changeset.change(
        status: swept_status(command, invalid),
        updated_at: DateTime.utc_now(),
        cancel_requested: command.cancel_requested or invalid
      )
      |> Repo.update!()
    end
  end

  defp swept_status(command, invalid) do
    deadline =
      if command.status == "claimed" and command.tool in @terminal,
        do: command.result_deadline,
        else: command.expires_at

    cond do
      command.status == "claimed" and (invalid or expired?(deadline)) -> "unknown"
      invalid -> "cancelled"
      expired?(deadline) -> "expired"
      true -> command.status
    end
  end

  defp digest(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic])) |> Base.encode16(case: :lower)

  defp audit(command, action, actor_id, interface) do
    Audit.record("environment.command_#{action}", %{
      actor_id: actor_id,
      interface: interface,
      target_type: "environment_command",
      target_id: command.id,
      metadata: %{environment_id: command.environment_id, run_id: command.run_id, tool: command.tool}
    })
  end
end
