defmodule AtlasWeb.AcquisitionLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Mimic
  import Phoenix.LiveViewTest

  alias Atlas.TuistAcquisition

  @render_async_timeout 1_000

  setup :set_mimic_from_context
  setup :verify_on_exit!

  defp funnel(source) do
    channels = [
      %{
        source: "chatgpt.com",
        medium: "",
        campaign: "hub",
        content: "ad-42",
        landings: 1200,
        signups: 30,
        customers: 3
      },
      %{source: "", medium: "", campaign: "", content: "", landings: 0, signups: 90, customers: 6}
    ]

    channels = if source, do: Enum.filter(channels, &(&1.source == source)), else: channels
    series = [{~D[2026-09-01], 1}, {~D[2026-09-02], 2}]

    {:ok,
     %{
       granularity: :day,
       channels: channels,
       totals: %{landings: 1200, signups: 120, attributed_signups: 30, customers: 9},
       previous: %{landings: 1000, signups: 0, attributed_signups: 30, customers: 9},
       sources: ["chatgpt.com", "newsletter"],
       campaigns: [
         %{campaign: "hub", sources: ["chatgpt.com"], ads: ["ad-42"], landings: 1200, signups: 30, customers: 3}
       ],
       effectiveness: %{
         signup_rate: 0.025,
         customer_rate: 0.1,
         landings_per_customer: 400.0,
         median_days_to_subscribe: 2,
         mean_days_to_subscribe: 2.0,
         plans: %{"enterprise" => 1},
         first_active_on: ~D[2026-09-01],
         last_active_on: ~D[2026-09-02],
         top_source: "chatgpt.com",
         top_ad: "ad-42"
       },
       subscriptions: [
         %{
           account: "acme-mobile",
           plan: "enterprise",
           status: "past_due",
           subscribed_on: ~D[2026-09-03],
           signed_up_on: ~D[2026-09-01],
           source: "chatgpt.com",
           medium: "",
           campaign: "hub",
           content: "ad-42"
         }
       ],
       series: %{landings: series, signups: series, attributed_signups: series, customers: series}
     }}
  end

  test "renders the funnel totals, chart and channels", %{conn: conn} do
    stub(TuistAcquisition, :funnel, fn _range, opts -> funnel(opts[:source]) end)
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition")
    render_async(view, @render_async_timeout)

    assert has_element?(view, "#acquisition-widget-landings [data-part='value']", "1,200")
    assert has_element?(view, "#acquisition-widget-signups [data-part='value']", "120")
    assert has_element?(view, "#acquisition-widget-attributed-signups [data-part='value']", "30")
    assert has_element?(view, "#acquisition-widget-customers [data-part='value']", "9")
    assert has_element?(view, "[id^='acquisition-chart-landings-']")
    assert has_element?(view, "#acquisition-channels-table", "chatgpt.com")
    assert has_element?(view, "#acquisition-channels-table", "Direct or unknown")
    assert has_element?(view, "#acquisition-widget-landings", "20")
    assert has_element?(view, "#acquisition-source-label-portal", "Any")
    assert has_element?(view, "#acquisition-subscriptions-table", "acme-mobile")
    assert has_element?(view, "#acquisition-subscriptions-table", "ad-42")
    assert has_element?(view, "#acquisition-subscriptions-table", "Past due")
  end

  test "filters by source from the URL and clears the filter", %{conn: conn} do
    test_pid = self()

    stub(TuistAcquisition, :funnel, fn _range, opts ->
      send(test_pid, {:source, opts[:source]})
      funnel(opts[:source])
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition?source=chatgpt.com")
    render_async(view, @render_async_timeout)

    assert_received {:source, "chatgpt.com"}
    assert has_element?(view, "#acquisition-source-label-portal", "chatgpt.com")
    refute has_element?(view, "#acquisition-channels-table", "Direct or unknown")

    # Noora renders dropdown items in a portal template, which selectors do not reach.
    items = view |> element("#acquisition-source-content-portal") |> render()
    assert items =~ "source=newsletter"

    render_patch(view, ~p"/commercial/gtm/acquisition?source=newsletter")
    render_async(view, @render_async_timeout)
    assert_received {:source, "newsletter"}

    render_patch(view, ~p"/commercial/gtm/acquisition")
    render_async(view, @render_async_timeout)
    assert_received {:source, nil}
  end

  test "searches, filters and sorts the tables through the URL", %{conn: conn} do
    stub(TuistAcquisition, :funnel, fn _range, opts -> funnel(opts[:source]) end)
    {conn, _user} = log_in_user(conn)

    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition?channels_q=chatgpt")
    render_async(view, @render_async_timeout)
    assert has_element?(view, "#acquisition-channels-table", "chatgpt.com")
    refute has_element?(view, "#acquisition-channels-table", "Direct or unknown")

    view
    |> form("#acquisition-channels-search-form", table_search: %{table: "channels", query: "nothing"})
    |> render_change()

    assert_patch(view, ~p"/commercial/gtm/acquisition?channels_q=nothing")

    {:ok, view, _html} =
      live(conn, ~p"/commercial/gtm/acquisition?filter_subscriptions_plan_op===&filter_subscriptions_plan_val=pro")

    render_async(view, @render_async_timeout)
    assert has_element?(view, "#acquisition-subscriptions-active-filters")
    refute has_element?(view, "#acquisition-subscriptions-table", "acme-mobile")

    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition?channels_sort_by=landings&channels_sort_order=asc")
    render_async(view, @render_async_timeout)
    html = view |> element("#acquisition-channels-table") |> render()
    assert :binary.match(html, "Direct or unknown") < :binary.match(html, "chatgpt.com")
  end

  test "lists campaigns and opens a campaign's page with its effectiveness", %{conn: conn} do
    test_pid = self()

    stub(TuistAcquisition, :funnel, fn _range, opts ->
      send(test_pid, {:campaign, opts[:campaign]})
      funnel(opts[:source])
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition")
    render_async(view, @render_async_timeout)
    assert_received {:campaign, nil}
    assert has_element?(view, "#acquisition-campaigns-table", "hub")

    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition/campaigns/hub?range=last-90-days")
    render_async(view, @render_async_timeout)
    assert_received {:campaign, "hub"}
    assert has_element?(view, "#acquisition-campaign-title", "hub")
    assert has_element?(view, "#acquisition-effectiveness-signup-rate", "2.5%")
    assert has_element?(view, "#acquisition-effectiveness-top-ad", "ad-42")
    refute has_element?(view, "#acquisition-campaigns-table")
  end

  test "caps a custom range at a year", %{conn: conn} do
    test_pid = self()

    stub(TuistAcquisition, :funnel, fn range, opts ->
      send(test_pid, {:range, range})
      funnel(opts[:source])
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition?range=custom&start=2020-01-01&end=2026-09-30")
    render_async(view, @render_async_timeout)

    assert_received {:range, {~D[2025-09-30], ~D[2026-09-30]}}
  end

  test "paginates subscriptions and goes back to the first page when the search changes", %{conn: conn} do
    stub(TuistAcquisition, :funnel, fn _range, opts ->
      {:ok, funnel} = funnel(opts[:source])
      [subscription] = funnel.subscriptions

      subscriptions =
        for index <- 1..45 do
          %{subscription | account: "account-#{String.pad_leading("#{index}", 2, "0")}"}
        end

      {:ok, %{funnel | subscriptions: subscriptions}}
    end)

    {conn, _user} = log_in_user(conn)

    for path <- [~p"/commercial/gtm/acquisition", ~p"/commercial/gtm/acquisition/campaigns/hub"] do
      {:ok, view, _html} = live(conn, path <> "?subscriptions_sort_by=subscribed_on")
      render_async(view, @render_async_timeout)

      assert has_element?(view, "#acquisition-subscriptions-table", "account-01")
      refute has_element?(view, "#acquisition-subscriptions-table", "account-21")
      assert has_element?(view, "#acquisition-subscriptions-pagination")

      render_patch(view, path <> "?subscriptions_sort_by=subscribed_on&subscriptions_page=3")
      assert has_element?(view, "#acquisition-subscriptions-table", "account-45")
      refute has_element?(view, "#acquisition-subscriptions-table", "account-01")

      view
      |> form("#acquisition-subscriptions-search-form", table_search: %{table: "subscriptions", query: "account-0"})
      |> render_change()

      assert_patch(view, path <> "?subscriptions_q=account-0&subscriptions_sort_by=subscribed_on")
      refute has_element?(view, "#acquisition-subscriptions-pagination")
    end
  end

  test "says when the Tuist server is not connected", %{conn: conn} do
    stub(TuistAcquisition, :funnel, fn _range, _opts -> {:error, :not_configured} end)
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/acquisition")
    render_async(view, @render_async_timeout)

    assert has_element?(view, "#acquisition-widget-landings", "Not connected")
    assert has_element?(view, "#acquisition-channels-table", "Not connected")
  end
end
