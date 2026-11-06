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

  for signal <- ~w(metrics logs traces errors) do
    test "renders #{signal} with organization navigation and escaped telemetry", ctx do
      signal = unquote(signal)
      stub(Pulse, :query, fn _, _, ^signal, _ -> {:ok, result(signal)} end)
      {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/#{signal}")
      html = render_async(view)

      assert has_element?(view, "#pulse[data-signal='#{signal}']")
      assert has_element?(view, "#sidebar-pulse a[href='/#{ctx.account.name}/~/pulse/errors']")
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

      if signal not in ~w(metrics errors) do
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
    view |> form("#pulse-expression-form", pulse: %{query: "{service_name=\"server\"}"}) |> render_submit()
    assert_patch(view, "/#{ctx.account.name}/~/pulse/logs?query=%7Bservice_name%3D%22server%22%7D&range=6h")
    render_async(view)
    assert has_element?(view, "#pulse-table", "{service_name=\"server\"} 6h")
    send(view.pid, :refresh)
    render_async(view)
    assert has_element?(view, "#pulse-table", "{service_name=\"server\"} 6h")
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
    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, "/#{ctx.account.name}/~/pulse/logs")
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

  test "error rows and trends preserve distinct project identity", ctx do
    rows = [issue(), Map.merge(issue(), %{"project" => "tuist/cache", "service" => "cache"})]
    stub(Pulse, :query, fn _, _, "errors", _ -> {:ok, %{result("errors") | rows: rows}} end)
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/errors")
    document = view |> render_async() |> Floki.parse_document!()
    row_ids = document |> Floki.find("#pulse-table tbody tr") |> Floki.attribute("id")
    chart_ids = document |> Floki.find("#pulse-table .noora-chart") |> Floki.attribute("id")
    assert length(Enum.uniq(row_ids)) == 2
    assert length(Enum.uniq(chart_ids)) == 2
    links = document |> Floki.find("#pulse-table [data-part='row-link']") |> Floki.attribute("href")
    assert Enum.map(links, &URI.decode_query(URI.parse(&1).query)["project"]) == ["1", "tuist/cache"]
  end

  test "grouped errors link through issue and occurrence details without losing their window", ctx do
    issue = issue()
    test = self()

    event = %{
      "event_id" => issue["latest_event_id"],
      "timestamp" => issue["last_seen_ns"],
      "service" => "server",
      "project" => "tuist/server",
      "trace_id" => String.duplicate("a", 32),
      "span_id" => String.duplicate("b", 16),
      "title" => "ArgumentError: <script>bad</script>",
      "level" => "error",
      "environment" => "production",
      "release" => "1.2.3",
      "tags" => %{"deployment.region" => "eu-central", "worker" => "<script>tag</script>"},
      "contexts" => %{"runtime" => %{"name" => "Elixir", "version" => "1.20.2", "jit" => true}},
      "extra" => %{"attempt" => 0, "details" => %{"message" => "<script>extra</script>", "retried" => false}},
      "modules" => %{"phoenix" => "1.8.1", "ecto" => "3.13.0"},
      "exception" => %{
        "type" => "ArgumentError",
        "value" => "<script>bad</script>",
        "frames" => [
          %{
            "module" => "MyApp.Worker",
            "function" => "run/1",
            "filename" => "lib/worker.ex",
            "lineno" => 42,
            "in_app" => true
          }
        ]
      }
    }

    event =
      Map.put(event, "exceptions", [
        %{"type" => "RootCause", "value" => "Original cause", "frames" => []},
        event["exception"]
      ])

    stub(Pulse, :query, fn _, _, "errors", _ -> {:ok, result("errors")} end)

    stub(Pulse, :error_issue, fn _, _, id, params ->
      assert id == issue["issue_id"]
      assert params["end_at"] == meta()["end_at"]
      send(test, :issue_loaded)

      {:ok,
       %{
         issue: issue,
         events: [event],
         latest_event: event,
         occurrence_series: [[1_790_000_000, 40], [1_790_000_060, 0], [1_790_000_120, 3]],
         meta: meta(),
         warnings: []
       }}
    end)

    stub(Pulse, :error_event, fn _, _, id, event_id, _ ->
      assert id == issue["issue_id"]
      assert event_id == event["event_id"]
      {:ok, %{event: event, warnings: []}}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/~/pulse/errors")
    html = render_async(view)
    headers = html |> Floki.parse_document!() |> Floki.find("#pulse-table th") |> Enum.map(&Floki.text/1)
    assert Enum.map(headers, &String.trim/1) == ["Issue", "Last seen", "First seen", "Trend", "Events"]
    assert has_element?(view, "#pulse-table [data-part='issue-context']", "error")
    assert has_element?(view, "#pulse-table [data-part='issue-culprit']", "MyApp.Worker.run/1")
    assert has_element?(view, "#pulse-table [title='Elixir'] svg")
    assert has_element?(view, "#pulse-table [title='2026-09-21 14:13:30.123456 UTC']")
    assert has_element?(view, "#pulse-table [data-part='issue-trend'] .noora-chart")
    link = view |> element("#pulse-table a", "<script>not executable</script>") |> render_click()
    {:ok, detail, _} = follow_redirect(link, ctx.conn)
    html = render_async(detail)
    assert_receive :issue_loaded
    assert has_element?(detail, "#pulse-error-back[data-part='back-button']")
    assert has_element?(detail, "[data-part='metadata-grid']", "43")
    assert has_element?(detail, "#pulse-issue-occurrences")
    assert has_element?(detail, "#pulse-stacktrace", "Latest event")
    assert has_element?(detail, "#pulse-stacktrace", "RootCause")
    assert has_element?(detail, "#pulse-stacktrace [data-in-app='true']", "MyApp.Worker.run/1")
    assert has_element?(detail, "#pulse-issue-overview", "Elixir")
    assert has_element?(detail, "#pulse-issue-overview", "First seen in this period")
    assert has_element?(detail, "#pulse-event-tags", "<script>tag</script>")
    assert has_element?(detail, "#pulse-event-contexts", "1.20.2")
    assert has_element?(detail, "#pulse-event-extra code.language-json .boolean", "false")
    assert has_element?(detail, "#pulse-modules-table", "phoenix")
    assert has_element?(detail, "#pulse-stack-frames-0 th", "File")
    refute html =~ "<script>"
    refute has_element?(detail, "[phx-click='resolve']")
    detail |> element("#pulse-error-occurrences-tab") |> render_click()
    render_async(detail)
    refute_received :issue_loaded
    assert has_element?(detail, "#pulse-error-events", event["event_id"])
    link = detail |> element("#pulse-error-events a", "2026-") |> render_click()
    {:ok, occurrence, _} = follow_redirect(link, ctx.conn)
    html = render_async(occurrence)
    assert has_element?(occurrence, "#pulse-stacktrace", "MyApp.Worker")
    assert has_element?(occurrence, "#pulse-stacktrace", "lib/worker.ex:42")
    assert has_element?(occurrence, "#pulse-stacktrace", "RootCause")
    assert has_element?(occurrence, "[data-part='metadata-grid']", event["span_id"])
    assert has_element?(occurrence, "#pulse-event-contexts", "true")
    assert has_element?(occurrence, "#pulse-event-extra code.language-json .string", "<script>extra</script>")
    assert has_element?(occurrence, "#pulse-event-modules", "3.13.0")
    refute html =~ "<script>"
  end

  test "event details distinguish missing exceptions and missing stack frames", ctx do
    event = %{"event_id" => issue()["latest_event_id"], "title" => "Message only", "exceptions" => [], "exception" => %{}}
    stub(Pulse, :error_event, fn _, _, _, _, _ -> {:ok, %{event: event, warnings: []}} end)
    path = "/#{ctx.account.name}/~/pulse/errors/issues/#{issue()["issue_id"]}/events/#{event["event_id"]}"
    {:ok, view, _} = live(ctx.conn, path)
    render_async(view)
    assert has_element?(view, "#pulse-stacktrace", "No exception recorded")
    refute has_element?(view, "#pulse-stacktrace [data-part='stack-frame']")
    refute has_element?(view, "#pulse-event-tags")
    refute has_element?(view, "#pulse-event-contexts")
    refute has_element?(view, "#pulse-event-extra")
    refute has_element?(view, "#pulse-event-modules")
  end

  test "error detail routes remain private and fail visibly", ctx do
    stub(Pulse, :error_issue, fn _, _, _, _ -> {:error, :not_found} end)
    path = "/#{ctx.account.name}/~/pulse/errors/issues/#{issue()["issue_id"]}"
    {:ok, view, _} = live(ctx.conn, path)
    render_async(view)
    assert has_element?(view, "#pulse-detail-error", "not found")

    outsider = AccountsFixtures.user_fixture()
    reject(Pulse, :error_event, 5)

    assert_raise NotFoundError, fn ->
      live(log_in_user(ctx.conn, outsider), path <> "/events/#{issue()["latest_event_id"]}")
    end
  end

  defp chart_data(html) do
    html |> Floki.parse_document!() |> Floki.find("#pulse-chart > [data-part='data']") |> Floki.text() |> Jason.decode!()
  end

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

  defp result("metrics") do
    %{
      rows: [%{"name" => "up", "labels" => %{"service_name" => "server"}, "value" => 2.5}],
      series: [%{"name" => "server", "points" => [[1_790_000_000, 0], [1_790_000_010, "NaN"], [1_790_000_020, 2.5]]}],
      warnings: [],
      meta: meta()
    }
  end

  defp result("errors") do
    %{
      rows: [issue()],
      series: [],
      warnings: ["Example warning"],
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

  defp issue do
    %{
      "issue_id" => "v1_" <> String.duplicate("a", 64),
      "project" => "1",
      "service" => "server",
      "title" => "<script>not executable</script>",
      "level" => "error",
      "platform" => "elixir",
      "culprit" => "MyApp.Worker.run/1",
      "occurrence_series" => [[1_790_000_000, 40], [1_790_000_060, 0], [1_790_000_120, 3]],
      "count" => 43,
      "first_seen_ns" => "1790000000123456789",
      "last_seen_ns" => "1790000010123456789",
      "latest_event_id" => String.duplicate("b", 32)
    }
  end
end
