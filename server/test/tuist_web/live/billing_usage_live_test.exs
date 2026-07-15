defmodule TuistWeb.BillingUsageLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @render_async_timeout 1_000

  setup :set_mimic_from_context

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "billing-usage-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, account: account}
  end

  defp stub_kura_billing_flag(account, enabled?) do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    account_id = account.id

    stub(FunWithFlags, :enabled?, fn
      :kura_billing, [for: %{id: ^account_id}] -> enabled?
      flag, opts -> Mimic.call_original(FunWithFlags, :enabled?, [flag, opts])
    end)
  end

  defp insert_event(attrs) do
    base = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      account_id: Map.fetch!(attrs, :account_id),
      project_id: 0,
      node_id: "kura-test",
      region: "us-east",
      traffic_plane: "public",
      network_path: "public_internet",
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

  test "raises 404 when Kura billing is not enabled for the account", %{conn: conn, account: account} do
    stub_kura_billing_flag(account, false)

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/billing/usage")
    end
  end

  test "renders only billable egress under Billing", %{conn: conn, account: account} do
    stub_kura_billing_flag(account, true)
    current_period_start = Timex.beginning_of_month(DateTime.utc_now())

    insert_event(%{account_id: account.id, bytes: 10_000_000_000})

    insert_event(%{
      account_id: account.id,
      bytes: 20_000_000_000,
      window_start:
        current_period_start
        |> Timex.shift(days: -1)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
    })

    insert_event(%{
      account_id: account.id,
      region: "scw-fr-par-runners",
      network_path: "private_network",
      bytes: 20_000_000
    })

    insert_event(%{
      account_id: account.id,
      direction: "ingress",
      bytes: 30_000_000
    })

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/billing/usage")
    html = html <> render_async(lv, @render_async_timeout)

    assert html =~ "Cache billing"
    assert html =~ "Bill overview"
    assert html =~ "$0.10"
    assert html =~ "Private runner traffic is excluded"
    assert html =~ "Previous cache bill"
    assert html =~ "Estimated next cache bill"
    assert render(element(lv, "#widget-previous-cache-bill")) =~ "$2.00"
    assert render(element(lv, "#widget-cache-cost-to-date")) =~ "$1.00"
    assert has_element?(lv, "#billing-usage-egress-chart")
    assert has_element?(lv, ~s([id="sidebar-billing"]))
    refute has_element?(lv, "#widget-billable-egress")
    refute has_element?(lv, "#widget-ingress")
    refute has_element?(lv, "#widget-requests")
  end

  test "renders an empty state when there is no billable egress", %{conn: conn, account: account} do
    stub_kura_billing_flag(account, true)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing/usage")

    html = render_async(lv, @render_async_timeout)

    assert html =~ "No billable cache downloads this period"
    assert render(element(lv, "#widget-cache-cost-to-date")) =~ "$0.00"
    assert render(element(lv, "#widget-estimated-next-cache-bill")) =~ "$0.00"
  end

  test "builds a cumulative cost chart series" do
    first_date = ~D[2026-07-01]
    second_date = ~D[2026-07-02]

    assert [
             %{
               data: [[^first_date, 1.0], [^second_date, 3.0]],
               name: "Cost to date",
               type: "line"
             }
           ] =
             TuistWeb.BillingUsageLive.chart_series(%{
               dates: [first_date, second_date],
               values: [10_000_000_000, 30_000_000_000]
             })
  end
end
