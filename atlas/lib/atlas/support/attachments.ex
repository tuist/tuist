defmodule Atlas.Support.Attachments do
  @moduledoc false

  alias Atlas.Documents.Storage
  alias Atlas.Support.Thread

  @max_entries 5
  @max_file_size 5_000_000
  @max_total_size 15_000_000

  def store(%Thread{} = thread, attachments) when is_list(attachments) do
    with :ok <- validate_attachments(attachments) do
      Enum.reduce_while(attachments, {:ok, []}, fn attachment, {:ok, stored} ->
        case store_attachment(thread, attachment) do
          {:ok, metadata} -> {:cont, {:ok, [metadata | stored]}}
          {:error, reason} -> {:halt, {:error, reason, stored}}
        end
      end)
      |> case do
        {:ok, stored} ->
          {:ok, Enum.reverse(stored)}

        {:error, reason, stored} ->
          delete_all(stored)
          {:error, reason}
      end
    end
  end

  def store(_thread, _attachments), do: {:error, :invalid_attachments}

  def load(%{"storage_key" => key} = attachment) when is_binary(key) do
    with {:ok, %{body: body}} <- Storage.get_object(key) do
      {:ok,
       %{
         body: body,
         filename: Map.get(attachment, "filename", "attachment"),
         content_type: Map.get(attachment, "content_type", "application/octet-stream")
       }}
    end
  end

  def load(_attachment), do: {:error, :attachment_unavailable}

  def delete_all(attachments) when is_list(attachments) do
    Enum.each(attachments, fn
      %{"storage_key" => key} when is_binary(key) ->
        _ = Storage.delete_object(key)

      _attachment ->
        :ok
    end)

    :ok
  end

  defp validate_attachments(attachments) do
    total_size = Enum.reduce(attachments, 0, fn attachment, total -> total + attachment_size(attachment) end)

    cond do
      length(attachments) > @max_entries -> {:error, :too_many_attachments}
      total_size > @max_total_size -> {:error, :attachments_too_large}
      Enum.any?(attachments, &(not valid_attachment?(&1))) -> {:error, :invalid_attachment}
      true -> :ok
    end
  end

  defp valid_attachment?(%{filename: filename, content_type: content_type, body: body}) do
    is_binary(filename) and filename != "" and is_binary(content_type) and is_binary(body) and
      byte_size(body) <= @max_file_size
  end

  defp valid_attachment?(_attachment), do: false

  defp attachment_size(%{body: body}) when is_binary(body), do: byte_size(body)
  defp attachment_size(_attachment), do: @max_total_size + 1

  defp store_attachment(thread, %{filename: filename, content_type: content_type, body: body}) do
    filename = safe_filename(filename)
    content_type = safe_content_type(content_type, filename)
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    key = object_key(thread, checksum, filename)

    with {:ok, _response} <- Storage.put_object(key, body, content_type: content_type) do
      {:ok,
       %{
         "storage_bucket" => Storage.bucket(),
         "storage_key" => key,
         "filename" => filename,
         "content_type" => content_type,
         "byte_size" => byte_size(body),
         "checksum_sha256" => checksum
       }}
    end
  end

  defp safe_filename(filename) do
    filename
    |> String.replace(~r/[\r\n"]/, "")
    |> Path.basename()
    |> case do
      "" -> "attachment"
      safe -> safe
    end
  end

  defp safe_content_type(content_type, filename) do
    if String.match?(content_type, ~r/^[a-z0-9.+-]+\/[a-z0-9.+-]+(?:;\s*charset=[a-z0-9._-]+)?$/i) do
      String.downcase(content_type)
    else
      MIME.from_path(filename)
    end
  end

  defp object_key(%Thread{id: thread_id}, checksum, filename) do
    extension = filename |> Path.extname() |> String.downcase()
    "support/#{thread_id}/attachments/#{checksum}-#{Ecto.UUID.generate()}#{extension}"
  end
end
