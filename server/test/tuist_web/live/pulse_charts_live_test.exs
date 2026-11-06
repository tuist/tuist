defmodule TuistWeb.PulseChartsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    account = AccountsFixtures.organization_fixture(creator: user).account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)

    stub(Pulse, :query, fn _, _, _, _ ->
      {:ok, %{rows: [], warnings: [], meta: %{}}}
    end)

    stub(Pulse, :analytics, fn _, _, signal, _ -> {:ok, analytics(signal)} end)
    %{conn: log_in_user(conn, user), path: "/#{account.name}/~/pulse"}
  end

  for signal <- ~w(logs traces errors) do
    test "#{signal} bucket counts default to bars and validate unsupported formats", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path <> "/#{unquote(signal)}?chart_type=scatter")
      [series] = chart_data(render_async(view))["series"]
      assert series["type"] == "bar"
      assert series["data"] == points()
      assert series["connectNulls"] == false
      assert has_element?(view, "[phx-value-type='bar'][data-selected]")
      refute has_element?(view, "[phx-value-type='scatter']")
    end
  end

  test "gauge widgets retain stepped lines and reject bar mode", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path <> "/metrics?widget=healthy&chart_type=bar")
    [series] = chart_data(render_async(view))["series"]
    assert series["type"] == "line"
    assert series["step"] == "end"
    assert series["data"] == points()
    refute has_element?(view, "#pulse-chart-type-controls")
  end

  test "format switches preserve table inputs and reuse full-period analytics", ctx do
    test_pid = self()

    expect(Pulse, :analytics, fn _, _, "traces", %{"range" => "6h"} ->
      send(test_pid, :analytics_loaded)
      {:ok, analytics("traces")}
    end)

    {:ok, view, _} =
      live(
        ctx.conn,
        ctx.path <> "/traces?widget=duration_p95&range=6h&page=2&search=worker&end_at=2026-09-21T14%3A13%3A20Z"
      )

    [series] = chart_data(render_async(view))["series"]
    assert_receive :analytics_loaded
    assert series["type"] == "line"

    view |> element("[phx-value-type='scatter']") |> render_click()
    patch = assert_patch(view)
    params = patch |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["chart_type"] == "scatter"
    assert params["page"] == "2"
    assert params["search"] == "worker"
    assert params["end_at"] == "2026-09-21T14:13:20Z"
    [series] = chart_data(render_async(view))["series"]
    assert series["type"] == "scatter"
    assert series["data"] == points()
    assert has_element?(view, "[data-part='chart-description']", "not an individual span")

    view |> element("[phx-value-widget='spans']") |> render_click()
    patch = assert_patch(view)
    params = patch |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["chart_type"] == "bar"
    [series] = chart_data(render_async(view))["series"]
    assert series["type"] == "bar"

    view |> element("[phx-value-type='line']") |> render_click()
    assert_patch(view)
    [series] = chart_data(render_async(view))["series"]
    assert series["type"] == "line"
    assert series["data"] == points()
    refute_receive :analytics_loaded
  end

  defp chart_data(html) do
    html |> Floki.parse_document!() |> Floki.find("#pulse-chart > [data-part='data']") |> Floki.text() |> Jason.decode!()
  end

  defp points, do: [[1_790_000_000_000, 0], [1_790_000_010_000, nil], [1_790_000_020_000, 12]]

  defp analytics(signal) do
    ids =
      case signal do
        "metrics" -> ~w(reporting healthy unhealthy)
        "logs" -> ~w(entries errors warnings)
        "traces" -> ~w(spans errors duration_p95)
        "errors" -> ~w(events fatal services)
      end

    %{
      warnings: [],
      widgets:
        Enum.map(ids, fn id ->
          %{
            id: id,
            value: 12,
            previous_value: 10,
            unit: if(id == "duration_p95", do: :milliseconds, else: :count),
            points: Enum.map(points(), fn [time, value] -> [div(time, 1000), value] end)
          }
        end)
    }
  end
end
