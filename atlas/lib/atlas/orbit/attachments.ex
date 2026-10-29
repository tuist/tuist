defmodule Atlas.Orbit.Attachments do
  @moduledoc """
  Private, thread-scoped upload reservations. Objects never enter the executive
  document library and are never exposed through signed or public URLs.

  Reserve a cleanup ledger before writing storage. The second transaction locks
  thread then reservation across the write, so claim, deletion and expiry cannot
  race a late upload. A crash leaves a reservation for the cleanup worker.
  """

  import Ecto.Query

  alias Atlas.Documents.Storage
  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Attachment
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Workers.CleanupAttachments
  alias Atlas.Repo
  alias Atlas.Users.User

  @max_bytes 5 * 1024 * 1024
  @max_encoded_bytes 4 * div(@max_bytes + 2, 3)
  @max_per_message 4
  @pending_seconds 86_400
  @content_type ~r/\A[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*\z/

  def max_bytes, do: @max_bytes

  def metadata(%Attachment{} = attachment) do
    Map.take(attachment, [:id, :filename, :content_type, :byte_size])
  end

  def upload(%User{} = user, %Thread{id: thread_id}, params) do
    with {:ok, _thread} <- Orbit.fetch(user, thread_id),
         {:ok, attrs, bytes} <- validate_upload(params),
         {:ok, attachment} <- reserve(user, thread_id, attrs) do
      case store(user, thread_id, attachment, bytes) do
        {:ok, {:ok, uploaded}} ->
          {:ok, uploaded}

        {:ok, {:error, reason}} ->
          {:error, reason}

        {:error, reason} ->
          mark_for_cleanup(attachment.id)
          {:error, reason}
      end
    end
  end

  defp reserve(user, thread_id, attrs) do
    Repo.transaction(fn ->
      authorize_locked!(user, thread_id, :active)

      case Repo.one(
             from a in Attachment,
               where: a.thread_id == ^thread_id and a.user_id == ^user.id and a.client_id == ^attrs.client_id,
               lock: "FOR UPDATE"
           ) do
        nil -> insert_reservation!(user, thread_id, attrs)
        attachment -> replay_reservation!(attachment, attrs)
      end
    end)
  end

  defp insert_reservation!(user, thread_id, attrs) do
    id = Ecto.UUID.generate()

    Repo.insert!(
      struct!(
        Attachment,
        Map.merge(attrs, %{
          id: id,
          thread_id: thread_id,
          user_id: user.id,
          storage_key: "orbit/threads/#{thread_id}/attachments/#{id}",
          expires_at: DateTime.add(DateTime.utc_now(), @pending_seconds)
        })
      )
    )
  end

  defp replay_reservation!(attachment, attrs) do
    if attachment.payload_digest != attrs.payload_digest, do: Repo.rollback({:invalid_field, :client_id})

    if attachment.status == "deleting" or
         (attachment.status != "attached" and not DateTime.after?(attachment.expires_at, DateTime.utc_now())),
       do: Repo.rollback(:not_found)

    attachment
  end

  defp store(user, thread_id, attachment, bytes) do
    Repo.transaction(fn ->
      authorize_locked!(user, thread_id, :active)
      current = Repo.one(from a in Attachment, where: a.id == ^attachment.id, lock: "FOR UPDATE")

      if is_nil(current), do: Repo.rollback(:not_found)
      replay_reservation!(current, attachment)

      if current.status == "uploading" do
        write_object!(current, bytes)
      else
        {:ok, current}
      end
    end)
  end

  defp write_object!(attachment, bytes) do
    case Storage.put_object(attachment.storage_key, bytes, content_type: attachment.content_type) do
      {:ok, _} ->
        {:ok, update!(attachment, status: "pending")}

      {:error, _} ->
        delete_later!(attachment)
        {:error, :storage_unavailable}
    end
  end

  @doc "Reads bytes only after checking current thread access and pending-upload ownership."
  def read(%User{} = user, thread_id, id) do
    with {:ok, _thread} <- Orbit.fetch(user, thread_id),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Attachment{} = attachment <- Repo.get_by(Attachment, id: id, thread_id: thread_id),
         true <- readable?(attachment, user),
         {:ok, %{body: bytes}} when is_binary(bytes) <- Storage.get_object(attachment.storage_key),
         true <- byte_size(bytes) == attachment.byte_size,
         {:ok, _thread} <- Orbit.fetch(user, thread_id),
         %Attachment{} = current <- Repo.get_by(Attachment, id: id, thread_id: thread_id),
         true <- readable?(current, user) do
      {:ok, current, bytes}
    else
      _ -> {:error, :not_found}
    end
  end

  defp readable?(%Attachment{status: "attached", message_id: id}, _user), do: is_binary(id)

  defp readable?(%Attachment{status: "pending", user_id: owner, expires_at: expires_at}, user),
    do: owner == user.id and DateTime.after?(expires_at, DateTime.utc_now())

  defp readable?(_attachment, _user), do: false

  @doc "Only the uploader may discard an unclaimed upload; object deletion is durable and retryable."
  def discard(%User{} = user, %Thread{id: thread_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.transaction(fn ->
          authorize_locked!(user, thread_id, :readable)

          case Repo.one(from a in Attachment, where: a.id == ^id and a.thread_id == ^thread_id, lock: "FOR UPDATE") do
            %Attachment{user_id: owner, status: status} = attachment
            when owner == user.id and status in ["uploading", "pending", "deleting"] ->
              delete_later!(attachment)
              :ok

            _ ->
              Repo.rollback(:not_found)
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          error -> error
        end

      _ ->
        {:error, :not_found}
    end
  end

  def ids(params) do
    case Map.get(params, "attachment_ids", []) do
      ids when is_list(ids) and length(ids) <= @max_per_message ->
        casted = Enum.map(ids, &Ecto.UUID.cast/1)

        if Enum.all?(casted, &match?({:ok, _}, &1)) and length(Enum.uniq(casted)) == length(ids),
          do: {:ok, Enum.map(casted, &elem(&1, 1))},
          else: {:error, {:invalid_field, :attachment_ids}}

      _ ->
        {:error, {:invalid_field, :attachment_ids}}
    end
  end

  @doc "Claims a whole validated set while the caller holds the thread lock, after the client-id replay check."
  def claim!(ids, user, message) do
    now = DateTime.utc_now()

    attachments =
      Repo.all(from a in Attachment, where: a.id in ^ids, order_by: a.id, lock: "FOR UPDATE")

    valid? =
      Enum.all?(attachments, fn a ->
        a.thread_id == message.thread_id and a.user_id == user.id and a.status == "pending" and
          is_nil(a.message_id) and DateTime.after?(a.expires_at, now)
      end)

    if length(attachments) != length(ids) or not valid?,
      do: Repo.rollback({:invalid_field, :attachment_ids})

    for {id, position} <- Enum.with_index(ids) do
      attachment = Enum.find(attachments, &(&1.id == id))
      update!(attachment, status: "attached", message_id: message.id, position: position)
    end

    :ok
  end

  @doc "Deletes expired staging and orphaned objects, retaining rows when the storage delete fails."
  def cleanup do
    ids = cleanup_query() |> select([a], a.id) |> limit(100) |> Repo.all()
    results = Enum.map(ids, &cleanup_one/1)
    if Enum.any?(results, &match?({:error, _}, &1)), do: {:error, :storage_unavailable}, else: :ok
  end

  defp cleanup_one(id) do
    Repo.transaction(fn ->
      attachment = cleanup_query() |> where([a], a.id == ^id) |> lock("FOR UPDATE SKIP LOCKED") |> Repo.one()

      if attachment do
        case Storage.delete_object(attachment.storage_key) do
          {:ok, _} -> Repo.delete!(attachment)
          {:error, :not_found} -> Repo.delete!(attachment)
          {:error, {:unexpected_status, 404, _}} -> Repo.delete!(attachment)
          {:error, _} -> Repo.rollback(:storage_unavailable)
        end
      end
    end)
  end

  defp cleanup_query do
    now = DateTime.utc_now()

    from a in Attachment,
      where:
        a.status == "deleting" or is_nil(a.thread_id) or
          (a.status == "attached" and is_nil(a.message_id)) or
          (a.status in ["uploading", "pending"] and (a.expires_at <= ^now or is_nil(a.user_id))),
      order_by: [asc: a.expires_at, asc: a.id]
  end

  defp mark_for_cleanup(id) do
    Repo.transaction(fn ->
      case Repo.one(from a in Attachment, where: a.id == ^id, lock: "FOR UPDATE") do
        %Attachment{status: "uploading"} = attachment -> delete_later!(attachment)
        _ -> :ok
      end
    end)
  end

  defp delete_later!(attachment) do
    update!(attachment, status: "deleting")
    %{} |> CleanupAttachments.new() |> Oban.insert!()
  end

  defp authorize_locked!(user, thread_id, mode) do
    thread = Repo.one(from t in Thread, where: t.id == ^thread_id, lock: "FOR UPDATE")
    if is_nil(thread) or not Access.can_read?(thread, user), do: Repo.rollback(:not_found)
    if mode == :active and thread.status != "active", do: Repo.rollback(:archived)
    thread
  end

  defp update!(attachment, attrs), do: attachment |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp validate_upload(%{"filename" => filename, "content_type" => content_type, "data" => data} = params) do
    with {:ok, client_id} <- Ecto.UUID.cast(params["client_id"]),
         {:ok, filename} <- filename(filename),
         true <- is_binary(content_type) and byte_size(content_type) <= 127,
         content_type = content_type |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase(),
         true <- Regex.match?(@content_type, content_type),
         true <- is_binary(data) and byte_size(data) <= @max_encoded_bytes,
         {:ok, bytes} <- Base.decode64(data),
         true <- byte_size(bytes) > 0 and byte_size(bytes) <= @max_bytes do
      digest = :crypto.hash(:sha256, :erlang.term_to_binary({filename, content_type, bytes}))

      {:ok,
       %{
         client_id: client_id,
         filename: filename,
         content_type: content_type,
         byte_size: byte_size(bytes),
         payload_digest: digest
       }, bytes}
    else
      _ -> {:error, {:invalid_field, :attachment}}
    end
  end

  defp validate_upload(_params), do: {:error, {:invalid_field, :attachment}}

  defp filename(filename) when is_binary(filename) and byte_size(filename) <= 1024 do
    clean =
      filename
      |> String.replace("\\", "/")
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[\p{Cc}\p{Cf}]/u, "")
      |> String.trim()
      |> String.trim_leading(".")
      |> String.codepoints()
      |> Enum.take(120)
      |> Enum.join()

    if clean == "", do: {:error, :filename}, else: {:ok, clean}
  end

  defp filename(_filename), do: {:error, :filename}
end
