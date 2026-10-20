defmodule AtlasWeb.GTMContactControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  alias Atlas.GTM
  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Workers.DeliverAutomatedEmail

  @token "posthog-destination-token"

  setup :verify_on_exit!

  setup do
    audience =
      %Audience{}
      |> Audience.changeset(%{
        name: "Users",
        slug: "users",
        source_id: "cm0loopslistid"
      })
      |> Atlas.Repo.insert!()

    %{audience: audience}
  end

  defp with_token(conn, token \\ @token) do
    stub(GTM, :email_contact_ingest_token, fn -> @token end)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  # The body is what the PostHog destination sends to Loops' contacts/update.
  defp contact_body(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => "signup@example.com",
        "userId" => "01H8XYZ",
        "firstName" => "Sam",
        "lastName" => "Builder",
        "userGroup" => "developer",
        "source" => "posthog"
      },
      overrides
    )
  end

  test "upserts a contact and queues the welcome email", %{conn: conn} do
    conn = conn |> with_token() |> put(~p"/api/email/contacts/update", contact_body())

    assert %{"success" => true, "created" => true} = json_response(conn, 200)

    subscriber = Audiences.get_subscriber_by_email("signup@example.com")
    assert subscriber.source == "posthog"
    assert subscriber.user_group == "developer"

    delivery = Atlas.Repo.get_by!(Delivery, subscriber_id: subscriber.id, kind: "welcome")
    assert_enqueued(worker: DeliverAutomatedEmail, args: %{"delivery_id" => delivery.id})
  end

  test "accepts POST as well as PUT", %{conn: conn} do
    conn = conn |> with_token() |> post(~p"/api/email/contacts/update", contact_body())

    assert %{"success" => true} = json_response(conn, 200)
  end

  test "subscribes to the audience matching the mailing list id", %{conn: conn, audience: audience} do
    body = contact_body(%{"mailingLists" => %{"cm0loopslistid" => true}})
    conn = conn |> with_token() |> put(~p"/api/email/contacts/update", body)

    assert %{"success" => true} = json_response(conn, 200)

    subscriber = Audiences.get_subscriber_by_email("signup@example.com")
    membership = Atlas.Repo.get_by!(AudienceMembership, audience_id: audience.id, subscriber_id: subscriber.id)
    assert membership.status == "subscribed"
  end

  test "rejects a request without a token", %{conn: conn} do
    stub(GTM, :email_contact_ingest_token, fn -> @token end)

    conn = put(conn, ~p"/api/email/contacts/update", contact_body())

    assert %{"success" => false, "message" => "invalid API key"} = json_response(conn, 401)
    refute Audiences.get_subscriber_by_email("signup@example.com")
  end

  test "rejects a wrong token", %{conn: conn} do
    conn = conn |> with_token("not-the-token") |> put(~p"/api/email/contacts/update", contact_body())

    assert %{"success" => false, "message" => "invalid API key"} = json_response(conn, 401)
    refute Audiences.get_subscriber_by_email("signup@example.com")
  end

  test "refuses to ingest when no token is configured", %{conn: conn} do
    stub(GTM, :email_contact_ingest_token, fn -> nil end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer anything")
      |> put(~p"/api/email/contacts/update", contact_body())

    assert %{"success" => false, "message" => "not configured"} = json_response(conn, 401)
    refute Audiences.get_subscriber_by_email("signup@example.com")
  end

  test "rejects a contact without an email", %{conn: conn} do
    conn = conn |> with_token() |> put(~p"/api/email/contacts/update", %{"firstName" => "Sam"})

    assert %{"success" => false, "message" => "email is required"} = json_response(conn, 400)
  end
end
