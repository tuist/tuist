defmodule AtlasWeb.GTMSubscriptionControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias AtlasWeb.SubscriptionRateLimit

  test "queues a digest confirmation", %{conn: conn} do
    %Audience{}
    |> Audience.changeset(%{name: "Email Digest", slug: "email-digest"})
    |> Atlas.Repo.insert!()

    conn = post(conn, ~p"/api/email/subscriptions", %{email: "web-reader@example.com", first_name: "Web"})

    assert %{"ok" => true, "status" => "confirmation_queued"} = json_response(conn, 202)
    subscriber = Audiences.get_subscriber_by_email("web-reader@example.com")
    assert subscriber.status == "pending"
    assert subscriber.source == "email-digest"
  end

  test "rejects an invalid confirmation link", %{conn: conn} do
    conn = get(conn, ~p"/email/subscriptions/confirm/not-a-token")
    assert html_response(conn, 422) =~ "confirmation link is invalid"
  end

  test "refuses a request that exceeds the rate limit", %{conn: conn} do
    %Audience{}
    |> Audience.changeset(%{name: "Email Digest", slug: "email-digest"})
    |> Atlas.Repo.insert!()

    stub(SubscriptionRateLimit, :check, fn _ip, _email -> {:error, 42} end)

    conn = post(conn, ~p"/api/email/subscriptions", %{email: "flooder@example.com"})

    assert %{"ok" => false, "error" => "too many requests"} = json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") == ["42"]
    # Nothing is created and no confirmation email is queued.
    refute Audiences.get_subscriber_by_email("flooder@example.com")
  end

  test "does not let a caller pick their own rate limit bucket", %{conn: conn} do
    %Audience{}
    |> Audience.changeset(%{name: "Email Digest", slug: "email-digest"})
    |> Atlas.Repo.insert!()

    stub(SubscriptionRateLimit, :check, fn ip, _email ->
      send(self(), {:rate_limit_ip, ip})
      :ok
    end)

    conn
    |> put_req_header("x-forwarded-for", "1.2.3.4, 203.0.113.7")
    |> post(~p"/api/email/subscriptions", %{email: "forwarded@example.com"})

    # 1.2.3.4 is whatever the caller sent; rotating it must not hand them a
    # fresh bucket, so the limit keys off what the proxy observed.
    assert_received {:rate_limit_ip, "203.0.113.7"}
  end
end
