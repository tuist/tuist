defmodule TuistWeb.UsageLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  setup :set_mimic_from_context

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "usage-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  defp enable_kura(account) do
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
  end

  defp insert_event(attrs) do
    base = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      project_id: 0,
      node_id: "kura-test",
      region: "us-east-1",
      traffic_plane: "public",
      direction: "egress",
      operation: "download",
      protocol: "http",
      artifact_kind: "xcframework",
      bytes: 0,
      request_count: 0,
      window_start: NaiveDateTime.utc_now(:second),
      window_seconds: 3_600,
      inserted_at: NaiveDateTime.utc_now(:second)
    }

    IngestRepo.insert_all(UsageEvent, [Map.merge(base, attrs)])
  end

  describe "Kura feature flag gate" do
    test "raises 404 when Kura is not enabled for the account", %{conn: conn, account: account} do
      stub(Environment, :dev?, fn -> false end)

      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        live(conn, ~p"/#{account.name}/usage")
      end
    end

    test "renders the page when Kura is enabled", %{conn: conn, account: account} do
      enable_kura(account)

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Usage"
      assert html =~ "Cache traffic"
      assert html =~ "Egress"
      assert html =~ "Ingress"
      assert html =~ "Requests"
    end
  end

  describe "rendering" do
    setup %{account: account} do
      enable_kura(account)
      :ok
    end

    test "shows the subtitle and project + date filters", %{conn: conn, account: account} do
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Traffic and request volume served by Tuist Cache"
      assert html =~ "Project:"
      assert html =~ "Last 30 days"
    end

    test "shows the empty state when there's no Kura traffic", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render_async(lv, @render_async_timeout)

      assert html =~ "No cache traffic in this window yet"
    end

    test "renders the per-node table when events exist", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account: account, name: "ios")

      insert_event(%{
        account_id: account.id,
        node_id: "kura-test-node",
        bytes: 1_000_000,
        request_count: 5,
        window_start: NaiveDateTime.utc_now(:second)
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render_async(lv, @render_async_timeout)

      assert html =~ "kura-test-node"
      # 1 MB rendered through ByteFormatter
      assert html =~ "MB"
    end
  end

  describe "widget switching" do
    # Each widget renders an `empty` variant (no `phx-value-widget` attribute)
    # when its bytes/count is zero, so seed at least one event of each kind so
    # the click wrappers always render in this describe block.
    setup %{account: account} do
      enable_kura(account)

      insert_event(%{account_id: account.id, direction: "egress", bytes: 1_000, request_count: 1})
      insert_event(%{account_id: account.id, direction: "ingress", bytes: 500, request_count: 1})

      :ok
    end

    test "egress is the default selected widget", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      _ = render_async(lv, @render_async_timeout)
      assert has_element?(lv, ~s|[phx-value-widget="egress"][data-selected]|)
    end

    test "clicking a widget patches the URL with ?widget=ingress", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      _ = render_async(lv, @render_async_timeout)

      lv
      |> element(~s|[phx-value-widget="ingress"]|)
      |> render_click()

      assert_patch(lv, ~p"/#{account.name}/usage?widget=ingress")
      assert has_element?(lv, ~s|[phx-value-widget="ingress"][data-selected]|)
    end

    test "honors widget=requests in the URL on initial mount", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage?widget=requests")

      _ = render_async(lv, @render_async_timeout)
      assert has_element?(lv, ~s|[phx-value-widget="requests"][data-selected]|)
    end

    test "ignores an unknown widget param and falls back to egress", %{
      conn: conn,
      account: account
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage?widget=bogus")

      _ = render_async(lv, @render_async_timeout)
      assert has_element?(lv, ~s|[phx-value-widget="egress"][data-selected]|)
    end
  end
end
