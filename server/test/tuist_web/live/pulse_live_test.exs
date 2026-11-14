defmodule TuistWeb.PulseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    account = organization.account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    stub(Pulse, :analytics, fn _, _, signal, _ -> {:ok, analytics(signal)} end)
    %{conn: log_in_user(conn, user), user: user, account: account, organization: organization}
  end

  test "logs and traces offer literal text search, metrics PromQL", ctx do
    stub(Pulse, :query, fn _, _, signal, _ -> {:ok, result(signal)} end)

    for {signal, language, default} <- [
          {"logs", "Text search (* for all)", "*"},
          {"traces", "Text search (* for all)", "*"},
          {"metrics", "PromQL", "up"}
        ] do
      {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/#{signal}")
      render_async(view)
      assert has_element?(view, "#pulse-toggle-query", language)
      view |> element("#pulse-toggle-query") |> render_click()
      assert has_element?(view, "#pulse-expression[value='#{default}']")
    end
  end

  for signal <- ~w(metrics logs traces) do
    test "renders #{signal} with organization navigation and escaped telemetry", ctx do
      signal = unquote(signal)
      stub(Pulse, :query, fn _, _, ^signal, _ -> {:ok, result(signal)} end)
      {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/#{signal}")
      html = render_async(view)

      assert has_element?(view, "#pulse[data-signal='#{signal}']")
      assert has_element?(view, "#sidebar-pulse a[href='/#{ctx.account.name}/~/pulse/traces']")
      refute has_element?(view, "#sidebar-pulse a[href='/#{ctx.account.name}/~/pulse/errors']")
      assert has_element?(view, "#pulse-table", "server")

      assert has_element?(
               view,
               "#pulse-results [data-part='table-section'] > [data-part='table-toolbar'] #pulse-query-form"
             )

      assert has_element?(view, "[data-part='table-toolbar'] ~ #pulse-table")
      assert has_element?(view, "#pulse-sort-by")
      assert has_element?(view, "#pulse-filter-dropdown")
      assert has_element?(view, "#pulse-query[placeholder='Search...']")
      refute has_element?(view, "label[for='pulse-query']")
      refute has_element?(view, "#pulse-run-query")
      refute html =~ "<script>"

      assert has_element?(view, "#pulse-analytics + #pulse-results")

      for widget <- analytics(signal).widgets do
        assert has_element?(view, "#pulse-widget-#{widget.id}")
        assert has_element?(view, "#pulse-widget-#{widget.id}", "vs previous hour")
      end

      refute has_element?(view, "#pulse-refresh")
      assert length(Floki.find(Floki.parse_document!(html), "#pulse-analytics .tuist-widget")) == 3
      [series] = chart_data(html)["series"]
      assert series["data"] == [[1_790_000_000_000, 0], [1_790_000_010_000, nil], [1_790_000_020_000, 12]]
      assert series["connectNulls"] == false

      if signal != "metrics" do
        assert has_element?(view, "#pulse-table", "2026-")
        if signal != "traces", do: assert(has_element?(view, "#pulse-table", "<script>not executable</script>"))
      end
    end
  end

  test "query and range survive URL patches and refresh", ctx do
    stub(Pulse, :query, fn _, _, "logs", params ->
      row = result("logs").rows |> hd() |> Map.put("message", params["query"] <> " " <> params["range"])
      {:ok, %{result("logs") | rows: [row]}}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs")
    render_async(view)
    render_patch(view, "/#{ctx.account.name}/~/pulse/logs?range=6h")
    render_async(view)
    view |> element("#pulse-toggle-query") |> render_click()
    view |> form("#pulse-expression-form", pulse: %{query: "timeout"}) |> render_submit()
    assert_patch(view, "/#{ctx.account.name}/~/pulse/logs?query=timeout&range=6h")
    render_async(view)
    assert has_element?(view, "#pulse-table", "timeout 6h")
    send(view.pid, :refresh)
    render_async(view)
    assert has_element?(view, "#pulse-table", "timeout 6h")
  end

  test "table search and widget selection reuse analytics; period and refresh reload it", ctx do
    test = self()
    stub(Pulse, :query, fn _, _, signal, _ -> {:ok, result(signal)} end)

    stub(Pulse, :analytics, fn _, _, signal, params ->
      send(test, {:analytics_range, params["range"]})
      {:ok, analytics(signal)}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/traces")
    render_async(view)
    assert_receive {:analytics_range, "1h"}
    view |> element("[phx-value-widget='duration_p95']") |> render_click()
    render_async(view)
    assert has_element?(view, "#pulse-analytics[data-widget='duration_p95']")
    assert has_element?(view, "#pulse-widget-duration_p95", "187.5 ms")
    assert hd(chart_data(render(view))["series"])["name"] == "p95 span duration"
    view |> form("#pulse-query-form", pulse: %{search: "request"}) |> render_change()
    render_async(view)
    refute_received {:analytics_range, _}
    assert has_element?(view, "#pulse-analytics[data-widget='duration_p95']")

    render_patch(view, "/#{ctx.account.name}/~/pulse/traces?range=6h&widget=duration_p95")
    render_async(view)
    assert_receive {:analytics_range, "6h"}
    send(view.pid, :refresh)
    render_async(view)
    assert_receive {:analytics_range, "6h"}
  end

  test "refresh retains content and respects a widget selected during the load", ctx do
    test = self()
    stub(Pulse, :query, fn _, _, signal, _ -> {:ok, result(signal)} end)
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/traces")
    render_async(view)

    stub(Pulse, :analytics, fn _, _, signal, _ ->
      send(test, {:refreshing, self()})

      receive do
        :continue -> {:ok, analytics(signal)}
      end
    end)

    send(view.pid, :refresh)
    assert_receive {:refreshing, worker}
    assert has_element?(view, "#pulse-analytics[data-state='refreshing'] #pulse-chart")
    assert has_element?(view, "#pulse-table", "server")
    send(view.pid, :refresh)
    render(view)
    refute_receive {:refreshing, _}
    view |> element("[phx-value-widget='duration_p95']") |> render_click()
    assert has_element?(view, "#pulse-analytics[data-widget='duration_p95'] #pulse-chart")
    send(worker, :continue)
    render_async(view)
    assert has_element?(view, "#pulse-analytics[data-state='ready'][data-widget='duration_p95']")
  end

  test "analytics failure is independent of searchable rows and recovers on period change", ctx do
    stub(Pulse, :query, fn _, _, signal, _ -> {:ok, result(signal)} end)

    stub(Pulse, :analytics, fn _, _, _, params ->
      if params["range"] == "6h", do: {:ok, analytics("logs")}, else: {:error, :unavailable}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs")
    render_async(view)
    assert has_element?(view, "#pulse-analytics[data-state='failed']")
    assert has_element?(view, "#pulse-table", "server")
    assert has_element?(view, "#pulse-query-form")
    render_patch(view, "/#{ctx.account.name}/~/pulse/logs?range=6h")
    render_async(view)
    assert has_element?(view, "#pulse-analytics[data-state='ready'] #pulse-chart")
  end

  test "missing analytics stay unavailable while measured zero remains charted", ctx do
    stub(Pulse, :query, fn _, _, signal, _ -> {:ok, result(signal)} end)

    stub(Pulse, :analytics, fn _, _, signal, _ ->
      data = analytics(signal)
      [first | rest] = data.widgets
      {:ok, %{data | widgets: [%{first | value: nil, points: []} | rest]}}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs?widget=invalid")
    render_async(view)
    assert has_element?(view, "#pulse-widget-entries", "No data")
    assert has_element?(view, "#pulse-chart-empty")
    view |> element("[phx-value-widget='errors']") |> render_click()
    html = render_async(view)
    assert has_element?(view, "#pulse-widget-errors", "0")
    assert has_element?(view, "#pulse-chart")
    assert hd(hd(chart_data(html)["series"])["data"]) == [1_790_000_000_000, 0]
  end

  test "empty and failed loads are distinct and failed queries can recover", ctx do
    stub(Pulse, :query, fn _, _, _, params ->
      case params["query"] do
        "empty" -> {:ok, %{result("logs") | rows: []}}
        "invalid" -> {:error, :invalid_query}
        _ -> {:ok, result("logs")}
      end
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs?query=empty")
    render_async(view)
    assert has_element?(view, "#pulse-empty")
    refute has_element?(view, "#pulse-error")
    render_patch(view, "/#{ctx.account.name}/~/pulse/logs?query=invalid")
    render_async(view)
    assert has_element?(view, "#pulse-error", "Check your query")
    refute has_element?(view, "#pulse-empty")
    assert has_element?(view, "#pulse-query-form")
    render_patch(view, "/#{ctx.account.name}/~/pulse/logs")
    render_async(view)
    assert has_element?(view, "#pulse-table", "server")
    refute has_element?(view, "#pulse-error")
  end

  test "comparisons preserve missing and zero baselines with inverse duration colors", ctx do
    stub(Pulse, :query, fn _, _, signal, _ -> {:ok, result(signal)} end)

    stub(Pulse, :analytics, fn _, _, signal, _ ->
      data = analytics(signal)
      [spans, errors, duration] = data.widgets

      {:ok,
       %{
         data
         | widgets: [
             %{spans | value: 15, previous_value: 10},
             %{errors | value: 0, previous_value: 0},
             %{duration | value: 12.5, previous_value: 0}
           ]
       }}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/traces?range=15m")
    render_async(view)
    assert has_element?(view, "#pulse-widget-spans [data-color='neutral']", "+50.0%")
    assert has_element?(view, "#pulse-widget-errors", "No change")
    assert has_element?(view, "#pulse-widget-duration_p95 [data-color='destructive']", "+12.5 ms")
    assert has_element?(view, "#pulse-widget-duration_p95", "vs previous 15 minutes")

    stub(Pulse, :analytics, fn _, _, signal, _ ->
      data = analytics(signal)
      {:ok, %{data | widgets: Enum.map(data.widgets, &%{&1 | previous_value: nil})}}
    end)

    send(view.pid, :refresh)
    render_async(view)
    refute has_element?(view, "#pulse-analytics", "vs previous")
  end

  test "public projects do not expose organization telemetry to outsiders", ctx do
    ProjectsFixtures.project_fixture(account: ctx.account, visibility: :public)
    outsider = AccountsFixtures.user_fixture()
    reject(Pulse, :query, 4)

    assert_raise NotFoundError, fn ->
      live(log_in_user(ctx.conn, outsider), "/#{ctx.account.name}/~/pulse/logs")
    end
  end

  test "unenrolled organizations have no Pulse navigation or pages", ctx do
    stub(Environment, :pulse_config, fn -> [] end)
    reject(Pulse, :query, 4)
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/projects")
    refute has_element?(view, "#sidebar-pulse")
    assert_raise NotFoundError, fn -> live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs") end
  end

  test "signed-out visitors must authenticate", ctx do
    conn = Phoenix.ConnTest.build_conn()
    path = "/#{ctx.account.name}/~/pulse/logs"
    assert {:error, {:redirect, %{to: destination}}} = live(conn, path)
    assert destination == ~p"/users/log_in?#{%{return_to: path}}"
  end

  test "automatic refresh rechecks membership", ctx do
    Process.flag(:trap_exit, true)
    stub(Pulse, :query, fn _, _, _, _ -> {:ok, result("logs")} end)
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs")
    render_async(view)
    Accounts.remove_user_from_organization(ctx.user, ctx.organization)

    send(view.pid, :refresh)
    assert {{%NotFoundError{}, _}, _} = catch_exit(render(view))
  end

  test "Pulse routes preserve the pulse project handle", ctx do
    route = Phoenix.Router.route_info(TuistWeb.Router, "GET", "/#{ctx.account.name}/pulse", "localhost")
    assert route.path_params == %{"account_handle" => ctx.account.name, "project_handle" => "pulse"}
  end

  test "table controls preserve a paged snapshot and reuse analytics", ctx do
    test = self()

    stub(Pulse, :query, fn _, _, signal, params ->
      send(test, {:table_inputs, params})
      page = if params["page"] == "2", do: 2, else: 1
      meta = Map.merge(meta(), %{"page" => page, "has_previous_page" => page == 2, "has_next_page" => page == 1})
      {:ok, %{result(signal) | meta: meta}}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/logs?range=6h")
    render_async(view)
    assert_receive {:table_inputs, first}
    view |> element("#pulse-next-page") |> render_click()
    render_async(view)
    assert_receive {:table_inputs, second}
    assert second["range"] == "6h"
    assert second["page"] == "2"
    assert second["end_at"] == meta()["end_at"]
    assert has_element?(view, "#pulse-resume-live")

    send(view.pid, :refresh)
    render_async(view)
    refute_received {:table_inputs, _}

    render_hook(view, "add_filter", %{"value" => "service"})
    render_async(view)
    assert_receive {:table_inputs, _}
    render_hook(view, "update_filter", %{"type" => "change_value", "payload_filter_id" => "service", "value" => "server"})
    render_async(view)
    assert_receive {:table_inputs, filtered}
    assert filtered["service"] == "server"
    assert filtered["service_op"] == "eq"
    refute Map.has_key?(filtered, "page")
    assert has_element?(view, "[data-part='active-filters']", "server")

    view |> element("#pulse-resume-live") |> render_click()
    render_async(view)
    assert_receive {:table_inputs, resumed}
    refute Map.has_key?(resumed, "page")
    assert resumed["end_at"] != second["end_at"]
    refute has_element?(view, "#pulse-resume-live")
    assert first["range"] == resumed["range"]
  end

  test "sort and literal search reset pagination and keep filters", ctx do
    test = self()

    stub(Pulse, :query, fn _, _, signal, params ->
      send(test, {:inputs, params})
      {:ok, result(signal)}
    end)

    {:ok, view, _} =
      live(
        ctx.conn,
        "/#{ctx.account.name}/~/pulse/traces?page=2&filter_service_op=%3D%3D&filter_service_val=server&range=15m"
      )

    render_async(view)
    assert_receive {:inputs, _}

    [sort_path] =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.attribute("#pulse-sort-by-content-portal [data-value='duration_ms']", "href")

    render_patch(view, sort_path)
    render_async(view)
    assert_receive {:inputs, sorted}
    assert sorted["sort_by"] == "duration_ms"
    assert sorted["sort_order"] == "desc"
    assert sorted["service"] == "server"
    refute Map.has_key?(sorted, "page")

    view |> form("#pulse-query-form", pulse: %{search: "a literal request"}) |> render_change()
    render_async(view)
    assert_receive {:inputs, searched}
    assert searched["search"] == "a literal request"
    assert searched["sort_by"] == "duration_ms"
    assert searched["range"] == "15m"
  end

  defp chart_data(html) do
    html |> Floki.parse_document!() |> Floki.find("#pulse-chart > [data-part='data']") |> Floki.text() |> JSON.decode!()
  end

  defp analytics(signal) do
    ids = analytics_ids(signal)

    %{
      warnings: [],
      widgets:
        Enum.with_index(ids, fn id, index ->
          %{
            id: id,
            value: if(id == "duration_p95", do: 187.5, else: if(index == 1, do: 0, else: 724)),
            previous_value: if(id == "duration_p95", do: 250, else: if(index == 1, do: 0, else: 500)),
            unit: if(id == "duration_p95", do: :milliseconds, else: :count),
            points: [[1_790_000_000, 0], [1_790_000_010, nil], [1_790_000_020, 12]]
          }
        end)
    }
  end

  defp analytics_ids("metrics"), do: ~w(reporting healthy unhealthy)
  defp analytics_ids("logs"), do: ~w(entries errors warnings)
  defp analytics_ids("traces"), do: ~w(spans errors duration_p95)

  defp result("metrics") do
    %{
      rows: [%{"name" => "up", "labels" => %{"service_name" => "server"}, "value" => 2.5}],
      series: [%{"name" => "server", "points" => [[1_790_000_000, 0], [1_790_000_010, "NaN"], [1_790_000_020, 2.5]]}],
      warnings: [],
      meta: meta()
    }
  end

  defp result(_signal) do
    %{
      rows: [
        %{
          "timestamp" => "1790000000123456789",
          "service" => "server",
          "level" => "error",
          "message" => "<script>not executable</script>",
          "name" => "GET /api/projects",
          "duration_ms" => 15.5,
          "trace_id" => "abc123"
        }
      ],
      series: [],
      warnings: [],
      meta: meta()
    }
  end

  defp meta do
    %{
      "page" => 1,
      "page_size" => 20,
      "total_count" => 1,
      "total_pages" => 1,
      "end_at" => "2026-09-21T14:13:20Z",
      "has_previous_page" => false,
      "has_next_page" => false
    }
  end
end
