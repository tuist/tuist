defmodule AtlasWeb.DemoLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Demo
  alias Atlas.Demo.DatasetCheck
  alias Atlas.Demo.Seeds
  alias Atlas.Finance
  alias Atlas.Finance.Transaction
  alias Atlas.Notes.Note
  alias Atlas.Repo
  alias Atlas.Tasks.Task
  alias Atlas.Users
  alias Atlas.Users.User

  setup :verify_on_exit!

  setup do
    stub(Demo, :enabled?, fn -> true end)
    :ok
  end

  test "anonymous entry points land directly on fictional accounts", %{conn: conn} do
    Seeds.run!()
    assert conn |> get("/") |> redirected_to() == "/commercial/sales/accounts"
    assert conn |> recycle() |> get("/demo") |> redirected_to() == "/commercial/sales/accounts"
    {:ok, view, _html} = live(build_conn(), "/commercial/sales/accounts")
    assert has_element?(view, "header #demo-badge [data-part='trigger'][tabindex='0']", "Demo")
    assert has_element?(view, "#demo-badge [data-part='content']", "Fictional data. Read-only.")
    refute has_element?(view, "#demo-banner")
    assert has_element?(view, "#accounts-table", "Helio Commerce")
    assert has_element?(view, "header #demo-docs-link[href='https://atlas.tuist.dev/docs']")
    refute has_element?(view, "a[href='/demo']")
    refute has_element?(view, "#atlas-demo")
    refute has_element?(view, "#account-dropdown")
  end

  test "normal deployments do not grant anonymous dashboard access", %{conn: conn} do
    stub(Demo, :enabled?, fn -> false end)
    assert conn |> get("/demo") |> redirected_to() == "/login"
    assert conn |> recycle() |> get("/") |> redirected_to() == "/login"
  end

  test "demo users never have write or administrator scopes" do
    user = Demo.user()
    assert Users.has_scope?(user, "accounts:read")
    refute Users.has_scope?(user, "accounts:write")
    refute Users.admin?(user)
    assert Users.scopes_for(user) == Demo.scopes()
  end

  test "seed data is fictional, coherent, and idempotent" do
    assert {:ok, :seeded} = Seeds.run!()
    assert Repo.aggregate(Account, :count) == 4
    assert Repo.aggregate(Transaction, :count) == 54
    assert Repo.aggregate(Task, :count) == 4
    assert Repo.aggregate(Note, :count) == 2
    overview = Finance.overview()
    assert Decimal.positive?(overview.available_cash_value)
    assert Decimal.positive?(overview.runway_months)
    assert Enum.any?(Finance.runway_analytics(Finance.runway_window()).values, &match?(%Decimal{}, &1))
    assert {:ok, :seeded} = Seeds.run!()
    assert Repo.aggregate(Account, :count) == 4
    assert Repo.aggregate(Transaction, :count) == 54
    assert Repo.aggregate(User, :count) == 2
    assert Repo.aggregate(Task, :count) == 4
    assert Seeds.verify!() == :ok
  end

  test "seed refuses non-demo records" do
    %User{}
    |> User.changeset(%{email: "real-#{System.unique_integer([:positive])}@example.org", name: "Existing user"})
    |> Repo.insert!()

    assert_raise RuntimeError, ~r/non-demo records/, fn -> Seeds.run!() end
  end

  test "all curated pages render seeded data without a session", %{conn: conn} do
    Seeds.run!()
    account = Repo.get_by!(Account, account_key: "atlas-demo:helio")
    note = Repo.one!(from(n in Note, where: n.title == "Northstar operating principles"))

    handler = "demo-write-probe-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler, [:atlas, :repo, :query], &__MODULE__.capture_write/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    reject(Req, :request, 1)
    reject(Req, :request, 2)

    for path <- [
          "/commercial/sales/accounts",
          "/commercial/sales/accounts/#{account.id}",
          "/tasks",
          "/commercial/finance",
          "/commercial/finance/vendors",
          "/library/notes",
          "/library/notes/#{note.id}"
        ] do
      {:ok, view, _html} = live(conn, path)
      render_async(view)
      assert has_element?(view, "header #demo-badge [data-part='trigger']", "Demo")
      refute has_element?(view, "#demo-banner")
    end

    {:ok, finance, _html} = live(conn, "/commercial/finance")
    render_hook(finance, "select_overview_widget", %{"widget" => "runway"})

    render_hook(finance, "runway_period_changed", %{
      "value" => %{"start" => "", "end" => ""},
      "preset" => "last-6-months"
    })

    {:ok, vendors, _html} = live(conn, "/commercial/finance/vendors")
    render_hook(vendors, "search_expenses", %{"expenses_search" => %{"query" => "Nimbus"}})
    refute_received {:demo_write, _query}
  end

  def capture_write(_event, _measurements, %{query: query}, test_pid) do
    belongs_to_test? = self() == test_pid or test_pid in Process.get(:"$callers", [])

    if belongs_to_test? and Regex.match?(~r/^\s*(INSERT|UPDATE|DELETE|TRUNCATE)|FOR UPDATE/i, query) do
      send(test_pid, {:demo_write, query})
    end
  end

  test "curated pages render browsing controls without write affordances", %{conn: conn} do
    Seeds.run!()
    account = Repo.get_by!(Account, account_key: "atlas-demo:helio")
    note = Repo.one!(from(n in Note, where: n.title == "Northstar operating principles"))

    for {path, browsing_control, write_controls} <- [
          {"/commercial/sales/accounts", "#accounts-search-form", "#new-account-button, #new-account-form"},
          {"/commercial/sales/accounts/#{account.id}", "#account-contacts-list",
           "#account-actions-dropdown, #edit-account-button, #refresh-overview-summary-button, #contact-form, #edit-billing-form, #term-form, #timeline-note-form, [data-part='contact-action'], [data-part='term-actions-cell']"},
          {"/tasks", "#tasks-search-form", "#add-task-button, #task-form, [id^='task-actions-']"},
          {"/library/notes", "#notes-search-form", "#notes-new-button"},
          {"/library/notes/#{note.id}", "#note-preview", "#note-form, #note-content, #note-save-button"}
        ] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, browsing_control)
      refute has_element?(view, write_controls)
      refute has_element?(view, "form[phx-submit]:not([phx-submit='search'])")
    end

    assert account.contacts_count == 1
  end

  test "account search works but forged mutations do not", %{conn: conn} do
    Seeds.run!()
    account = Repo.get_by!(Account, account_key: "atlas-demo:helio")
    {:ok, list, _html} = live(conn, "/commercial/sales/accounts")
    render_change(list, "search", %{"search" => %{"query" => "Helio"}})
    assert_patch(list)
    assert has_element?(list, "#accounts", "Helio Commerce")
    refute has_element?(list, "#accounts", "Orbit Mobility")
    count = Repo.aggregate(Account, :count)
    render_hook(list, "create_account", %{"account" => %{"name" => "Forged account"}})
    assert Repo.aggregate(Account, :count) == count

    {:ok, detail, _html} = live(conn, "/commercial/sales/accounts/#{account.id}")
    render_hook(detail, "save_account", %{"account" => %{"name" => "Changed"}})
    render_hook(detail, "delete_account", %{})
    render_hook(detail, "refresh_overview_summary", %{})
    assert Repo.get!(Account, account.id).name == "Helio Commerce"
    assert has_element?(detail, "#flash-info", "read-only demo")
  end

  test "task and note mutations, including unknown events, fail closed", %{conn: conn} do
    Seeds.run!()
    task = Repo.one!(from(t in Task, limit: 1))
    {:ok, view, _html} = live(conn, "/tasks")
    render_hook(view, "complete", %{"id" => task.id})
    render_hook(view, "save", %{"task" => %{"title" => "Forged"}})
    render_hook(view, "future_mutation", %{})
    assert Repo.get!(Task, task.id).status == "open"
    assert Repo.aggregate(Task, :count) == 4

    note = Repo.one!(from(n in Note, limit: 1))
    {:ok, view, _html} = live(conn, "/library/notes/#{note.id}")
    render_hook(view, "save", %{"note" => %{"content" => "Changed"}})
    assert Repo.get!(Note, note.id).content == note.content
  end

  test "API, auth, integrations, admin, downloads, and public write-on-GET routes are blocked", %{conn: conn} do
    for {method, path} <- [
          {:post, "/mcp"},
          {:get, "/mcp"},
          {:post, "/inference/v1/chat/completions"},
          {:post, "/api/slack/events"},
          {:post, "/oauth2/register"},
          {:get, "/oauth2/authorize"},
          {:get, "/admin/users"},
          {:get, "/admin/dashboard"},
          {:get, "/admin/oban"},
          {:get, "/auth/google"},
          {:get, "/mcps/tuist/authorize"},
          {:get, "/email/subscriptions/confirm/token"},
          {:get, "/support/chat/verify/token"},
          {:get, "/p/pocs/token/verify"},
          {:get, "/documents/id/download"},
          {:get, "/library/notes/new"},
          {:post, "/tasks"},
          {:get, "/commercial/sales"}
        ] do
      response = dispatch(conn, @endpoint, method, path)
      assert response.status == 403, "#{method} #{path}"
    end
  end

  test "same-session navigation cannot mount an unreviewed page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/library/notes")
    render_patch(view, "/library/notes/new")
    assert_redirect(view, "/commercial/sales/accounts")
  end

  test "serving refuses an owner credential" do
    assert_raise RuntimeError, ~r/SELECT-only role/, fn -> DatasetCheck.verify_permissions!() end
  end

  test "demo supervisor omits every external execution dependency" do
    assert Atlas.Application.children() == [
             AtlasWeb.Telemetry,
             Atlas.Vault,
             {Atlas.Repo, Demo.repo_options()},
             {Phoenix.PubSub, name: Atlas.PubSub},
             DatasetCheck,
             AtlasWeb.Endpoint
           ]
  end

  test "serving database connections reject writes" do
    config = Repo.config() |> Keyword.take([:username, :password, :hostname, :port, :database])
    connection = start_supervised!({Postgrex, Keyword.merge(config, Demo.repo_options())})
    assert {:ok, %{rows: [["on"]]}} = Postgrex.query(connection, "SHOW default_transaction_read_only", [])

    assert {:error, %Postgrex.Error{postgres: %{code: :read_only_sql_transaction}}} =
             Postgrex.query(connection, "UPDATE users SET name = name", [])
  end
end
