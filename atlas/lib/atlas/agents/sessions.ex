defmodule Atlas.Agents.Sessions do
  @moduledoc """
  Auditing layer around Condukt-driven agentic runs.

  Wrappers around `Condukt.run/2`, `Condukt.run/3`, and
  `Condukt.Operation.run/4` that mint a UUIDv7 session id, persist a
  `Atlas.Agents.Sessions.Session` row before the run starts, finalize it
  afterwards, and let `Atlas.Agents.Sessions.TelemetryHandler` attach the
  per-event audit trail in between.
  """

  import Ecto.Query

  alias Atlas.Agents.Sessions.Session
  alias Atlas.Repo
  alias Condukt.SessionID

  @atlas_opts [:account_id]

  @doc """
  Wraps `Condukt.run(agent_module, prompt, opts)` where `agent_module`
  is a real `use Condukt` module.
  """
  def run(agent_module, prompt, opts \\ []) when is_atom(agent_module) and is_binary(prompt) do
    {session, condukt_opts} = start_session(agent_module, prompt, opts)

    finalize(
      session,
      Condukt.run(agent_module, prompt, condukt_opts)
    )
  end

  @doc """
  Wraps `Condukt.Operation.run(agent_module, operation_name, args, opts)`.

  The audit row's `prompt` is set to the JSON-encoded operation args so
  the audit page can show what the operation was invoked with.
  """
  def run_operation(agent_module, operation_name, args, opts \\ [])
      when is_atom(agent_module) and is_atom(operation_name) and is_map(args) do
    prompt = "operation:#{operation_name} #{JSON.encode!(args)}"
    {session, condukt_opts} = start_session(agent_module, prompt, opts)

    finalize(
      session,
      Condukt.Operation.run(agent_module, operation_name, args, condukt_opts)
    )
  end

  @doc """
  Starts an audited session and passes the Condukt options to `fun`.

  This is used by streaming callers that need to own the lower-level Condukt
  session lifecycle while still writing the same session and event records as
  `run/3`.
  """
  def with_session(agent_module, prompt, opts \\ [], fun)
      when is_atom(agent_module) and is_binary(prompt) and is_function(fun, 1) do
    {session, condukt_opts} = start_session(agent_module, prompt, opts)

    try do
      finalize(session, fun.(condukt_opts))
    rescue
      exception ->
        finalize(session, {:error, exception})
        reraise(exception, __STACKTRACE__)
    catch
      kind, reason ->
        finalize(session, {:error, {kind, reason}})
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Lists agent sessions, newest first, preloading the linked account.

  Accepts `:page` (default 1) and `:page_size` (default 20) options and
  returns `{sessions, meta}` where `meta` carries `:total_count`,
  `:total_pages`, `:current_page`, and `:page_size`.
  """
  def list_sessions(opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, 20) |> max(1)
    offset = (page - 1) * page_size

    total_count = Repo.aggregate(Session, :count, :id)

    total_pages =
      if total_count == 0, do: 0, else: ceil(total_count / page_size)

    sessions =
      Session
      |> order_by(desc: :started_at)
      |> limit(^page_size)
      |> offset(^offset)
      |> preload(:account)
      |> Repo.all()

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    }

    {sessions, meta}
  end

  @doc """
  Fetches a session by id and preloads the account and ordered events.

  Returns `nil` if no session matches.
  """
  def get_session(id) when is_binary(id) do
    Session
    |> preload([:account, :events])
    |> Repo.get(id)
  end

  @doc """
  Associates an account with an in-flight session.

  Useful for agents that discover the relevant account mid-run (for
  example, the email event agent calls `find_account` as a tool).
  """
  def attach_account(session_id, account_id) when is_binary(session_id) and is_binary(account_id) do
    case normalize_uuid(account_id) do
      {:ok, account_id} ->
        from(s in Session, where: s.id == ^session_id and is_nil(s.account_id))
        |> Repo.update_all(set: [account_id: account_id, updated_at: DateTime.utc_now()])
        |> case do
          {0, _} -> :ok
          {_, _} -> :ok
        end

      :error ->
        :ok
    end
  end

  defp start_session(agent_module, prompt, opts) do
    {atlas_opts, condukt_opts} = Keyword.split(opts, @atlas_opts)
    session_id = Keyword.get(condukt_opts, :id) || SessionID.generate()
    started_at = DateTime.utc_now()

    session =
      %{
        id: session_id,
        agent: inspect(agent_module),
        prompt: prompt,
        status: "running",
        started_at: started_at,
        account_id: Keyword.get(atlas_opts, :account_id)
      }
      |> Session.create_changeset()
      |> Repo.insert!()

    {session, Keyword.put(condukt_opts, :id, session_id)}
  end

  defp finalize(session, {:ok, result}) do
    update_session!(session, "succeeded", result_to_map(result), nil)
    account_id = extract_account_id(result)

    if account_id && is_nil(session.account_id) do
      attach_account(session.id, account_id)
    end

    {:ok, result}
  end

  defp finalize(session, {:error, reason}) do
    reason = sanitize_error(reason)

    update_session!(session, "failed", nil, format_error(reason))
    {:error, reason}
  end

  defp sanitize_error({:session_exit, reason}), do: {:session_exit, sanitize_exit(reason)}
  defp sanitize_error(reason), do: reason

  defp sanitize_exit({:noproc, {GenServer, :call, [process, _message, timeout]}}) do
    {:noproc, {GenServer, :call, [process, :redacted, timeout]}}
  end

  defp sanitize_exit({reason, stack}) when is_list(stack), do: {reason, :redacted_stack}
  defp sanitize_exit(reason), do: reason

  defp update_session!(session, status, result, error) do
    finished_at = DateTime.utc_now()
    duration_ms = DateTime.diff(finished_at, session.started_at, :millisecond)

    session
    |> Session.finalize_changeset(%{
      status: status,
      finished_at: finished_at,
      duration_ms: duration_ms,
      result: result,
      error: error
    })
    |> Repo.update!()
  end

  defp result_to_map(result) when is_map(result) and not is_struct(result), do: result
  defp result_to_map(result) when is_binary(result), do: %{"text" => result}
  defp result_to_map(result), do: %{"value" => inspect(result)}

  defp extract_account_id(%{"account_id" => id}) when is_binary(id), do: normalized_uuid_or_nil(id)
  defp extract_account_id(%{account_id: id}) when is_binary(id), do: normalized_uuid_or_nil(id)
  defp extract_account_id(_), do: nil

  defp normalized_uuid_or_nil(id) do
    case normalize_uuid(id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_uuid(id), do: Atlas.UUIDv7.cast(id)

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
