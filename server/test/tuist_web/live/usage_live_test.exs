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
    stub(Environment, :dev?, fn -> false end)
    stub_kura_flag(account, true)
  end

  defp disable_kura(account) do
    stub(Environment, :dev?, fn -> false end)
    # Kura is on by default on non-hosted deployments, so the flag only gates
    # visibility on the hosted server.
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub_kura_flag(account, false)
  end

  defp stub_kura_flag(account, enabled?) do
    account_id = account.id

    stub(FunWithFlags, :enabled?, fn
      :kura, [for: %{id: ^account_id}] -> enabled?
      flag, opts -> Mimic.call_original(FunWithFlags, :enabled?, [flag, opts])
    end)
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
      disable_kura(account)

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

    test "renders the page on the hosted server when the flag is on", %{conn: conn, account: account} do
      # Positive coverage for the hosted branch: tuist_hosted? true disables
      # the `not tuist_hosted?()` disjunct, so the page renders only because
      # the :kura flag is on.
      stub(Environment, :dev?, fn -> false end)
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub_kura_flag(account, true)

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Usage"
    end
  end

  describe "rendering" do
    setup %{account: account} do
      enable_kura(account)
      :ok
    end

    test "shows the subtitle and project + date filters", %{conn: conn, account: account} do
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Runner time and cache traffic billed to this account"
      assert html =~ "Project:"
      assert html =~ "Last 30 days"
    end

    test "shows the empty state when there's no Kura traffic", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render_async(lv, @render_async_timeout)

      assert html =~ "No cache traffic in this window yet"
    end

    test "renders the per-region table when events exist", %{conn: conn, account: account} do
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

      assert html =~ "Traffic by region"
      assert html =~ "us-east-1"
      refute html =~ "kura-test-node"
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

  describe "runner usage receipt" do
    test "walks from minutes to money, showing the allowance as a credit", %{conn: conn, user: user} do
      account = user.account
      started = DateTime.add(DateTime.utc_now(), -2, :hour)

      Tuist.Repo.insert!(%Tuist.Runners.RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 120 * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render(lv)
      assert html =~ "120 minutes run"
      assert html =~ "100 minutes included"
      assert html =~ "Billed this period"
      # The credit reads as money off the bill, not as a bare minute count.
      assert html =~ "−7.50"
      # 20 minutes past the allowance at the standard rate.
      assert html =~ "1.50"
      assert html =~ "On track for about"
    end
  end
end
