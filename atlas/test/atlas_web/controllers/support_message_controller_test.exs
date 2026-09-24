defmodule AtlasWeb.SupportMessageControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Inbox
  alias Atlas.Inbox.EmailParser
  alias Atlas.Support

  test "renders an original email and its inline image for authenticated users", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    message = support_message_with_inline_image!()

    original_conn = get(conn, ~p"/support/messages/#{message.id}/original")

    assert original_html = response(original_conn, 200)
    assert original_html =~ ~s(src="/support/messages/#{message.id}/attachments?content_id=bank-details%40example.com")

    assert get_resp_header(original_conn, "content-security-policy") == [
             "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'; img-src 'self' data:; style-src 'unsafe-inline'; font-src data:; sandbox allow-same-origin"
           ]

    attachment_conn =
      build_conn()
      |> log_in_user()
      |> elem(0)
      |> get(~p"/support/messages/#{message.id}/attachments?#{[content_id: "bank-details@example.com"]}")

    assert response(attachment_conn, 200) == "image bytes"
    assert get_resp_header(attachment_conn, "content-type") == ["image/png"]
  end

  test "returns not found for a malformed support message identifier", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    assert response(get(conn, "/support/messages/not-a-uuid/original"), 404) == "Original email is unavailable."
  end

  test "downloads duplicate attachment filenames by checksum", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    message = support_message_with_duplicate_attachments!()
    [first, second] = message.metadata["attachments"]

    first_conn = get(conn, ~p"/support/messages/#{message.id}/download?#{[checksum: first["checksum_sha256"]]}")

    second_conn =
      build_conn()
      |> log_in_user()
      |> elem(0)
      |> get(~p"/support/messages/#{message.id}/download?#{[checksum: second["checksum_sha256"]]}")

    assert response(first_conn, 200) == "first report"
    assert response(second_conn, 200) == "second report"
  end

  defp support_message_with_inline_image! do
    suffix = System.unique_integer([:positive])

    raw_email = """
    Message-ID: <support-image-#{suffix}@example.com>
    From: Diana <diana-#{suffix}@example.com>
    To: contact@tuist.dev
    Subject: Bank details
    MIME-Version: 1.0
    Content-Type: multipart/related; boundary=atlas-boundary

    --atlas-boundary
    Content-Type: text/plain; charset=UTF-8

    See the screenshot.
    [cid:bank-details@example.com]
    --atlas-boundary
    Content-Type: text/html; charset=UTF-8

    <p>See the screenshot.</p><img src="cid:bank-details@example.com" alt="Bank details">
    --atlas-boundary
    Content-Type: image/png; name=bank-details.png
    Content-Disposition: inline; filename=bank-details.png
    Content-ID: <bank-details@example.com>
    Content-Transfer-Encoding: base64

    aW1hZ2UgYnl0ZXM=
    --atlas-boundary--
    """

    {:ok, inbox_email} =
      Inbox.persist_inbound(raw_email,
        envelope: %{"from" => "diana-#{suffix}@example.com", "to" => "contact@tuist.dev"}
      )

    {:ok, %{message: message}} = Support.ingest_inbound(EmailParser.parse(raw_email), inbox_email.id)
    message
  end

  defp support_message_with_duplicate_attachments! do
    suffix = System.unique_integer([:positive])

    raw_email = """
    Message-ID: <support-duplicate-#{suffix}@example.com>
    From: Diana <diana-#{suffix}@example.com>
    To: contact@tuist.dev
    Subject: Duplicate files
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary=atlas-boundary

    --atlas-boundary
    Content-Type: text/plain; charset=UTF-8

    Two reports are attached.
    --atlas-boundary
    Content-Type: text/plain; name=report.txt
    Content-Disposition: attachment; filename=report.txt
    Content-Transfer-Encoding: base64

    #{Base.encode64("first report")}
    --atlas-boundary
    Content-Type: text/plain; name=report.txt
    Content-Disposition: attachment; filename=report.txt
    Content-Transfer-Encoding: base64

    #{Base.encode64("second report")}
    --atlas-boundary--
    """

    {:ok, inbox_email} =
      Inbox.persist_inbound(raw_email,
        envelope: %{"from" => "diana-#{suffix}@example.com", "to" => "contact@tuist.dev"}
      )

    {:ok, %{message: message}} = Support.ingest_inbound(EmailParser.parse(raw_email), inbox_email.id)
    message
  end
end
