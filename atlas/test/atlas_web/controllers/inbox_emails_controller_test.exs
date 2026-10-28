defmodule AtlasWeb.InboxEmailsControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Inbox.InboxEmail
  alias Atlas.Inbox.Workers.IngestEmail
  alias Atlas.Repo

  setup :verify_on_exit!

  describe "POST /api/inbox/emails" do
    test "persists the raw email and enqueues the ingest worker", %{conn: conn} do
      raw_email = """
      Message-ID: <controller-123@acme.example>
      From: maya@acme.example
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Please schedule renewal planning.
      """

      conn = post_signed_email(conn, raw_email)

      assert %{"ok" => true, "status" => "queued", "inbox_email_id" => inbox_email_id} =
               json_response(conn, 200)

      inbox_email = Repo.get!(InboxEmail, inbox_email_id)
      assert inbox_email.raw_email == raw_email
      assert inbox_email.status == "pending"
      assert inbox_email.envelope_from == "maya@acme.example"
      assert inbox_email.envelope_to == "inbox@atlas.tuist.dev"

      assert_enqueued(worker: IngestEmail, args: %{"inbox_email_id" => inbox_email_id})
    end

    test "returns 401 for an invalid signature", %{conn: conn} do
      conn =
        conn
        |> put_inbox_secret()
        |> put_req_header("content-type", "message/rfc822")
        |> put_req_header("x-atlas-inbox-timestamp", Integer.to_string(System.system_time(:second)))
        |> put_req_header("x-atlas-inbox-signature", "sha256=invalid")
        |> post(~p"/api/inbox/emails", "Subject: Hello\n\nBody")

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
      assert Repo.aggregate(InboxEmail, :count) == 0
    end

    test "returns 401 for a stale timestamp", %{conn: conn} do
      raw_email = "Subject: Hello\n\nBody"
      timestamp = Integer.to_string(System.system_time(:second) - 301)

      conn =
        conn
        |> put_inbox_secret()
        |> put_req_header("content-type", "message/rfc822")
        |> put_req_header("x-atlas-inbox-timestamp", timestamp)
        |> put_req_header("x-atlas-inbox-signature", sign(raw_email, timestamp))
        |> post(~p"/api/inbox/emails", raw_email)

      assert json_response(conn, 401) == %{"error" => "stale timestamp"}
      assert Repo.aggregate(InboxEmail, :count) == 0
    end

    test "returns 401 when the secret is not configured", %{conn: conn} do
      raw_email = "Subject: Hello\n\nBody"
      timestamp = Integer.to_string(System.system_time(:second))

      conn =
        conn
        |> Plug.Conn.put_private(:atlas_inbox_webhook_secret, nil)
        |> put_req_header("content-type", "message/rfc822")
        |> put_req_header("x-atlas-inbox-timestamp", timestamp)
        |> put_req_header("x-atlas-inbox-signature", sign(raw_email, timestamp))
        |> post(~p"/api/inbox/emails", raw_email)

      assert json_response(conn, 401) == %{"error" => "not configured"}
      assert Repo.aggregate(InboxEmail, :count) == 0
    end
  end

  defp post_signed_email(conn, raw_email, envelope_from \\ "maya@acme.example") do
    timestamp = Integer.to_string(System.system_time(:second))

    conn
    |> put_inbox_secret()
    |> put_req_header("content-type", "message/rfc822")
    |> put_req_header("x-atlas-inbox-timestamp", timestamp)
    |> put_req_header("x-atlas-inbox-signature", sign(raw_email, timestamp))
    |> put_req_header("x-atlas-inbox-envelope-from", envelope_from)
    |> put_req_header("x-atlas-inbox-envelope-to", "inbox@atlas.tuist.dev")
    |> post(~p"/api/inbox/emails", raw_email)
  end

  defp sign(body, timestamp) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, "inbox-secret", [timestamp, ".", body]) |> Base.encode16(case: :lower))
  end

  defp put_inbox_secret(conn) do
    Plug.Conn.put_private(conn, :atlas_inbox_webhook_secret, "inbox-secret")
  end
end
