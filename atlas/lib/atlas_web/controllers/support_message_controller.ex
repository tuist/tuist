defmodule AtlasWeb.SupportMessageController do
  use AtlasWeb, :controller

  alias Atlas.Inbox.EmailParser
  alias Atlas.Support
  alias Atlas.Support.Attachments

  @original_email_content_security_policy "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'; img-src 'self' data:; style-src 'unsafe-inline'; font-src data:; sandbox allow-same-origin"

  def original(conn, %{"message_id" => message_id}) do
    case Support.get_inbound_message(message_id) do
      %{inbox_email: %{raw_email: raw_email}} = message when is_binary(raw_email) ->
        html =
          EmailParser.original_html(raw_email, fn content_id ->
            ~p"/support/messages/#{message.id}/attachments?#{[content_id: content_id]}"
          end)

        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("content-security-policy", @original_email_content_security_policy)
        |> put_resp_header("referrer-policy", "no-referrer")
        |> send_resp(200, html)

      _message ->
        conn
        |> put_status(:not_found)
        |> text("Original email is unavailable.")
    end
  end

  def attachment(conn, %{"message_id" => message_id, "content_id" => content_id}) do
    with %{inbox_email: %{raw_email: raw_email}} <- Support.get_inbound_message(message_id),
         %{body: body, content_type: content_type, filename: filename} <-
           EmailParser.inline_attachment(raw_email, content_id) do
      conn
      |> put_resp_content_type(safe_content_type(content_type), nil)
      |> put_resp_header("content-disposition", ~s(inline; filename="#{safe_filename(filename)}"))
      |> put_resp_header("content-security-policy", "sandbox")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, body)
    else
      _reason ->
        conn
        |> put_status(:not_found)
        |> text("Inline attachment is unavailable.")
    end
  end

  def download(conn, %{"message_id" => message_id, "checksum" => checksum}) do
    message_id
    |> Support.get_message()
    |> downloadable_attachment_by_checksum(checksum)
    |> respond_with_download(conn)
  end

  def download(conn, %{"message_id" => message_id, "filename" => filename}) do
    message_id
    |> Support.get_message()
    |> downloadable_attachment_by_filename(filename)
    |> respond_with_download(conn)
  end

  defp downloadable_attachment_by_checksum(%{kind: "inbound", inbox_email: %{raw_email: raw_email}}, checksum) do
    case EmailParser.attachment_by_checksum(raw_email, checksum) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  defp downloadable_attachment_by_checksum(%{kind: "outbound", metadata: %{"attachments" => attachments}}, checksum) do
    attachments
    |> Enum.find(&(Map.get(&1, "checksum_sha256") == checksum))
    |> load_outbound_attachment()
  end

  defp downloadable_attachment_by_checksum(_message, _checksum), do: {:error, :not_found}

  defp downloadable_attachment_by_filename(%{kind: "inbound", inbox_email: %{raw_email: raw_email}}, filename) do
    case EmailParser.attachment_by_filename(raw_email, filename) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  defp downloadable_attachment_by_filename(%{kind: "outbound", metadata: %{"attachments" => attachments}}, filename) do
    attachments
    |> Enum.find(&(Map.get(&1, "filename") == filename))
    |> load_outbound_attachment()
  end

  defp downloadable_attachment_by_filename(_message, _filename), do: {:error, :not_found}

  defp load_outbound_attachment(nil), do: {:error, :not_found}
  defp load_outbound_attachment(attachment_metadata), do: Attachments.load(attachment_metadata)

  defp respond_with_download({:ok, attachment}, conn), do: send_attachment(conn, attachment, "attachment")
  defp respond_with_download({:error, _reason}, conn), do: not_found(conn)

  defp send_attachment(conn, attachment, disposition) do
    conn
    |> put_resp_content_type(safe_content_type(attachment.content_type), nil)
    |> put_resp_header("content-disposition", ~s(#{disposition}; filename="#{safe_filename(attachment.filename)}"))
    |> put_resp_header("content-security-policy", "sandbox")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, attachment.body)
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Attachment is unavailable.")
  end

  defp safe_filename(filename) do
    filename
    |> to_string()
    |> String.replace(~r/[\r\n"]/, "")
    |> Path.basename()
    |> case do
      "" -> "attachment"
      safe -> safe
    end
  end

  defp safe_content_type(content_type) when is_binary(content_type) do
    if String.match?(content_type, ~r/^[a-z0-9.+-]+\/[a-z0-9.+-]+(?:;\s*charset=[a-z0-9._-]+)?$/i) do
      String.downcase(content_type)
    else
      "application/octet-stream"
    end
  end

  defp safe_content_type(_content_type), do: "application/octet-stream"
end
