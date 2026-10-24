defmodule Atlas.Orbit.Tools do
  @moduledoc """
  Builds the Condukt tools for one run attempt and executes each call.

  Every call is fenced to the attempt that built it (`Runs.with_attempt/3`) and
  re-checked against current state under the thread lock: the run is
  still running and not cancelled, the thread is active, the acting user
  can read it, and every reader holds the tool's scopes. The MCP tool then runs
  in-process as the acting user, outside any lock. Its result is stored, and
  its scopes ratcheted onto the thread, in one fenced transaction that
  re-checks the audience again. The model receives the result only after that
  commit, so output never reaches a reply that someone without access can read.
  """

  import Ecto.Query

  alias Atlas.MCP.Server
  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Rendering
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Subagents
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.ToolPolicy
  alias Atlas.Repo
  alias Atlas.Users.User

  @unavailable "This tool is not available in this thread."
  @tool_timeout :timer.seconds(60)
  @superseded "This run was resumed elsewhere; the result was discarded."

  @doc "Condukt tools offered to this attempt, filtered by the current audience floor."
  def build(%Run{id: run_id, resume_count: attempt}, parent_message_id \\ nil) do
    case Runs.with_attempt(run_id, attempt, fn thread, run ->
           Subagents.authorize_parent!(thread, run, parent_message_id)
           tool_audience(thread, run)
         end) do
      {:ok, scopes} ->
        scopes |> ToolPolicy.available() |> Enum.map(&inline_tool(run_id, attempt, &1, parent_message_id))

      {:error, _reason} ->
        []
    end
  end

  defp tool_audience(thread, run) do
    acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)
    audience = Access.audience(thread)

    if acting_user && Enum.any?(audience, &(&1.id == acting_user.id)),
      do: Access.effective_scopes(audience),
      else: MapSet.new()
  end

  defp inline_tool(run_id, attempt, descriptor, parent_message_id) do
    name = descriptor["name"]

    Condukt.tool(
      name: name,
      description: descriptor["description"] || "",
      parameters: descriptor["inputSchema"] || %{"type" => "object", "properties" => %{}},
      call: fn args, context -> call(run_id, attempt, name, args || %{}, parent_message_id, context) end
    )
  end

  @doc false
  def call(run_id, attempt, name, args, parent_message_id \\ nil, context \\ %{}) do
    case ToolPolicy.required_scopes(name) do
      {:ok, scopes} ->
        perform(run_id, attempt, name, args, parent_message_id, scopes, fn message, acting_user ->
          execute(acting_user, run_id, message.thread_id, name, args, context)
        end)

      _ ->
        {:error, @unavailable}
    end
  end

  @doc false
  def task(%Run{} = run, args, context) do
    if Subagents.valid_args?(args) do
      perform(run.id, run.resume_count, "task", args, nil, [], fn message, _acting_user ->
        Subagents.execute(run, message, args, context)
      end)
    else
      {:error, "Provide one nonempty research task of at most 4,000 characters."}
    end
  end

  defp perform(run_id, attempt, name, args, parent_message_id, scopes, execute) do
    case Runs.with_attempt(run_id, attempt, &begin!(&1, &2, scopes, name, args, parent_message_id)) do
      {:ok, {:execute, message, acting_user}} ->
        Orbit.notify_changed(message.thread_id)

        execute.(message, acting_user)
        |> case do
          {:ok, result} ->
            settle(run_id, attempt, message, scopes, {:ok, result})

          {:error, reason} ->
            settle(run_id, attempt, message, scopes, {:error, Rendering.error(reason)})
        end

      {:ok, {:replay, result}} ->
        {:ok, result}

      {:ok, {:replay_error, reason}} ->
        {:error, reason}

      {:error, :stale} ->
        {:error, @superseded}

      {:error, :cancelled} ->
        {:error, "The run was cancelled."}

      {:error, _reason} ->
        {:error, @unavailable}
    end
  end

  # Runs the MCP tool in its own process so a tool that raises or hangs settles
  # its card as failed instead of leaving it running.
  defp execute(acting_user, run_id, thread_id, name, args, context) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args}
    }

    task =
      Task.Supervisor.async_nolink(Atlas.TaskSupervisor, fn ->
        if Subagents.register_tool(context) == :ok do
          acting_user |> conn(run_id, thread_id) |> Server.handle_message(request) |> normalize()
        else
          {:error, "The research task was stopped."}
        end
      end)

    case Task.yield(task, @tool_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, outcome} -> outcome
      {:exit, _reason} -> {:error, "The tool failed."}
      nil -> {:error, "The tool timed out."}
    end
  end

  defp begin!(thread, run, scopes, name, args, parent_message_id) do
    Subagents.authorize_parent!(thread, run, parent_message_id)
    acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)

    cond do
      not is_nil(run.cancel_requested_at) ->
        Repo.rollback(:cancelled)

      thread.status != "active" or is_nil(acting_user) ->
        Repo.rollback(:unavailable)

      match?({:ok, _}, Access.authorize_tool(thread, acting_user, scopes)) ->
        open_call!(thread, run, acting_user, name, args, parent_message_id)

      true ->
        Repo.rollback(:unavailable)
    end
  end

  defp open_call!(thread, run, acting_user, name, args, parent_message_id) do
    key = call_key(name, args, parent_message_id)

    case recorded_call(run, key) do
      %Message{tool_status: "succeeded", tool_result: result} when is_binary(result) ->
        {:replay, result}

      %Message{} = recorded when name == "task" ->
        # Never launch a second child for an in-flight or interrupted task.
        # A checkpoint can replay completed children, but not restart them.
        {:replay_error, Subagents.recorded_error(recorded)}

      %Message{} = interrupted ->
        {:execute, Orbit.touch!(interrupted, %{tool_status: "running", tool_output: ""}), acting_user}

      nil ->
        if name == "task", do: Subagents.reserve!(run)

        message =
          Orbit.append!(thread, %{
            kind: "tool",
            run_id: run.id,
            parent_message_id: parent_message_id,
            tool_name: name,
            tool_status: "running",
            tool_input: Rendering.input(args),
            tool_call_key: key
          })

        {:execute, message, acting_user}
    end
  end

  # Identical calls within one run (same tool and arguments) share a card. A
  # completed call is answered from its recorded result instead of executing
  # again, which is how a resumed attempt continues without duplicate tool
  # events or repeated side effects. Access is re-authorized first either way.
  defp call_key(name, args, parent_message_id) do
    # Preserve existing root replay keys across deployment and resumption.
    term = if is_nil(parent_message_id), do: {name, args}, else: {parent_message_id, name, args}

    :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp recorded_call(run, key) do
    Repo.one(
      from(message in Message,
        where: message.run_id == ^run.id and message.tool_call_key == ^key,
        order_by: [desc: message.position],
        limit: 1
      )
    )
  end

  defp settle(run_id, attempt, message, scopes, outcome) do
    run_id
    |> Runs.with_attempt(attempt, &settle_locked(&1, &2, message, scopes, outcome))
    |> case do
      {:ok, reply} ->
        Orbit.notify_changed(message.thread_id)
        reply

      {:error, :stale} ->
        {:error, @superseded}

      {:error, _reason} ->
        {:error, @unavailable}
    end
  end

  defp settle_locked(thread, run, message, scopes, outcome) do
    message = Repo.reload!(message)

    case {outcome,
          authorized?(thread, run, scopes) and Subagents.parent_active?(thread, run, message.parent_message_id)} do
      {{:ok, result}, true} ->
        ratchet!(thread, scopes)
        model_result = Rendering.for_model(result)

        Orbit.touch!(message, %{
          tool_status: "succeeded",
          tool_output: Rendering.output(result, message.tool_name),
          tool_result: model_result
        })

        {:ok, model_result}

      # Tool error text can disclose domain state ("no invoice for account X"),
      # so an authorized failure ratchets the same scopes as a success.
      {{:error, reason}, true} ->
        ratchet!(thread, scopes)
        Orbit.touch!(message, %{tool_status: "failed", tool_output: reason})
        {:error, reason}

      {_outcome, false} ->
        Orbit.touch!(message, %{tool_status: "cancelled", tool_output: ""})
        {:error, "Access to this thread changed during the call, so the result was discarded."}
    end
  end

  defp authorized?(thread, run, scopes) do
    acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)

    is_nil(run.cancel_requested_at) and thread.status == "active" and
      match?({:ok, _}, Access.authorize_tool(thread, acting_user, scopes))
  end

  defp ratchet!(%Thread{} = thread, scopes) do
    required = Enum.sort(Enum.uniq(thread.required_scopes ++ scopes))

    if required != Enum.sort(thread.required_scopes) do
      Repo.update_all(from(c in Thread, where: c.id == ^thread.id),
        set: [required_scopes: required]
      )
    end
  end

  defp conn(%User{} = acting_user, run_id, thread_id) do
    %{
      assigns: %{
        current_user: acting_user,
        audit_interface: "worker",
        mcp_claims: %{
          "scopes" => ["mcp"],
          "thread_id" => thread_id,
          "orbit_run_id" => run_id
        }
      }
    }
  end

  defp normalize(%{"result" => %{"isError" => true} = result}), do: {:error, text(result)}

  defp normalize(%{"result" => %{"structuredContent" => content}}) when is_map(content), do: {:ok, content}

  defp normalize(%{"result" => result}), do: {:ok, text(result)}

  defp normalize(%{"error" => %{"message" => message}}) when is_binary(message), do: {:error, message}

  defp normalize(_response), do: {:error, "The tool call failed."}

  defp text(%{"content" => parts}) when is_list(parts) do
    Enum.map_join(parts, "\n", fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      _part -> ""
    end)
  end

  defp text(_result), do: ""
end
