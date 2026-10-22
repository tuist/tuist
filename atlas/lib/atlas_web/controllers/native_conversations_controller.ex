defmodule AtlasWeb.NativeConversationsController do
  @moduledoc """
  Bearer-authenticated conversation routes for native clients. Conversations a
  caller cannot read return 404, indistinguishable from missing ones.
  """
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Conversations
  alias Atlas.Conversations.Components
  alias Atlas.Conversations.Conversation
  alias Atlas.Conversations.Message
  alias Atlas.Users.User

  def action(conn, _opts) do
    if Atlas.Demo.enabled?() do
      error(conn, :not_found, "not_found")
    else
      Audit.with_context(Audit.context_from_conn(conn, "api"), fn ->
        apply(__MODULE__, action_name(conn), [conn, conn.params])
      end)
    end
  end

  def index(conn, params) do
    case page(params) do
      {:ok, page} ->
        user = conn.assigns.current_user
        {items, meta} = Conversations.list_for_user(user, page)

        json(conn, %{
          bot: %{name: Conversations.agent_name(), configured: Conversations.agent_configured?()},
          conversations: Map.put(meta, :items, Enum.map(items, &conversation/1))
        })

      _ ->
        error(conn, :unprocessable_entity, "invalid_params")
    end
  end

  def private(conn, _params) do
    case Conversations.ensure_private(conn.assigns.current_user) do
      {:ok, conversation, :created} -> conn |> put_status(:created) |> json(%{conversation: conversation(conversation)})
      {:ok, conversation, :existing} -> json(conn, %{conversation: conversation(conversation)})
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def create(conn, params) do
    case Conversations.create_shared(conn.assigns.current_user, Map.take(params, ["title", "participant_ids"])) do
      {:ok, conversation} -> conn |> put_status(:created) |> json(%{conversation: conversation(conversation)})
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def messages(conn, %{"id" => id} = params) do
    with {:ok, page} <- page(params),
         {:ok, conversation} <- Conversations.fetch(conn.assigns.current_user, id) do
      {items, meta} = Conversations.list_messages(conversation, page)

      json(conn, %{
        conversation: conversation(conversation),
        messages: Map.put(meta, :items, Enum.map(items, &message/1)),
        latest_seq: conversation.last_seq
      })
    else
      {:error, :not_found} -> error(conn, :not_found, "not_found")
      _ -> error(conn, :unprocessable_entity, "invalid_params")
    end
  end

  def post_message(conn, %{"id" => id} = params) do
    with {:ok, conversation} <- Conversations.fetch(conn.assigns.current_user, id),
         {:ok, message, created} <-
           Conversations.post_message(
             conn.assigns.current_user,
             conversation,
             Map.take(params, ["body", "client_id", "address_agent"])
           ) do
      status = if created == :created, do: :created, else: :ok
      conn |> put_status(status) |> json(%{message: message(message)})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def add_participant(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, conversation} <- Conversations.fetch(user, id),
         {:ok, added} <- Conversations.add_participant(user, conversation, params["user_id"]) do
      conn |> put_status(:created) |> json(%{participant: %{id: added.id, name: Conversations.display_name(added)}})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def remove_participant(conn, %{"id" => id, "user_id" => user_id}) do
    user = conn.assigns.current_user

    with {:ok, conversation} <- Conversations.fetch(user, id),
         :ok <- Conversations.remove_participant(user, conversation, user_id) do
      json(conn, %{removed: true})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def cancel_run(conn, %{"id" => id, "run_id" => run_id}) do
    user = conn.assigns.current_user

    with {:ok, conversation} <- Conversations.fetch(user, id),
         {:ok, run} <- Conversations.cancel_run(user, conversation, run_id) do
      conn |> put_status(:accepted) |> json(%{run: %{id: run.id, status: run.status}})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  @doc false
  def conversation(%Conversation{} = conversation) do
    active_run = Conversations.active_run(conversation)

    %{
      id: conversation.id,
      title: if(conversation.kind == "private", do: Conversations.agent_name(), else: conversation.title),
      kind: conversation.kind,
      status: conversation.status,
      summary: conversation.summary || "",
      origin: conversation.origin,
      owner_id: conversation.owner_id,
      participants:
        Enum.map(conversation.participants, fn participant ->
          %{id: participant.user_id, name: Conversations.display_name(participant.user)}
        end),
      agent_status: agent_status(active_run),
      latest_seq: conversation.last_seq,
      updated_at: DateTime.to_iso8601(conversation.updated_at)
    }
  end

  defp agent_status(nil) do
    if Conversations.agent_configured?(), do: "idle", else: "unconfigured"
  end

  defp agent_status(run), do: run.status

  @doc false
  def message(%Message{} = message) do
    %{
      id: message.id,
      kind: message.kind,
      body: message.body,
      author_id: if(message.kind == "human", do: message.author_id),
      author_name: author_name(message),
      inserted_at: DateTime.to_iso8601(message.inserted_at),
      tool_name: message.tool_name,
      tool_status: message.tool_status,
      tool_input: message.tool_input || "",
      tool_output: message.tool_output || "",
      component: Components.for_message(message),
      # Stable creation order; clients sort by it. Status changes to a tool
      # message move the conversation's revision, not this value.
      seq: message.position
    }
  end

  defp author_name(%Message{kind: "human", author: %User{} = author}), do: Conversations.display_name(author)
  defp author_name(%Message{kind: "human"} = message), do: message.author_name
  defp author_name(%Message{kind: kind}) when kind in ["agent", "tool"], do: Conversations.agent_name()
  defp author_name(_message), do: ""

  defp page(params) do
    case Map.get(params, "page", "1") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {page, ""} when page >= 1 and page <= 100_000 -> {:ok, page}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp respond_error(conn, {:invalid_field, field}),
    do:
      conn |> put_status(:unprocessable_entity) |> json(%{error: "validation_failed", fields: %{field => ["invalid"]}})

  defp respond_error(conn, %Ecto.Changeset{} = changeset) do
    fields = Ecto.Changeset.traverse_errors(changeset, fn {_message, _opts} -> "invalid" end)
    conn |> put_status(:unprocessable_entity) |> json(%{error: "validation_failed", fields: fields})
  end

  defp respond_error(conn, :missing_access),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "validation_failed", fields: %{user_id: ["missing_access"]}})

  defp respond_error(conn, :not_found), do: error(conn, :not_found, "not_found")
  defp respond_error(conn, :forbidden), do: error(conn, :forbidden, "forbidden")
  defp respond_error(conn, :archived), do: error(conn, :conflict, "archived")
  defp respond_error(conn, :rate_limited), do: error(conn, :too_many_requests, "rate_limited")
  defp respond_error(conn, _reason), do: error(conn, :conflict, "conflict")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
