defmodule TuistWeb.OpsRegistryLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Registry
  alias Tuist.Registry.Swift.SyncWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)
    stub(Accounts, :tuist_operator?, fn _ -> true end)

    %{conn: conn}
  end

  test "lists and searches Swift packages", %{conn: conn} do
    stub(Registry, :list_swift_packages, fn ->
      {:ok,
       [
         package("apple", "swift-argument-parser"),
         package("pointfreeco", "swift-composable-architecture")
       ]}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry")
    render_async(live_view)

    assert has_element?(live_view, "#ops-registry-packages-table", "swift-argument-parser")
    assert has_element?(live_view, "#ops-registry-packages-table", "swift-composable-architecture")

    live_view
    |> form("form[phx-submit='search']", %{search: "pointfreeco"})
    |> render_change()

    assert has_element?(live_view, "#ops-registry-packages-table", "swift-composable-architecture")
    refute has_element?(live_view, "#ops-registry-packages-table", "swift-argument-parser")
  end

  test "links packages to their version detail page", %{conn: conn} do
    stub(Registry, :list_swift_packages, fn ->
      {:ok, [package("apple", "swift-argument-parser")]}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry")
    render_async(live_view)

    assert has_element?(
             live_view,
             "a[href='/ops/registry/apple/swift-argument-parser']",
             "swift-argument-parser"
           )
  end

  test "lists and searches package versions", %{conn: conn} do
    stub(Registry, :get_swift_package, fn "apple", "swift-argument-parser" ->
      {:ok,
       package("apple", "swift-argument-parser", [
         version("2.0.0", :available, "def456"),
         version("1.2.3", :available, "abc123"),
         version("1.0.0", :skipped, "missing_manifests")
       ])}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry/apple/swift-argument-parser")
    render_async(live_view)

    assert has_element?(live_view, "#ops-registry-versions-table", "2.0.0")
    assert has_element?(live_view, "#ops-registry-versions-table", "abc123")
    assert has_element?(live_view, "#ops-registry-versions-table", "Missing manifests")

    live_view
    |> form("form[phx-submit='search']", %{search: "1.2"})
    |> render_change()

    assert has_element?(live_view, "#ops-registry-versions-table", "1.2.3")
    refute has_element?(live_view, "#ops-registry-versions-table", "2.0.0")
    refute has_element?(live_view, "#ops-registry-versions-table", "1.0.0")
  end

  test "queues a resync for one package version", %{conn: conn} do
    stub(Registry, :get_swift_package, fn "apple", "swift-argument-parser" ->
      {:ok,
       package("apple", "swift-argument-parser", [
         version("1.2.3", :available, "abc123")
       ])}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry/apple/swift-argument-parser")
    render_async(live_view)

    live_view
    |> element("button[phx-value-version='1.2.3']")
    |> render_click()

    assert_enqueued(
      worker: SyncWorker,
      args: %{
        "force" => true,
        "repository_full_handle" => "apple/swift-argument-parser",
        "version" => "1.2.3"
      }
    )
  end

  test "rejects a resync for a version that is not on the page", %{conn: conn} do
    stub(Registry, :get_swift_package, fn "apple", "swift-argument-parser" ->
      {:ok,
       package("apple", "swift-argument-parser", [
         version("1.2.3", :available, "abc123")
       ])}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry/apple/swift-argument-parser")
    render_async(live_view)

    render_click(live_view, "force_resync", %{"version" => "2.0.0"})

    refute_enqueued(worker: SyncWorker)
  end

  test "paginates the package catalog", %{conn: conn} do
    stub(Registry, :list_swift_packages, fn ->
      {:ok, Enum.map(1..31, &package("owner", "package-#{&1}"))}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry")
    render_async(live_view)

    assert has_element?(live_view, "a[href*='page=2'][data-part='page-button']")
  end

  test "shows an error when the package catalog cannot be loaded", %{conn: conn} do
    stub(Registry, :list_swift_packages, fn -> {:error, :timeout} end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry")
    render_async(live_view)

    assert has_element?(live_view, "#ops-registry-packages-table", "Could not load packages")
  end

  test "shows an error when package metadata cannot be loaded", %{conn: conn} do
    stub(Registry, :get_swift_package, fn "apple", "swift-argument-parser" ->
      {:error, :timeout}
    end)

    {:ok, live_view, _html} = live(conn, ~p"/ops/registry/apple/swift-argument-parser")
    render_async(live_view)

    assert has_element?(live_view, "#ops-registry-versions-table", "Could not load package")
  end

  defp package(scope, name, versions \\ []) do
    %{
      scope: scope,
      name: name,
      repository_full_handle: "#{scope}/#{name}",
      versions: versions
    }
  end

  defp version(version, status, detail) do
    %{version: version, status: status, detail: detail}
  end
end
