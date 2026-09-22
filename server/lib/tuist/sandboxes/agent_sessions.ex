defmodule Tuist.Sandboxes.AgentSessions do
  @moduledoc """
  Starts and follows Managed Agents sessions on an account's connected
  environment using the organization API key stored on that environment,
  so callers never hold the key themselves. Anthropic owns the session;
  the `sandbox_agent_sessions` row keeps the ids, the request and the
  last status the server saw.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.Anthropic.ControlPlane
  alias Tuist.Sandboxes.Sandbox

  @default_system_prompt "You are a coding agent working inside a Tuist sandbox. " <>
                           "The working directory is /workspace and it persists across turns. " <>
                           "Repositories requested for the session are cloned under /workspace before you start. " <>
                           "Use bash for anything that touches the machine."
  @idle_event_type "session.status_idle"
  @text_event_types ["user.message", "agent.message", "user.tool_result", "agent.tool_result"]
  @recent_events_limit 100
  @events_page_limit 1000
  @events_page_cap 20

  def default_system_prompt, do: @default_system_prompt

  @doc """
  Creates the Anthropic session for `attrs.prompt` and records it.

  `attrs` may also carry `agent_environment_id` (defaults to the account's
  single enabled environment), `title`, `repository_url`, `repository_ref`,
  `model` (defaults to the environment's), `budget_cents` and `agent_id`
  (skips the cached agent). `opts` takes `:created_by_user_id`.

  The row id is generated before the Anthropic call so it can travel in
  the session's metadata, which is how the router finds the row again
  from a work item.
  """
  def start_agent_session(%Account{} = account, attrs, opts \\ []) when is_map(attrs) do
    id = Ecto.UUID.generate()

    with {:ok, params} <- validate_params(attrs),
         {:ok, agent_environment} <- resolve_agent_environment(account, attrs[:agent_environment_id]),
         {:ok, api_key} <- api_key(agent_environment),
         model = params.model || agent_environment.agent_model,
         {:ok, agent_id} <- ensure_agent(account, agent_environment, api_key, model, attrs[:agent_id]),
         {:ok, remote} <- create_session(api_key, agent_id, agent_environment, account, id, params) do
      %AgentSession{id: id}
      |> AgentSession.create_changeset(%{
        account_id: account.id,
        agent_environment_id: agent_environment.id,
        anthropic_session_id: remote["id"],
        anthropic_agent_id: agent_id,
        prompt: params.prompt,
        title: params.title,
        repository_url: params.repository_url,
        repository_ref: params.repository_ref,
        model: model,
        budget_cents: params.budget_cents,
        last_status: remote["status"],
        created_by_user_id: Keyword.get(opts, :created_by_user_id)
      })
      |> Repo.insert()
    end
  end

  def list_agent_sessions(%Account{id: account_id}) do
    Repo.all(
      from s in AgentSession,
        where: s.account_id == ^account_id,
        order_by: [desc: s.inserted_at, desc: s.id]
    )
  end

  def get_agent_session(%Account{id: account_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %AgentSession{} = agent_session <- Repo.get_by(AgentSession, id: uuid, account_id: account_id) do
      {:ok, agent_session}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_agent_session!(%Account{} = account, id) do
    case get_agent_session(account, id) do
      {:ok, agent_session} -> agent_session
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: AgentSession
    end
  end

  def get_agent_session_by_anthropic_session_id(anthropic_session_id) when is_binary(anthropic_session_id) do
    Repo.get_by(AgentSession, anthropic_session_id: anthropic_session_id)
  end

  def bind_sandbox(%AgentSession{} = agent_session, %Sandbox{id: sandbox_id}) do
    update_agent_session(agent_session, %{sandbox_id: sandbox_id})
  end

  @doc """
  Reads the session back from Anthropic, stores its status (and, when it
  is idle, the stop reason of the latest idle event) and returns the
  updated row with `status`, `usage` and the bound sandbox's state.
  """
  def refresh_agent_session(%AgentSession{} = agent_session) do
    with {:ok, api_key} <- api_key_for(agent_session),
         {:ok, remote} <- ControlPlane.get_session(api_key, agent_session.anthropic_session_id) do
      status = remote["status"]

      attrs =
        maybe_put(
          %{last_status: status},
          :last_stop_reason,
          if(status == "idle", do: latest_stop_reason(api_key, agent_session))
        )

      with {:ok, agent_session} <- update_agent_session(agent_session, attrs) do
        {:ok,
         %{
           session: agent_session,
           status: status,
           usage: usage(remote["usage"]),
           sandbox_state: sandbox_state(agent_session)
         }}
      end
    end
  end

  def send_agent_session_message(%AgentSession{} = agent_session, text) when is_binary(text) do
    with {:ok, api_key} <- api_key_for(agent_session),
         {:ok, _sent} <- ControlPlane.send_message(api_key, agent_session.anthropic_session_id, text) do
      :ok
    end
  end

  @doc """
  Returns the session's events flattened to
  `%{id, type, at, text, command, tool_name, stop_reason}`, oldest first,
  following Anthropic's pages (at most #{@events_page_cap} per call).
  `after: cursor` resumes after the event a previous call returned as
  `next_after`, so a client polls incrementally. `next_after` is the
  cursor of the last event returned, the cursor passed in when nothing
  newer exists and nil when the session has no events at all.

  The cursor is the base64url of `"<processed_at>|<event_id>"`. Listing
  with one asks Anthropic for events processed at or after that
  timestamp and drops everything up to and including the event id, so
  events sharing a timestamp are neither lost nor repeated.
  """
  def list_agent_session_events(%AgentSession{} = agent_session, opts \\ []) do
    after_cursor = Keyword.get(opts, :after)

    with {:ok, cursor} <- decode_cursor(after_cursor),
         {:ok, api_key} <- api_key_for(agent_session),
         {:ok, events} <- fetch_events(api_key, agent_session.anthropic_session_id, cursor) do
      simplified = events |> Enum.map(&simplify_event/1) |> drop_through(cursor)
      remember_stop_reason(agent_session, simplified)

      next_after =
        case {simplified, cursor} do
          {[], nil} -> nil
          {[], _cursor} -> after_cursor
          {newer, _cursor} -> encode_cursor(newer, cursor)
        end

      {:ok, %{events: simplified, next_after: next_after}}
    end
  end

  def archive_agent_session(%AgentSession{} = agent_session) do
    with {:ok, api_key} <- api_key_for(agent_session),
         {:ok, _archived} <- ControlPlane.archive_session(api_key, agent_session.anthropic_session_id) do
      update_agent_session(agent_session, %{last_status: "archived"})
    end
  end

  # ----- Starting -----

  defp validate_params(attrs) do
    %AgentSession{}
    |> AgentSession.params_changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp resolve_agent_environment(%Account{id: account_id}, nil) do
    case Repo.all(from e in AgentEnvironment, where: e.account_id == ^account_id and e.enabled == true) do
      [agent_environment] -> {:ok, agent_environment}
      _ -> {:error, :no_agent_environment}
    end
  end

  defp resolve_agent_environment(%Account{id: account_id}, id) do
    case Repo.get_by(AgentEnvironment, id: id, account_id: account_id) do
      %AgentEnvironment{} = agent_environment -> {:ok, agent_environment}
      nil -> {:error, :no_agent_environment}
    end
  end

  defp api_key(%AgentEnvironment{anthropic_api_key: api_key}) when is_binary(api_key) and api_key != "",
    do: {:ok, api_key}

  defp api_key(%AgentEnvironment{}), do: {:error, :missing_api_key}

  defp api_key_for(%AgentSession{agent_environment_id: agent_environment_id}) do
    case Repo.get(AgentEnvironment, agent_environment_id) do
      %AgentEnvironment{} = agent_environment -> api_key(agent_environment)
      nil -> {:error, :no_agent_environment}
    end
  end

  defp ensure_agent(_account, _agent_environment, _api_key, _model, agent_id)
       when is_binary(agent_id) and agent_id != "" do
    {:ok, agent_id}
  end

  defp ensure_agent(
         _account,
         %AgentEnvironment{anthropic_agent_id: agent_id, agent_model: model},
         _api_key,
         model,
         _agent_id
       )
       when is_binary(agent_id) do
    {:ok, agent_id}
  end

  # The cached agent only ever matches the environment's own model, so an
  # agent created for a per-session model override is not cached.
  defp ensure_agent(%Account{} = account, %AgentEnvironment{} = agent_environment, api_key, model, _agent_id) do
    attrs = %{
      name: "tuist-" <> account.name,
      model: model,
      system: agent_environment.agent_system_prompt || @default_system_prompt
    }

    case ControlPlane.create_agent(api_key, attrs) do
      {:ok, %{"id" => agent_id}} when is_binary(agent_id) ->
        if model == agent_environment.agent_model do
          {:ok, _} = agent_environment |> AgentEnvironment.cache_agent_changeset(agent_id) |> Repo.update()
        end

        {:ok, agent_id}

      {:ok, body} ->
        {:error, {:malformed_response, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_session(api_key, agent_id, agent_environment, account, id, params) do
    attrs = %{
      agent: agent_id,
      environment_id: agent_environment.anthropic_environment_id,
      title: params.title,
      budget_cents: params.budget_cents,
      metadata: %{
        "tuist_account" => account.name,
        "tuist_agent_session_id" => id,
        "repository_url" => params.repository_url || "",
        "repository_ref" => params.repository_ref || ""
      },
      initial_events: [first_message(params)]
    }

    case ControlPlane.create_session(api_key, attrs) do
      {:ok, %{"id" => session_id} = remote} when is_binary(session_id) -> {:ok, remote}
      {:ok, body} -> {:error, {:malformed_response, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ----- Following -----

  defp latest_stop_reason(api_key, %AgentSession{anthropic_session_id: session_id}) do
    case ControlPlane.list_events(api_key, session_id, order: "desc", limit: @recent_events_limit) do
      {:ok, %{data: events}} ->
        Enum.find_value(events, fn
          %{"type" => @idle_event_type} = event -> get_in(event, ["stop_reason", "type"])
          _event -> nil
        end)

      {:error, _reason} ->
        nil
    end
  end

  defp remember_stop_reason(%AgentSession{} = agent_session, simplified) do
    case simplified |> Enum.reverse() |> Enum.find_value(& &1.stop_reason) do
      nil -> :ok
      stop_reason when stop_reason == agent_session.last_stop_reason -> :ok
      stop_reason -> update_agent_session(agent_session, %{last_stop_reason: stop_reason})
    end
  end

  defp fetch_events(api_key, session_id, cursor) do
    params =
      case cursor do
        %{at: at} when is_binary(at) -> [limit: @events_page_limit, created_at_gte: at]
        _none -> [limit: @events_page_limit]
      end

    fetch_pages(api_key, session_id, params, nil, [], @events_page_cap)
  end

  defp fetch_pages(api_key, session_id, params, page, acc, pages_left) do
    opts = if page, do: Keyword.put(params, :page, page), else: params

    case ControlPlane.list_events(api_key, session_id, opts) do
      {:ok, %{data: events, next_page: next_page}} when is_binary(next_page) and pages_left > 1 ->
        fetch_pages(api_key, session_id, params, next_page, [events | acc], pages_left - 1)

      {:ok, %{data: events}} ->
        {:ok, [events | acc] |> Enum.reverse() |> Enum.concat()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp drop_through(simplified, nil), do: simplified

  # The inclusive timestamp bound re-fetches the cursor event and any
  # sharing its timestamp; everything through the cursor id was already
  # delivered. A cursor whose event is missing keeps the whole window
  # rather than hiding events behind an id that will never show up.
  defp drop_through(simplified, %{id: id}) do
    case Enum.split_while(simplified, &(&1.id != id)) do
      {_delivered, [_cursor_event | newer]} -> newer
      {all, []} -> all
    end
  end

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(decoded, "|", parts: 2) do
      {:ok, %{at: blank_to_nil(at), id: id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_cursor), do: {:error, :invalid_cursor}

  # An event Anthropic has not processed yet has no `processed_at`; the
  # cursor then keeps the newest timestamp seen so the next listing still
  # starts from a bound Anthropic accepts.
  defp encode_cursor(simplified, cursor) do
    last = List.last(simplified)
    at = simplified |> Enum.reverse() |> Enum.find_value(& &1.at) || (cursor && cursor.at) || ""
    Base.url_encode64(at <> "|" <> to_string(last.id), padding: false)
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp simplify_event(event) when is_map(event) do
    type = event["type"]

    base = %{
      id: event["id"],
      type: type,
      at: event["processed_at"],
      text: nil,
      command: nil,
      tool_name: nil,
      stop_reason: nil
    }

    cond do
      type in @text_event_types -> %{base | text: text_content(event["content"])}
      type == "agent.tool_use" -> %{base | tool_name: event["name"], command: command(event["input"])}
      type == @idle_event_type -> %{base | stop_reason: get_in(event, ["stop_reason", "type"])}
      true -> base
    end
  end

  defp text_content(blocks) when is_list(blocks) do
    case for %{"type" => "text", "text" => text} when is_binary(text) <- blocks, do: text do
      [] -> nil
      texts -> Enum.join(texts, "\n")
    end
  end

  defp text_content(_content), do: nil

  defp command(%{"command" => command}) when is_binary(command), do: command
  defp command(_input), do: nil

  defp usage(%{} = usage) do
    %{
      input_tokens: usage["input_tokens"],
      output_tokens: usage["output_tokens"],
      cache_read_input_tokens: usage["cache_read_input_tokens"],
      active_seconds: usage["active_seconds"],
      list_cost: list_cost(usage["list_cost"])
    }
  end

  defp usage(_usage), do: nil

  defp list_cost(%{"amount" => amount, "currency" => currency}), do: %{amount: amount, currency: currency}
  defp list_cost(_list_cost), do: nil

  defp sandbox_state(%AgentSession{sandbox_id: nil}), do: nil

  defp sandbox_state(%AgentSession{sandbox_id: sandbox_id}) do
    case Repo.get(Sandbox, sandbox_id) do
      %Sandbox{state: state} -> state
      nil -> nil
    end
  end

  # ----- Helpers -----

  defp update_agent_session(%AgentSession{} = agent_session, attrs) do
    agent_session
    |> AgentSession.update_changeset(attrs)
    |> Repo.update()
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  # The agent only knows the working directory from its system prompt, so
  # the first message names the exact clone path when a repository was
  # requested.
  defp first_message(params) do
    prompt = params.prompt
    url = Map.get(params, :repository_url)

    if is_binary(url) and url != "" do
      ControlPlane.user_message("The repository #{url} is cloned at #{repository_directory(url)}.\n\n" <> prompt)
    else
      ControlPlane.user_message(prompt)
    end
  end

  defp repository_directory(url) do
    name =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> Kernel.||("")
      |> Path.basename()
      |> String.replace_suffix(".git", "")

    "/workspace/" <> name
  end
end
