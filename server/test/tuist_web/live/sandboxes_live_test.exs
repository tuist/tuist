defmodule TuistWeb.SandboxesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes.AmpIntegration
  alias Tuist.Sandboxes.Events
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(name: "sandbox-org", creator: user, preload: [:account])

    conn = conn |> assign(:selected_account, account) |> log_in_user(user)
    %{conn: conn, user: user, account: account}
  end

  defp log_in_with_role(conn, account, role) do
    member = AccountsFixtures.user_fixture()
    {:ok, organization} = Accounts.get_organization_by_id(account.organization_id)
    Accounts.add_user_to_organization(member, organization, role: role)
    conn |> recycle() |> assign(:selected_account, account) |> log_in_user(member)
  end

  describe "feature flag" do
    test "the pages do not exist while the flag is off", %{conn: conn, account: account} do
      stub(FeatureFlags, :sandboxes_enabled?, fn _ -> false end)

      for path <- [
            "/#{account.name}/sandboxes",
            "/#{account.name}/sandboxes/instances"
          ] do
        assert_raise NotFoundError, fn -> live(conn, path) end
      end
    end

    test "the sidebar links to sandboxes only while the flag is on", %{conn: conn, account: account} do
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/members")
      assert html =~ ~s(href="/#{account.name}/sandboxes")

      stub(FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/members")
      refute html =~ ~s(href="/#{account.name}/sandboxes")
    end
  end

  describe "overview" do
    test "offers to connect an agent when the account has no sandboxes", %{conn: conn, account: account} do
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/sandboxes")

      assert html =~ "Run agents in sandboxes"
      assert has_element?(lv, ~s([data-provider="amp"] a[href="/#{account.name}/settings/integrations"]), "Connect")
      assert has_element?(lv, ~s([data-provider="cli"]), "Coming soon")
    end

    test "shows a connected Amp integration", %{conn: conn, account: account} do
      Repo.insert!(%AmpIntegration{account_id: account.id, enabled: true, status: :running})

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes")

      assert has_element?(lv, ~s([data-provider="amp"]), "Connected")
      refute has_element?(lv, ~s([data-provider="amp"] a))
    end

    test "members who cannot manage integrations are told an admin can connect one", %{conn: conn, account: account} do
      conn = log_in_with_role(conn, account, :user)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes")

      assert has_element?(lv, ~s([data-provider="amp"]), "An admin can connect it")
      refute has_element?(lv, ~s([data-provider="amp"] a))
    end

    test "shows the most recent sandboxes and current usage", %{conn: conn, account: account} do
      oldest = sandbox_fixture(account: account, amp_orb_id: "orb-oldest", state: :paused)
      recent = for i <- 1..4, do: sandbox_fixture(account: account, amp_orb_id: "orb-recent-#{i}", state: :paused)
      sandbox_fixture(account: account, amp_orb_id: "orb-active", residency_work_id: "amp:orb-active")
      Repo.update_all(from(s in Sandbox, where: s.id == ^oldest.id), set: [inserted_at: ~U[2026-01-01 00:00:00Z]])

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes")

      assert has_element?(lv, "#sandboxes-recent a[href='/#{account.name}/sandboxes/instances']", "View more")
      assert has_element?(lv, "#sandboxes-recent tbody tr", "orb-active")
      refute has_element?(lv, "#sandbox-#{oldest.id}")
      assert Enum.all?(recent, &has_element?(lv, "#sandbox-#{&1.id}"))
      refute has_element?(lv, "#sandboxes-concurrency-sandboxes")
      refute has_element?(lv, "#sandboxes-providers")
      assert has_element?(lv, "#sandboxes-concurrency-vcpus", "2 of 32 in use now")
      assert has_element?(lv, "#sandboxes-concurrency-disk", "84 GB of 420 GB on nodes now")
    end

    test "charts the account's sandbox history", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, amp_orb_id: "orb-history")
      Events.record(sandbox, "created")
      Events.record(sandbox, "started", Events.boot("disk_snapshot", 1_500))
      Events.record(sandbox_fixture(amp_orb_id: "orb-of-another-account"), "created")

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes")
      render_async(lv)

      assert has_element?(lv, "#widget-sandboxes-created", "1")
      assert has_element?(lv, "#widget-sandboxes-time-to-start", "p50 Time to start")
      refute has_element?(lv, "#widget-sandboxes-time-to-start", "No data yet")
      assert has_element?(lv, "#widget-sandboxes-setup", "No data yet")
      assert has_element?(lv, "#sandboxes-created-chart")

      render_click(lv, "select_widget", %{"widget" => "time_to_start"})
      render_async(lv)

      assert_patch(lv, ~p"/#{account.name}/sandboxes?widget=time_to_start")
      assert has_element?(lv, "#sandboxes-time-to-start-chart")
    end
  end

  describe "instances" do
    test "lists the account's sandboxes", %{conn: conn, account: account} do
      active = sandbox_fixture(account: account, amp_orb_id: "orb-active", residency_work_id: "amp:orb-active")
      paused = sandbox_fixture(account: account, amp_orb_id: "orb-paused", state: :paused, vcpus: 4, memory_mb: 8192)
      archived = sandbox_fixture(account: account, amp_orb_id: "orb-archived", state: :archived, node_name: nil)
      other = sandbox_fixture(amp_orb_id: "orb-of-another-account")

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/instances")

      assert has_element?(lv, "#sandbox-#{active.id}", "orb-active")
      assert has_element?(lv, "#sandbox-#{active.id}", "Active")
      assert has_element?(lv, "#sandbox-#{active.id}", "Amp Orb")
      assert has_element?(lv, "#sandbox-#{paused.id}", "Paused")
      assert has_element?(lv, "#sandbox-#{paused.id}", "4 vCPU · 8 GB RAM · 10 GB disk")
      assert has_element?(lv, "#sandbox-#{archived.id}", "Archived")
      refute has_element?(lv, "#sandbox-#{other.id}")
      refute has_element?(lv, "[data-part='pagination']")
    end

    test "filters sandboxes by status", %{conn: conn, account: account} do
      running = sandbox_fixture(account: account, amp_orb_id: "orb-running")
      failed = sandbox_fixture(account: account, amp_orb_id: "orb-failed", state: :error, error_message: "boom")

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/instances?status=error")

      assert has_element?(lv, "#sandbox-#{failed.id}", "Failed")
      refute has_element?(lv, "#sandbox-#{running.id}")
    end

    test "pages through the sandboxes of a status", %{conn: conn, account: account} do
      start = ~U[2026-01-01 00:00:00Z]

      paused =
        for i <- 1..22 do
          sandbox = sandbox_fixture(account: account, amp_orb_id: "orb-paused-#{i}", state: :paused)
          inserted_at = DateTime.add(start, i, :minute)
          Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id), set: [inserted_at: inserted_at])
          sandbox
        end

      running = sandbox_fixture(account: account, amp_orb_id: "orb-running")
      [oldest, second_oldest | _] = paused

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/instances?status=paused")

      assert has_element?(lv, "[data-part='pagination']", "Page 1 of 2")
      assert has_element?(lv, "#sandbox-#{Enum.at(paused, 2).id}")
      refute has_element?(lv, "#sandbox-#{second_oldest.id}")
      refute has_element?(lv, "#sandbox-#{running.id}")

      lv |> element("[data-part='pagination'] a", "Next") |> render_click()

      assert_patch(lv, ~p"/#{account.name}/sandboxes/instances?page=2&status=paused")
      assert has_element?(lv, "#sandbox-#{oldest.id}")
      assert has_element?(lv, "#sandbox-#{second_oldest.id}")
      refute has_element?(lv, "#sandbox-#{Enum.at(paused, 2).id}")

      assert render(lv) =~ ~s(href="/#{account.name}/sandboxes/instances" data-phx-link="patch")
      assert render(lv) =~ ~s(href="/#{account.name}/sandboxes/instances?status=running")

      render_patch(lv, ~p"/#{account.name}/sandboxes/instances")
      assert has_element?(lv, "#sandbox-#{running.id}")
      assert has_element?(lv, "[data-part='pagination']", "Page 1 of 2")
    end
  end

  describe "sandbox" do
    test "shows the sandbox's details", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, amp_orb_id: "orb-details", state: :error, error_message: "jail died")

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/#{sandbox.id}")

      assert has_element?(lv, "h1", "orb-details")
      assert has_element?(lv, "#sandbox-error", "jail died")
      assert has_element?(lv, "#sandbox-amp-managed")
      assert has_element?(lv, ~s([data-part="back-button"][href="/#{account.name}/sandboxes/instances"]), "Instances")
      assert has_element?(lv, ~s(#sidebar-sandboxes a[href="/#{account.name}/sandboxes/instances"] [data-selected]))
    end

    test "does not show another account's sandbox", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(amp_orb_id: "orb-of-another-account")

      assert_raise NotFoundError, fn -> live(conn, ~p"/#{account.name}/sandboxes/#{sandbox.id}") end
    end

    test "pauses an idle sandbox", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: id}, _opts when id == sandbox.id -> {:ok, %{}} end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/#{sandbox.id}")
      lv |> element("#sandbox-pause") |> render_click()
      render_async(lv, 5_000)

      assert Repo.get!(Sandbox, sandbox.id).state == :paused
      assert has_element?(lv, "h1 + .noora-status-badge", "Paused")
    end

    test "does not offer to pause a sandbox an agent is working in", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, residency_work_id: "amp:orb")

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/#{sandbox.id}")

      refute has_element?(lv, "#sandbox-pause")
      assert has_element?(lv, "#sandbox-delete")
    end

    test "deletes a sandbox", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, amp_orb_id: "orb-delete", node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: id}, _opts when id == sandbox.id -> {:ok, %{}} end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/#{sandbox.id}")
      lv |> element("#sandbox-delete") |> render_click()
      render_click(lv, "delete", %{})

      assert_redirect(lv, ~p"/#{account.name}/sandboxes/instances", 5_000)
      refute Repo.get(Sandbox, sandbox.id)
    end

    test "read-only members cannot manage sandboxes", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account)
      reject(&Nodes.call/4)
      conn = log_in_with_role(conn, account, :viewer)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/sandboxes/#{sandbox.id}")

      refute has_element?(lv, "#sandbox-pause")
      refute has_element?(lv, "#sandbox-delete")
      render_click(lv, "pause", %{})
      render_click(lv, "delete", %{})
      assert Repo.get!(Sandbox, sandbox.id).state == :running
    end
  end
end
