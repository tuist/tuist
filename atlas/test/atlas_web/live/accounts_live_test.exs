defmodule AtlasWeb.AccountsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Term
  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Users.User

  test "renders accounts with row navigation and lifecycle badges", %{conn: conn} do
    user = insert_user!("accounts@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:delivery_hero",
        name: "Acme",
        primary_domain: "deliveryhero.com",
        segment: :customer,
        contacts_count: 2
      })

    insert_account_handle!(account, "deliveryhero-production")

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts?q=deliveryhero-production")

    assert has_element?(view, "#accounts")
    assert has_element?(view, "#accounts-filters-dropdown")

    assert has_element?(
             view,
             ~s(#accounts-table tr[id="#{account.id}"] a[href="/commercial/sales/accounts/#{account.id}"])
           )

    assert has_element?(view, "#accounts-table [data-type='text_and_description'] [data-part='label']", "Acme")
    assert has_element?(view, "#accounts-table", "Lifecycle")
    assert has_element?(view, "#accounts-table", "Customer")
    refute has_element?(view, "#accounts-table", "Sources")
    refute has_element?(view, "[role='tab']")
    refute has_element?(view, "#customers-table")
  end

  test "renders value from the current term when the stored account value is stale", %{conn: conn} do
    user = insert_user!("accounts-term-value@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:term_value",
        name: "Term Value",
        primary_domain: "termvalue.example",
        segment: :customer,
        currency: "EUR",
        current_value: Decimal.new("0")
      })

    %Term{account_id: account.id}
    |> Term.changeset(%{
      source: "atlas",
      payment: "yearly",
      start_date: Date.add(Date.utc_today(), -30),
      end_date: Date.add(Date.utc_today(), 335),
      total: Decimal.new("42000"),
      currency: "EUR"
    })
    |> Repo.insert!()

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts?q=termvalue")

    assert has_element?(view, "#accounts-table tr[id='#{account.id}']", "EUR 42,000.00")
    refute has_element?(view, "#accounts-table tr[id='#{account.id}']", "EUR 0.00")
  end

  test "creates a manual account from the accounts page", %{conn: conn} do
    user = insert_user!("create-account@example.com")
    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts")

    assert has_element?(view, "#new-account-button", "New account")

    assert {:error, {:live_redirect, %{to: account_path}}} =
             render_submit(view, "create_account", %{
               "account" => %{
                 "name" => "Acme Labs",
                 "primary_domain" => "acme.example",
                 "segment" => "lead",
                 "deal_stage" => "discovery",
                 "currency" => "usd",
                 "current_value" => "12000.50",
                 "description" => "Expansion prospect"
               }
             })

    account = Repo.get_by!(Account, name: "Acme Labs")

    assert account_path == "/commercial/sales/accounts/#{account.id}"
    assert account.account_key == "manual:acme-example"
    assert account.primary_domain == "acme.example"
    assert account.segment == :lead
    assert account.deal_stage == "discovery"
    assert account.currency == "USD"
    assert Decimal.equal?(account.current_value, Decimal.new("12000.50"))
    assert account.description == "Expansion prospect"

    activity = Repo.get_by!(Activity, action: "account.created", target_id: account.id)
    assert activity.actor_id == user.id
    assert activity.interface == "dashboard"
    assert activity.metadata["path"] == "/commercial/sales/accounts/#{account.id}"
  end

  test "filters accounts using the shared Noora query-param filters", %{conn: conn} do
    user = insert_user!("filters@example.com")

    customer =
      insert_account!(%{
        account_key: "demo:customer",
        name: "Acme",
        segment: :customer
      })

    lead =
      insert_account!(%{
        account_key: "demo:lead",
        name: "Morgan Stanley",
        segment: :lead
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    filter_params = %{
      "filter_lifecycle_op" => "==",
      "filter_lifecycle_val" => "customer"
    }

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts?#{filter_params}")

    assert has_element?(view, ~s(#accounts-table tr[id="#{customer.id}"]))
    refute has_element?(view, ~s(#accounts-table tr[id="#{lead.id}"]))
    assert has_element?(view, "#lifecycle")
  end

  test "does not render accounts marked as not an account", %{conn: conn} do
    user = insert_user!("non-account-list@example.com")

    account =
      insert_account!(%{
        account_key: "account:grafana",
        name: "Grafana Labs",
        primary_domain: "grafana.com",
        segment: :lead
      })
      |> Account.not_account_changeset(%{reason: "Vendor"}, ~U[2026-06-10 12:00:00Z])
      |> Repo.update!()

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts?q=grafana")

    refute has_element?(view, ~s(#accounts-table tr[id="#{account.id}"]))
  end

  test "sidebar accounts navigation defaults to prospect lifecycle filter", %{conn: conn} do
    user = insert_user!("sidebar@example.com")
    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales")

    assert has_element?(
             view,
             ~s(a[href="/commercial/sales/accounts?filter_lifecycle_op=%3D%3D&filter_lifecycle_val=prospect"]),
             "Accounts"
           )
  end

  defp insert_user!(email) do
    %User{}
    |> User.changeset(%{email: email, name: "Atlas User"})
    |> Repo.insert!()
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_account_handle!(account, handle) do
    %AccountHandle{}
    |> AccountHandle.changeset(%{
      account_id: account.id,
      handle: handle,
      source: "enterprise"
    })
    |> Repo.insert!()
  end
end
