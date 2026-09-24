defmodule AtlasWeb.LicensesLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Audit.Activity
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Repo
  alias AtlasWeb.LicensesLive

  test "renders customer licenses for executives", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "licenses@example.com", role: :executive})
    customer = insert_account!(%{name: "Acme Labs", primary_domain: "acme.example"})
    license = insert_license!(customer, %{key: "ACME-ONLINE-KEY"})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses")

    assert has_element?(view, "#licenses")
    assert has_element?(view, "#new-license-button")
    assert has_element?(view, "#licenses-table")

    assert has_element?(
             view,
             "#license-key-#{license.id}[title='ACME-ONLINE-KEY']",
             "ACME-ONLINE-KEY"
           )

    assert has_element?(
             view,
             "#copy-license-key-#{license.id}[data-copy-value='ACME-ONLINE-KEY']"
           )

    assert has_element?(view, "#license-status-#{license.id}", "Active")
    assert has_element?(view, "#license-actions-#{license.id}-button")

    assert has_element?(view, "#license-actions-#{license.id}-content-portal")

    assert has_element?(
             view,
             "#license-account-link-#{license.id}[href='/commercial/sales/accounts/#{customer.id}']"
           )

    assert has_element?(view, ~s(a[href="/commercial/sales/licenses"]), "Licenses")
  end

  test "renders the license empty state with styled semantic parts", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "licenses-empty@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses")

    assert has_element?(view, "#licenses-empty-state > [data-part='icon'][aria-hidden='true']")
    assert has_element?(view, "#licenses-empty-state > [data-part='title']", "No matching licenses")

    assert has_element?(
             view,
             "#licenses-empty-state > [data-part='subtitle']",
             "Adjust the filters or create a customer license from this page."
           )

    refute has_element?(view, "#licenses-table")
  end

  test "creates a license connected to a customer account", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "license-create@example.com", role: :executive})
    customer = insert_account!(%{name: "New Customer"})
    expires_on = Date.utc_today() |> Date.add(180)

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses")

    render_submit(view, "create_license", %{
      "license" => %{"account_id" => customer.id, "expires_on" => Date.to_iso8601(expires_on)}
    })

    license = Repo.one!(License)
    assert has_element?(view, "#license-key-#{license.id}", license.key)
    assert has_element?(view, "#licenses-table", "New Customer")

    activity = Repo.get_by!(Activity, action: "license.created", target_id: license.id)
    assert activity.actor_id == user.id
    assert activity.interface == "dashboard"
  end

  test "extends an existing license", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "license-extend@example.com", role: :executive})
    customer = insert_account!(%{name: "Renewing Customer"})
    license = insert_license!(customer, %{})
    new_expiration_date = Date.add(license.expires_on, 365)

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses")

    view
    |> element("#license-actions-#{license.id}-button")
    |> render_click()

    render_submit(view, "extend_license", %{
      "extension" => %{"expires_on" => Date.to_iso8601(new_expiration_date)}
    })

    assert Repo.get!(License, license.id).expires_on == new_expiration_date
    assert has_element?(view, "#licenses-table", Calendar.strftime(new_expiration_date, "%b %-d, %Y"))

    activity = Repo.get_by!(Activity, action: "license.extended", target_id: license.id)
    assert activity.actor_id == user.id
    assert activity.interface == "dashboard"
  end

  test "only offers customer and POC accounts in the create form", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-options@example.com", role: :executive})
    customer = insert_account!(%{name: "Customer Option"})
    poc = insert_account!(%{name: "POC Option", segment: :prospect, deal_stage: "poc"})
    prospect = insert_account!(%{name: "Prospect Option", segment: :prospect, deal_stage: "discovery"})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses")

    html = render(view)
    assert html =~ ~s(data-value="#{customer.id}")
    assert html =~ ~s(data-value="#{poc.id}")
    refute html =~ ~s(data-value="#{prospect.id}")
  end

  test "disambiguates customer accounts with the same name by domain", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-duplicate-options@example.com", role: :executive})
    first = insert_account!(%{name: "Acme", primary_domain: "first.example"})
    second = insert_account!(%{name: "Acme", primary_domain: "second.example"})

    {:ok, _view, _html} = live(conn, ~p"/commercial/sales/licenses")

    assert LicensesLive.customer_option_label(first) == "Acme (first.example)"
    assert LicensesLive.customer_option_label(second) == "Acme (second.example)"
  end

  test "disambiguates domainless customers and uses the labels in customer filters", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-domainless-options@example.com", role: :executive})
    first = insert_account!(%{name: "Acme", account_key: "account:acme-first"})
    second = insert_account!(%{name: "Acme", account_key: "account:acme-second"})

    assert LicensesLive.customer_option_label(first) == "Acme (account:acme-first)"
    assert LicensesLive.customer_option_label(second) == "Acme (account:acme-second)"

    params = %{"filter_customer_op" => "==", "filter_customer_val" => first.id}
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses?#{params}")

    assert has_element?(
             view,
             "#filter-customer-value-dropdown [data-value='#{first.id}'][data-label='Acme (account:acme-first)']"
           )

    assert has_element?(
             view,
             "#filter-customer-value-dropdown [data-value='#{second.id}'][data-label='Acme (account:acme-second)']"
           )
  end

  test "filters licenses by customer and status", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-filter@example.com", role: :executive})
    first_customer = insert_account!(%{name: "Filtered Customer"})
    second_customer = insert_account!(%{name: "Other Customer"})
    matching_license = insert_license!(first_customer, %{key: "FILTERED-KEY"})
    other_license = insert_license!(second_customer, %{key: "OTHER-KEY"})

    params = %{
      "filter_customer_op" => "==",
      "filter_customer_val" => first_customer.id,
      "filter_status_op" => "==",
      "filter_status_val" => "active"
    }

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses?#{params}")

    assert has_element?(view, "#licenses-active-filters")
    assert has_element?(view, "#license-key-#{matching_license.id}")
    refute has_element?(view, "#license-key-#{other_license.id}")
  end

  test "searches and sorts licenses by their connected accounts", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-sort@example.com", role: :executive})
    alpha = insert_account!(%{name: "Alpha Customer", primary_domain: "alpha.example"})
    zulu = insert_account!(%{name: "Zulu Customer", primary_domain: "zulu.example"})
    alpha_license = insert_license!(alpha, %{key: "ALPHA-KEY"})
    zulu_license = insert_license!(zulu, %{key: "ZULU-KEY"})

    {:ok, sorted_view, _html} =
      live(conn, ~p"/commercial/sales/licenses?#{%{"sort-by" => "customer", "sort-order" => "asc"}}")

    assert has_element?(
             sorted_view,
             "#licenses-table-body > tr:first-child #license-key-#{alpha_license.id}"
           )

    {:ok, searched_view, _html} = live(conn, ~p"/commercial/sales/licenses?#{%{"q" => "zulu.example"}}")

    assert has_element?(searched_view, "#license-key-#{zulu_license.id}")
    refute has_element?(searched_view, "#license-key-#{alpha_license.id}")
  end

  test "paginates matching licenses without losing filters or sorting", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-pagination@example.com", role: :executive})
    customer = insert_account!(%{name: "Paginated Customer", primary_domain: "pages.example"})

    for index <- 1..25 do
      insert_license!(customer, %{
        key: "PAGE-#{index}",
        expires_on: Date.utc_today() |> Date.add(100)
      })
    end

    last_license =
      insert_license!(customer, %{
        key: "LAST-PAGE-KEY",
        expires_on: Date.utc_today() |> Date.add(200)
      })

    params = %{"q" => "pages.example", "sort-by" => "expires_on", "sort-order" => "asc"}
    {:ok, first_page, _html} = live(conn, ~p"/commercial/sales/licenses?#{params}")

    assert has_element?(first_page, "#licenses-pagination")
    refute has_element?(first_page, "#license-key-#{last_license.id}")

    {:ok, second_page, _html} = live(conn, ~p"/commercial/sales/licenses?#{Map.put(params, "page", 2)}")

    assert has_element?(second_page, "#license-key-#{last_license.id}")
  end

  test "clamps an out-of-range page to the last page with results", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-page-clamp@example.com", role: :executive})
    customer = insert_account!(%{name: "Clamp Customer"})

    for index <- 1..25 do
      insert_license!(customer, %{
        key: "CLAMP-PAGE-#{index}",
        expires_on: Date.add(Date.utc_today(), 100)
      })
    end

    last_license =
      insert_license!(customer, %{
        key: "CLAMP-LAST-PAGE",
        expires_on: Date.add(Date.utc_today(), 200)
      })

    assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/commercial/sales/licenses?page=999")
    assert path == ~p"/commercial/sales/licenses?page=2"

    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, "#license-key-#{last_license.id}")
    refute has_element?(view, "#licenses-empty-state")
  end

  test "renders accessible search, action, and clipboard feedback controls", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-accessibility@example.com", role: :executive})
    customer = insert_account!(%{name: "Accessible Customer"})
    license = insert_license!(customer, %{})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/licenses")

    assert has_element?(view, "#licenses-search[aria-label='Search licenses']")

    assert has_element?(
             view,
             "[data-part='license-actions'][data-trigger-label='More actions for Accessible Customer']"
           )

    assert has_element?(view, "#copy-license-status-#{license.id}[aria-live='polite']")
  end

  test "redirects employees away from licenses", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-employee@example.com", role: :employee})

    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/commercial/sales/licenses")
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Customer",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_license!(customer, attrs) do
    defaults = %{
      key: "ONLINE-KEY",
      signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
      expires_on: Date.utc_today() |> Date.add(365)
    }

    attrs = Map.merge(defaults, attrs)
    attrs = Map.put(attrs, :key_hash, Issuer.key_hash(Map.fetch!(attrs, :key)))

    %License{account_id: customer.id}
    |> License.issued_changeset(attrs)
    |> Repo.insert!()
  end
end
