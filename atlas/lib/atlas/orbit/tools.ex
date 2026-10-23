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
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.ToolPolicy
  alias Atlas.Repo
  alias Atlas.Users.User

  @unavailable "This tool is not available in this thread."
  @tool_timeout :timer.seconds(60)
  @superseded "This run was resumed elsewhere; the result was discarded."

  @doc "Condukt tools offered to this attempt, filtered by the current audience floor."
  def build(%Run{id: run_id, resume_count: attempt}) do
    case Runs.with_attempt(run_id, attempt, fn thread, run -> tool_audience(thread, run) end) do
      {:ok, scopes} -> scopes |> ToolPolicy.available() |> Enum.map(&inline_tool(run_id, attempt, &1))
      {:error, _reason} -> []
    end
  end

  defp tool_audience(thread, run) do
    acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)
    audience = Access.audience(thread)

    if acting_user && Enum.any?(audience, &(&1.id == acting_user.id)),
      do: Access.effective_scopes(audience),
      else: MapSet.new()
  end

  defp inline_tool(run_id, attempt, descriptor) do
    name = descriptor["name"]

    Condukt.tool(
      name: name,
      description: descriptor["description"] || "",
      parameters: descriptor["inputSchema"] || %{"type" => "object", "properties" => %{}},
      call: fn args, _context -> call(run_id, attempt, name, args || %{}) end
    )
  end

  @doc false
  def call(run_id, attempt, name, args) do
    with {:ok, scopes} <- ToolPolicy.required_scopes(name),
         {:ok, {:execute, message, acting_user}} <-
           Runs.with_attempt(run_id, attempt, &begin!(&1, &2, scopes, name, args)) do
      Orbit.notify_changed(message.thread_id)

      acting_user
      |> execute(run_id, message.thread_id, name, args)
      |> case do
        {:ok, result} -> settle(run_id, attempt, message, scopes, {:ok, result})
        {:error, reason} -> settle(run_id, attempt, message, scopes, {:error, Rendering.error(reason)})
      end
    else
      {:ok, {:replay, result}} -> {:ok, result}
      :error -> {:error, @unavailable}
      {:error, :stale} -> {:error, @superseded}
      {:error, :cancelled} -> {:error, "The run was cancelled."}
      {:error, _reason} -> {:error, @unavailable}
    end
  end

  # Runs the MCP tool in its own process so a tool that raises or hangs settles
  # its card as failed instead of leaving it running.
  defp execute(acting_user, run_id, thread_id, name, args) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args}
    }

    task =
      Task.Supervisor.async_nolink(Atlas.TaskSupervisor, fn ->
        acting_user |> conn(run_id, thread_id) |> Server.handle_message(request) |> normalize()
      end)

    case Task.yield(task, @tool_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, outcome} -> outcome
      {:exit, _reason} -> {:error, "The tool failed."}
      nil -> {:error, "The tool timed out."}
    end
  end

  defp begin!(thread, run, scopes, name, args) do
    acting_user = run.acting_user_id && Repo.get(User, run.acting_user_id)

    cond do
      not is_nil(run.cancel_requested_at) ->
        Repo.rollback(:cancelled)

      thread.status != "active" or is_nil(acting_user) ->
        Repo.rollback(:unavailable)

      match?({:ok, _}, Access.authorize_tool(thread, acting_user, scopes)) ->
        open_call!(thread, run, acting_user, name, args)

      true ->
        Repo.rollback(:unavailable)
    end
  end

  defp open_call!(thread, run, acting_user, name, args) do
    key = call_key(name, args)

    case recorded_call(run, key) do
      %Message{tool_status: "succeeded", tool_result: result} when is_binary(result) ->
        {:replay, result}

      %Message{} = interrupted ->
        {:execute, Orbit.touch!(interrupted, %{tool_status: "running", tool_output: ""}), acting_user}

      nil ->
        message =
          Orbit.append!(thread, %{
            kind: "tool",
            run_id: run.id,
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
  defp call_key(name, args) do
    :crypto.hash(:sha256, :erlang.term_to_binary({name, args}, [:deterministic])) |> Base.encode16(case: :lower)
  end

  defp recorded_call(run, key) do
    Repo.one(
      from message in Message,
        where: message.run_id == ^run.id and message.tool_call_key == ^key,
        order_by: [desc: message.position],
        limit: 1
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

    case {outcome, authorized?(thread, run, scopes)} do
      {{:ok, result}, true} ->
        ratchet!(thread, scopes)
        model_result = Rendering.for_model(result)

        Orbit.touch!(message, %{
          tool_status: "succeeded",
          tool_output: Rendering.output(result),
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
      Repo.update_all(from(c in Thread, where: c.id == ^thread.id), set: [required_scopes: required])
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
