defmodule AtlasWeb.GTMTransactionalControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Ecto.Query

  alias Atlas.GTM
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Workers.DeliverAutomatedEmail

  @token "marketing-site-token"
  @loops_template_id "cmfglb1pe5esq2w0ixnkdou94"
  @verification_url "https://tuist.dev/newsletter/verify?token=abc123"

  setup :verify_on_exit!

  defp with_token(conn, token \\ @token) do
    stub(GTM, :email_contact_ingest_token, fn -> @token end)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  # Exactly the body Tuist.Loops.send_transactional_email/3 posts today.
  defp loops_body(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => "reader@example.com",
        "transactionalId" => @loops_template_id,
        "dataVariables" => %{"verificationUrl" => @verification_url}
      },
      overrides
    )
  end

  test "queues the newsletter confirmation from the Loops-shaped body", %{conn: conn} do
    conn = conn |> with_token() |> post(~p"/api/email/transactional", loops_body())

    assert %{"success" => true, "duplicate" => false, "id" => id} = json_response(conn, 200)

    delivery = Atlas.Repo.get!(Delivery, id)
    assert delivery.kind == "transactional"
    assert delivery.recipient_email == "reader@example.com"
    assert_enqueued(worker: DeliverAutomatedEmail, args: %{"delivery_id" => id})
  end

  test "reports a repeat submission as a duplicate without queuing twice", %{conn: conn} do
    first = build_conn() |> with_token() |> post(~p"/api/email/transactional", loops_body())
    assert %{"success" => true, "duplicate" => false, "id" => id} = json_response(first, 200)

    second = conn |> with_token() |> post(~p"/api/email/transactional", loops_body())
    assert %{"success" => true, "duplicate" => true, "id" => ^id} = json_response(second, 200)

    assert Atlas.Repo.aggregate(from(d in Delivery, where: d.kind == "transactional"), :count) == 1
  end

  test "rejects an unknown transactional id", %{conn: conn} do
    body = loops_body(%{"transactionalId" => "not-a-template"})
    conn = conn |> with_token() |> post(~p"/api/email/transactional", body)

    assert %{"success" => false, "message" => "unknown transactionalId"} = json_response(conn, 404)
  end

  test "rejects a missing data variable", %{conn: conn} do
    body = loops_body(%{"dataVariables" => %{}})
    conn = conn |> with_token() |> post(~p"/api/email/transactional", body)

    assert %{"success" => false, "message" => message} = json_response(conn, 400)
    assert message =~ "verificationUrl"
  end

  test "rejects a missing email", %{conn: conn} do
    body = loops_body() |> Map.delete("email")
    conn = conn |> with_token() |> post(~p"/api/email/transactional", body)

    assert %{"success" => false, "message" => "email is required"} = json_response(conn, 400)
  end

  test "rejects a wrong token", %{conn: conn} do
    conn = conn |> with_token("not-the-token") |> post(~p"/api/email/transactional", loops_body())

    assert %{"success" => false, "message" => "invalid API key"} = json_response(conn, 401)
    assert Atlas.Repo.aggregate(from(d in Delivery, where: d.kind == "transactional"), :count) == 0
  end

  test "refuses to send when no token is configured", %{conn: conn} do
    stub(GTM, :email_contact_ingest_token, fn -> nil end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer anything")
      |> post(~p"/api/email/transactional", loops_body())

    assert %{"success" => false, "message" => "not configured"} = json_response(conn, 401)
  end
end
