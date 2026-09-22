defmodule AtlasWeb.POCLive.PublicTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.POC
  alias Atlas.Users.User
  alias AtlasWeb.POCPublicController

  defp user do
    %User{}
    |> User.changeset(%{
      email: "poc-public-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Owner"
    })
    |> Atlas.Repo.insert!()
  end

  defp account(attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    defaults = %{
      account_key: "account:#{suffix}",
      name: "ExampleCo #{suffix}",
      primary_domain: "flexport.example",
      segment: :prospect
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Atlas.Repo.insert!()
  end

  defp contact!(account, email) do
    %Contact{}
    |> Contact.outreach_changeset(%{
      account_id: account.id,
      full_name: "Contact #{System.unique_integer([:positive])}",
      email: email
    })
    |> Atlas.Repo.insert!()
  end

  defp published_poc(user, account, attrs \\ %{}) do
    defaults = %{
      "account_id" => account.id,
      "title" => "Enterprise evaluation",
      "hosting" => "cloud",
      "summary" => "Two-week evaluation for the mobile platform team.",
      "brand_accent_color" => "#ff5500"
    }

    {:ok, poc} = POCs.create_poc(Map.merge(defaults, attrs), user)
    {:ok, published} = POCs.publish_poc(poc, user)
    published
  end

  defp session_conn(conn, poc, cookie_value) do
    Plug.Test.init_test_session(conn, %{POCPublicController.session_cookie_name(poc) => cookie_value})
  end

  describe "unauthenticated visitor" do
    test "sees the email gate instead of the brief", %{conn: conn} do
      published = published_poc(user(), account())

      {:ok, view, html} = live(conn, ~p"/p/pocs/#{published.public_token}")

      assert html =~ "Access required"
      refute html =~ "Two-week evaluation for the mobile platform team."
      assert has_element?(view, "#poc-access-form")
    end

    test "not-found screen for an unknown token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/p/pocs/#{Ecto.UUID.generate()}")
      assert html =~ "POC not available"
    end

    test "not-found screen for a revoked token", %{conn: conn} do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "Draft"}, user)
      {:ok, published} = POCs.publish_poc(poc, user)
      {:ok, _} = POCs.unpublish_poc(published, user)

      {:ok, _view, html} = live(conn, ~p"/p/pocs/#{published.public_token}")

      assert html =~ "POC not available"
    end
  end

  describe "email gate" do
    test "submitting a domain-matching email creates a pending request and enters waiting state", %{conn: conn} do
      user = user()
      account = account(%{primary_domain: "flexport.example"})
      published = published_poc(user, account)

      {:ok, view, _html} = live(conn, ~p"/p/pocs/#{published.public_token}")

      html =
        view
        |> form("#poc-access-form", %{"access" => %{"email" => "jordan@flexport.example"}})
        |> render_submit()

      assert html =~ "Waiting on the Tuist team"
      assert html =~ "jordan@flexport.example"

      # Request row was created with the entered email.
      [request] = POCs.list_access_requests(POCs.get_poc!(published.id))
      assert request.email == "jordan@flexport.example"
      assert is_nil(request.verified_at)
      assert is_nil(request.approved_at)
    end

    test "submitting a contact email also creates a request", %{conn: conn} do
      user = user()
      account = account(%{primary_domain: "otherdomain.example"})
      contact!(account, "jordan@flexport.example")
      published = published_poc(user, account)

      {:ok, view, _html} = live(conn, ~p"/p/pocs/#{published.public_token}")

      view
      |> form("#poc-access-form", %{"access" => %{"email" => "jordan@flexport.example"}})
      |> render_submit()

      assert [%{email: "jordan@flexport.example"}] =
               POCs.list_access_requests(POCs.get_poc!(published.id))
    end

    test "an unauthorized email does not create a request", %{conn: conn} do
      user = user()
      account = account(%{primary_domain: "flexport.example"})
      published = published_poc(user, account)

      {:ok, view, _html} = live(conn, ~p"/p/pocs/#{published.public_token}")

      view
      |> form("#poc-access-form", %{"access" => %{"email" => "attacker@somewhere.example"}})
      |> render_submit()

      # We deliberately do not leak whether the email was accepted, so we can
      # only verify from the outside that no request was created.
      assert POCs.list_access_requests(POCs.get_poc!(published.id)) == []
    end
  end

  describe "session cookie" do
    test "an approved request replayed via the session cookie unlocks the brief", %{conn: conn} do
      user = user()
      account = account(%{primary_domain: "flexport.example"})
      published = published_poc(user, account)

      {:ok, request, token} =
        POCs.create_access_request(published, "jordan@flexport.example",
          ip: "203.0.113.4",
          user_agent: "curl/8"
        )

      {:ok, _request} = POCs.verify_access_email(request.id, token)
      {:ok, request} = POCs.approve_access_request(request.id, user)

      cookie = POCs.sign_session_cookie(POCs.get_poc!(published.id), request)

      {:ok, _view, html} =
        conn
        |> session_conn(published, cookie)
        |> live(~p"/p/pocs/#{published.public_token}")

      assert html =~ "Two-week evaluation for the mobile platform team."
      assert html =~ "Proof of Concept"
    end

    test "a revoked request is not accepted even if the cookie is still signed", %{conn: conn} do
      user = user()
      account = account(%{primary_domain: "flexport.example"})
      published = published_poc(user, account)

      {:ok, request, token} =
        POCs.create_access_request(published, "jordan@flexport.example", ip: nil, user_agent: nil)

      {:ok, _request} = POCs.verify_access_email(request.id, token)
      {:ok, request} = POCs.approve_access_request(request.id, user)
      cookie = POCs.sign_session_cookie(POCs.get_poc!(published.id), request)
      {:ok, _revoked} = POCs.revoke_access_request(request.id, user)

      {:ok, _view, html} =
        conn
        |> session_conn(published, cookie)
        |> live(~p"/p/pocs/#{published.public_token}")

      assert html =~ "Access required"
      refute html =~ "Two-week evaluation for the mobile platform team."
    end
  end

  describe "authorized_email?/2" do
    test "matches the account's primary domain and existing contacts, case-insensitive" do
      account = account(%{primary_domain: "Flexport.Example"})
      contact!(account, "riley@ally.example")
      poc = %POC{account: account}

      assert POCs.authorized_email?(poc, "Jordan@flexport.example")
      assert POCs.authorized_email?(poc, "RILEY@ally.example")
      refute POCs.authorized_email?(poc, "stranger@nowhere.example")
    end
  end
end
