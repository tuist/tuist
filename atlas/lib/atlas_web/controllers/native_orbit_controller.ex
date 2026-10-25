defmodule AtlasWeb.NativeOrbitController do
  @moduledoc """
  Bearer-authenticated Orbit thread routes for native clients. Threads a
  caller cannot read return 404, indistinguishable from missing ones.
  """
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Orbit
  alias Atlas.Orbit.Attachments
  alias Atlas.Orbit.Components
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Progress
  alias Atlas.Orbit.Thread
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
    case {page(params), Map.get(params, "kind")} do
      {{:ok, page}, kind} when kind in [nil, "private", "shared"] ->
        user = conn.assigns.current_user
        {items, meta} = Orbit.list_for_user(user, page, kind)

        json(conn, %{
          assistant: %{name: Orbit.agent_name(), configured: Orbit.agent_configured?(user), can_create_private: true},
          threads: Map.put(meta, :items, Enum.map(items, &thread/1))
        })

      _ ->
        error(conn, :unprocessable_entity, "invalid_params")
    end
  end

  def private(conn, _params) do
    case Orbit.ensure_private(conn.assigns.current_user) do
      {:ok, thread, :created} -> conn |> put_status(:created) |> json(%{thread: thread(thread)})
      {:ok, thread, :existing} -> json(conn, %{thread: thread(thread)})
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def create(conn, %{"kind" => "private"} = params) do
    case Orbit.create_private(conn.assigns.current_user, Map.take(params, ["request_id"])) do
      {:ok, thread, :created} -> conn |> put_status(:created) |> json(%{thread: thread(thread)})
      {:ok, thread, :existing} -> json(conn, %{thread: thread(thread)})
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def create(conn, %{"kind" => kind}) when kind != "shared" do
    error(conn, :unprocessable_entity, "invalid_params")
  end

  def create(conn, params) do
    case Orbit.create_shared(conn.assigns.current_user, Map.take(params, ["title", "participant_ids"])) do
      {:ok, thread} -> conn |> put_status(:created) |> json(%{thread: thread(thread)})
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def messages(conn, %{"id" => id} = params) do
    with {:ok, page} <- page(params),
         {:ok, thread} <- Orbit.fetch(conn.assigns.current_user, id) do
      {items, meta} = Orbit.list_messages(thread, page)

      json(conn, %{
        thread: thread(thread),
        messages: Map.put(meta, :items, Enum.map(items, &message/1)),
        latest_seq: thread.last_seq
      })
    else
      {:error, :not_found} -> error(conn, :not_found, "not_found")
      _ -> error(conn, :unprocessable_entity, "invalid_params")
    end
  end

  def post_message(conn, %{"id" => id} = params) do
    with {:ok, thread} <- Orbit.fetch(conn.assigns.current_user, id),
         {:ok, message, created} <-
           Orbit.post_message(
             conn.assigns.current_user,
             thread,
             Map.take(params, ["body", "client_id", "address_agent", "attachment_ids", "mention_ids"])
           ) do
      status = if created == :created, do: :created, else: :ok
      conn |> put_status(status) |> json(%{message: message(message)})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def people(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, thread} <- Orbit.fetch(user, id),
         {:ok, people} <- Orbit.mention_people(user, thread, Map.get(params, "query", "")) do
      json(conn, %{people: people})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def upload_attachment(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, thread} <- Orbit.fetch(user, id),
         {:ok, attachment} <-
           Attachments.upload(user, thread, Map.take(params, ["filename", "content_type", "data", "client_id"])) do
      conn |> put_status(:created) |> json(%{attachment: Attachments.metadata(attachment)})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def download_attachment(conn, %{"id" => id, "attachment_id" => attachment_id}) do
    case Attachments.read(conn.assigns.current_user, id, attachment_id) do
      {:ok, attachment, bytes} ->
        json(conn, %{attachment: Map.put(Attachments.metadata(attachment), :data, Base.encode64(bytes))})

      {:error, reason} ->
        respond_error(conn, reason)
    end
  end

  def delete_attachment(conn, %{"id" => id, "attachment_id" => attachment_id}) do
    user = conn.assigns.current_user

    with {:ok, thread} <- Orbit.fetch(user, id),
         :ok <- Attachments.discard(user, thread, attachment_id) do
      json(conn, %{deleted: true})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def add_participant(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, thread} <- Orbit.fetch(user, id),
         {:ok, added} <- Orbit.add_participant(user, thread, params["user_id"]) do
      conn |> put_status(:created) |> json(%{participant: %{id: added.id, name: Orbit.display_name(added)}})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def remove_participant(conn, %{"id" => id, "user_id" => user_id}) do
    user = conn.assigns.current_user

    with {:ok, thread} <- Orbit.fetch(user, id),
         :ok <- Orbit.remove_participant(user, thread, user_id) do
      json(conn, %{removed: true})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  def cancel_run(conn, %{"id" => id, "run_id" => run_id}) do
    user = conn.assigns.current_user

    with {:ok, thread} <- Orbit.fetch(user, id),
         {:ok, run} <- Orbit.cancel_run(user, thread, run_id) do
      conn |> put_status(:accepted) |> json(%{run: %{id: run.id, status: run.status}})
    else
      {:error, reason} -> respond_error(conn, reason)
    end
  end

  @doc false
  def thread(%Thread{} = thread) do
    active_run = Orbit.active_run(thread)

    %{
      id: thread.id,
      title: thread.title,
      kind: thread.kind,
      status: thread.status,
      summary: thread.summary || "",
      origin: thread.origin,
      owner_id: thread.owner_id,
      participants:
        Enum.map(thread.participants, fn participant ->
          %{id: participant.user_id, name: Orbit.display_name(participant.user)}
        end),
      agent_status: agent_status(active_run),
      latest_seq: thread.last_seq,
      updated_at: DateTime.to_iso8601(thread.updated_at)
    }
  end

  defp agent_status(nil), do: "idle"

  defp agent_status(run), do: Progress.status(run)

  @doc false
  def message(%Message{} = message) do
    %{
      id: message.id,
      kind: message.kind,
      body: message.body,
      notice_kind: message.notice_kind,
      mentioned_user_ids: message.mentioned_user_ids,
      author_id: if(message.kind == "human", do: message.author_id),
      author_name: author_name(message),
      inserted_at: DateTime.to_iso8601(message.inserted_at),
      tool_name: message.tool_name,
      tool_status: message.tool_status,
      parent_message_id: message.parent_message_id,
      tool_input: message.tool_input || "",
      tool_output: message.tool_output || "",
      component: Components.for_message(message),
      attachments: Enum.map(message.attachments, &Attachments.metadata/1),
      # Stable creation order; clients sort by it. Status changes to a tool
      # message move the thread's revision, not this value.
      seq: message.position
    }
  end

  defp author_name(%Message{kind: "human", author: %User{} = author}), do: Orbit.display_name(author)
  defp author_name(%Message{kind: "human"} = message), do: message.author_name
  defp author_name(%Message{kind: kind}) when kind in ["agent", "tool"], do: Orbit.agent_name()
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
  defp respond_error(conn, :thread_promoted), do: error(conn, :conflict, "thread_promoted")
  defp respond_error(conn, :rate_limited), do: error(conn, :too_many_requests, "rate_limited")
  defp respond_error(conn, :storage_unavailable), do: error(conn, :service_unavailable, "storage_unavailable")
  defp respond_error(conn, _reason), do: error(conn, :conflict, "conflict")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
