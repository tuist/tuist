defmodule TuistWeb.MixBuildLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Mix
  alias Tuist.Mix.Build.Buffer
  alias Tuist.Mix.Cache
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Helpers.OpenGraph

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "mixbuild#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(name: "mix-build-org", creator: user, preload: [:account])

    project = ProjectsFixtures.project_fixture(name: "phoenix-app", account_id: account.id, build_system: :mix)

    conn =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    build_id = UUIDv7.generate()

    {:ok, ^build_id} =
      Mix.create_build(%{
        id: build_id,
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 2_000,
        status: "success",
        elixir_version: "1.19.1",
        otp_version: "28",
        mix_env: "dev",
        dependency_cache: [
          Map.merge(cache_event("jason", "local_hit", 500), %{read_bytes: 4_000, read_duration_us: 5_000}),
          Map.merge(cache_event("decimal", "miss"), %{write_bytes: 2_000, write_duration_us: 20_000}),
          cache_event("native", "bypass")
        ],
        git_branch: "feature/elixir-og",
        diagnostics: [
          %{severity: "warning", file: "lib/greeter.ex", module: "Demo.Greeter", message: "unused variable", line: 4},
          %{severity: "warning", file: "lib/greeter.ex", module: "Demo.Greeter", message: "unused alias <b>", line: 9}
        ],
        files: [
          %{
            path: "lib/macros.ex",
            start_offset_ms: 10,
            compile_duration_ms: 1_500,
            wait_duration_ms: 0,
            modules: ["Demo.Macros"],
            waits: []
          },
          %{
            path: "lib/greeter.ex",
            start_offset_ms: 20,
            compile_duration_ms: 70,
            wait_duration_ms: 333,
            modules: ["Demo.Greeter"],
            dependencies: [%{path: "lib/macros.ex", kind: "compile"}],
            waits: [
              %{module: "Demo.Macros", path: "lib/macros.ex", kind: "module", duration_ms: 333, start_offset_ms: 30}
            ]
          }
        ],
        steps: [
          %{
            category: "type_check",
            title: "Type checking Demo.Greeter",
            path: "lib/greeter.ex",
            start_offset_ms: 1_600,
            duration_ms: 25
          }
        ]
      })

    for buffer <- [Buffer, Mix.Diagnostic.Buffer, Mix.CompiledFile.Buffer, Mix.Step.Buffer, Mix.CacheEvent.Buffer],
        do: buffer.flush()

    %{
      conn: conn,
      user: user,
      project: project,
      build_id: build_id,
      path: ~p"/#{organization.account.name}/#{project.name}/builds/mix-builds/#{build_id}",
      timeline_path: ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}/timeline.json"
    }
  end

  @tag :build_environment
  test "Elixir and OTP versions belong to the build environment, not invocation details", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)

    for label <- ["Elixir version", "OTP version"] do
      assert has_element?(view, "#build-environment-content[hidden]", label)
      refute has_element?(view, "[data-part=build-details]", label)
    end

    assert has_element?(view, "#build-environment-content", "1.19.1")
    assert has_element?(view, "#build-environment-content", "28")
    assert has_element?(view, "[data-part=build-details]", "Mix environment")
    assert has_element?(view, "[data-part=build-details]", "mix compile")
    refute has_element?(view, "[data-part=build-details] #build-environment")
  end

  test "uses the shared project card for public Mix builds", %{conn: conn, project: project, path: path} do
    {:ok, _project} = Projects.update_project(project, %{visibility: :public})
    html = conn |> get(path) |> html_response(:ok)
    document = Floki.parse_document!(html)
    [image] = Floki.attribute(document, "meta[property='og:image']", "content")
    assert URI.parse(image).path =~ "/open-graph-images/"
    %{"token" => token} = URI.decode_query(URI.parse(image).query)

    assert {:ok, params} = OpenGraph.verify_image_token(token)
    assert params["template"] == "project"
    assert params["project_id"] == to_string(project.id)
    assert params["project"] == "mix-build-org/phoenix-app"
    assert params["title"] == "mix compile"
    assert params["subtitle"] == "dev · feature/elixir-og"
    assert params["badge"] == "Success"
    assert Floki.attribute(document, "meta[name='twitter:image']", "content") == [image]
  end

  test "uses a failure badge and omits empty build metadata", %{conn: conn, project: project, user: user} do
    {:ok, _project} = Projects.update_project(project, %{visibility: :public})
    build_id = UUIDv7.generate()

    {:ok, ^build_id} =
      Mix.create_build(%{
        id: build_id,
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 500,
        status: "failure"
      })

    Buffer.flush()
    path = ~p"/mix-build-org/#{project.name}/builds/mix-builds/#{build_id}"
    html = conn |> get(path) |> html_response(:ok)
    [image] = html |> Floki.parse_document!() |> Floki.attribute("meta[property='og:image']", "content")
    %{"token" => token} = URI.decode_query(URI.parse(image).query)

    assert {:ok, params} = OpenGraph.verify_image_token(token)
    assert params["title"] == "mix compile"
    assert params["badge"] == "Failure"
    refute Map.has_key?(params, "subtitle")
  end

  test "keeps private Mix build previews generic", %{conn: conn, path: path} do
    html = conn |> get(path) |> html_response(:ok)
    document = Floki.parse_document!(html)

    assert Floki.attribute(document, "meta[property='og:image']", "content") == [
             Tuist.Environment.app_url(path: "/images/open-graph/dashboard/build-runs.png")
           ]
  end

  test "has a Timeline tab backed by the shared build timeline", %{conn: conn, path: path, timeline_path: timeline_path} do
    {:ok, lv, _html} = live(conn, path <> "?tab=timeline")
    render_async(lv, 2_000)

    assert has_element?(lv, "#build-timeline[data-source=mix]")
    assert has_element?(lv, "#build-timeline[data-url='#{timeline_path}']")
    assert has_element?(lv, "[data-part=legend] button[data-kind=setup]", "Type checking")
    assert has_element?(lv, "[data-part=legend] button[data-kind=resource]", "Writing to disk")
    assert has_element?(lv, "[data-part=legend] button[data-kind=script]", "Other compilers")
    refute has_element?(lv, "[data-part=legend] button[data-kind=link]")
    refute has_element?(lv, "[data-part=build-details]")

    tabs =
      lv
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("a.noora-tab-menu-horizontal-item")
      |> Enum.map(&Floki.text/1)

    assert tabs == ["Overview", "Timeline", "Mix cache", "Warnings", "Errors"]

    [version] = lv |> render() |> Floki.parse_document!() |> Floki.attribute("#build-timeline", "data-version")
    render_hook(lv, "load-timeline", %{version: String.to_integer(version)})
    assert has_element?(lv, "#build-timeline")
  end

  test "serves the timeline steps as JSON, without a step for the time a file waited", %{
    conn: conn,
    timeline_path: timeline_path
  } do
    response = conn |> get(timeline_path) |> json_response(200)

    assert Enum.map(response["events"], & &1["category"]) == ["compile", "compile", "compile", "type_check"]
    assert %{"title" => "Type checking Demo.Greeter", "target" => "lib/greeter.ex"} = List.last(response["events"])
    refute Map.has_key?(response, "machine_metrics")
  end

  test "hides the Timeline tab when no file has a recorded start", %{conn: conn, user: user, project: project} do
    build_id = UUIDv7.generate()

    {:ok, ^build_id} =
      Mix.create_build(%{
        id: build_id,
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 500,
        status: "success",
        files: [%{path: "lib/a.ex", compile_duration_ms: 40, modules: ["A"]}]
      })

    for buffer <- [Buffer, Mix.CompiledFile.Buffer], do: buffer.flush()

    {:ok, lv, html} = live(conn, ~p"/mix-build-org/#{project.name}/builds/mix-builds/#{build_id}?tab=timeline")

    refute html =~ "Timeline"
    assert has_element?(lv, "[data-part=build-details]")
  end

  test "shows build details, diagnostics and the file breakdown with the dependency graph", %{conn: conn, path: path} do
    {:ok, lv, html} = live(conn, path)

    assert html =~ "mix compile · Elixir 1.19.1"
    assert html =~ "unused variable"
    assert has_element?(lv, "#mix-breakdown-table")
    assert html =~ "File Breakdown"
    assert html =~ "1.5s"
    # greeter.ex needs macros.ex to compile: one dependency, one dependent.
    table = lv |> element("#mix-breakdown-table") |> render()
    assert table =~ "Compile-time dependencies"
    assert table =~ "Compile-time dependents"

    assert table
           |> Floki.parse_document!()
           |> Floki.find("td")
           |> Enum.count(&(&1 |> Floki.text() |> String.trim() == "1 file")) == 2

    refute table =~ "Waited on"
    refute table =~ "Blocked"
  end

  test "sorts by the dependency graph and switches to modules", %{conn: conn, path: path} do
    # By compile time and by dependents macros.ex leads; by dependencies greeter.ex does.
    {:ok, lv, _html} = live(conn, path)
    table = lv |> element("#mix-breakdown-table") |> render()
    assert position(table, "lib/macros.ex") < position(table, "lib/greeter.ex")

    {:ok, lv, _html} = live(conn, path <> "?breakdown-sort-by=dependents")
    table = lv |> element("#mix-breakdown-table") |> render()
    assert position(table, "lib/macros.ex") < position(table, "lib/greeter.ex")

    {:ok, lv, _html} = live(conn, path <> "?breakdown-sort-by=dependencies")
    table = lv |> element("#mix-breakdown-table") |> render()
    assert position(table, "lib/greeter.ex") < position(table, "lib/macros.ex")

    {:ok, lv, _html} = live(conn, path <> "?breakdown-tab=module")
    table = lv |> element("#mix-breakdown-table") |> render()
    assert table =~ "Demo.Greeter"
    assert table =~ "Demo.Macros"
  end

  test "cache tab has a summary and lookup breakdown with CAS-only expanded rows", context do
    reject(&Mix.compiled_files_page/2)
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")
    html = render_async(view, 5_000)
    assert has_element?(view, "[data-part='cache-summary-card']")
    assert has_element?(view, "#mix-build-cache-widget-hits", "1")
    assert has_element?(view, "#mix-build-cache-widget-misses", "1")
    assert has_element?(view, "#mix-build-cache-widget-hit_rate", "50.0%")
    assert has_element?(view, "#mix-build-cache-widget-read_bytes", "4.0 KB")
    assert has_element?(view, "#mix-build-cache-widget-write_bytes", "2.0 KB")
    refute has_element?(view, "#mix-build-cache-widget-saved_duration_ms")
    assert has_element?(view, "#mix-build-cache-read-latency", "5ms")
    assert has_element?(view, "#mix-build-cache-write-latency", "20ms")
    assert has_element?(view, "a.noora-tab-menu-horizontal-item", "Cacheable Tasks")
    assert has_element?(view, "a.noora-tab-menu-horizontal-item", "CAS Outputs")
    assert has_element?(view, "#mix-build-cache-breakdown-chart")
    assert has_element?(view, "#mix-build-cache-entries", "jason")
    assert has_element?(view, "#mix-build-cache-entries", "Local")
    assert has_element?(view, "#mix-build-cache-entries", "Miss")
    assert has_element?(view, "#mix-build-cache-entries", "Not cached")

    for column <- ["Task", "Hit", "Type", "Cache key"],
        do: assert(has_element?(view, "#mix-build-cache-entries th", column))

    render_click(view, "toggle-cache-entry", %{"dependency" => "native"})
    render_async(view, 5_000)
    render_click(view, "toggle-cache-entry", %{"dependency" => "jason"})
    render_async(view, 5_000)
    refute has_element?(view, "[data-part='cache-entry-details']")
    refute has_element?(view, "#mix-build-cache-entries dl")
    refute html =~ "Bypasses"
    refute has_element?(view, "#mix-breakdown-table")
    refute has_element?(view, "#build-timeline")
  end

  test "cache bars round only the outer edges of nonempty segments", context do
    summary = Cache.build_summary(context.project.id, context.build_id)

    combinations = [
      {{0, 1, 1}, [[0, 0, 0, 0], [6, 0, 0, 6], [0, 6, 6, 0]]},
      {{1, 1, 0}, [[6, 0, 0, 6], [0, 6, 6, 0], [0, 0, 0, 0]]},
      {{1, 0, 1}, [[6, 0, 0, 6], [0, 0, 0, 0], [0, 6, 6, 0]]},
      {{1, 1, 1}, [[6, 0, 0, 6], [0, 0, 0, 0], [0, 6, 6, 0]]},
      {{1, 0, 0}, [[6, 6, 6, 6], [0, 0, 0, 0], [0, 0, 0, 0]]},
      {{0, 1, 0}, [[0, 0, 0, 0], [6, 6, 6, 6], [0, 0, 0, 0]]},
      {{0, 0, 1}, [[0, 0, 0, 0], [0, 0, 0, 0], [6, 6, 6, 6]]}
    ]

    for {{local, remote, misses}, radii} <- combinations do
      stub(Cache, :build_summary, fn _, _ ->
        Map.merge(summary, %{
          local_hits: local,
          remote_hits: remote,
          hits: local + remote,
          misses: misses,
          lookups: local + remote + misses
        })
      end)

      {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")

      chart =
        view
        |> render_async(5_000)
        |> Floki.parse_document!()
        |> Floki.find("#mix-build-cache-breakdown-chart > [data-part='data']")
        |> Floki.text()
        |> JSON.decode!()

      assert Enum.map(chart["series"], & &1["itemStyle"]["borderRadius"]) == radii
    end
  end

  test "expanded output links show loading while the shared query is pending", context do
    owner = self()

    stub(Tuist.ReapiCache, :list_cache_events, fn _, _, _ ->
      send(owner, {:outputs_pending, self()})

      receive do
        :release -> {[], nil}
      end
    end)

    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")
    render_async(view, 5_000)
    render_click(view, "toggle-cache-entry", %{"dependency" => "jason"})
    assert_receive {:outputs_pending, worker}, 5_000
    assert has_element?(view, "[data-part='task-cas-loading']")
    send(worker, :release)
    render_async(view, 5_000)
    refute has_element?(view, "[data-part='task-cas-loading']")
    refute has_element?(view, "[data-part='task-cas-error']")
  end

  test "expanded output failures are visible and retried on re-expansion", context do
    expect(Tuist.ReapiCache, :list_cache_events, fn _, _, _ -> raise "temporary CAS query failure" end)
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")
    render_async(view, 5_000)
    render_click(view, "toggle-cache-entry", %{"dependency" => "jason"})
    render_async(view, 5_000)
    assert has_element?(view, "[data-part='task-cas-error']")
    refute has_element?(view, "[data-part='cache-entry-outputs'] a")
    digest = String.duplicate("b", 64)

    expect(Tuist.ReapiCache, :list_cache_events, fn _, _, _ ->
      {[%{target_label: "jason", action_digest: digest}], nil}
    end)

    render_click(view, "toggle-cache-entry", %{"dependency" => "jason"})
    render_click(view, "toggle-cache-entry", %{"dependency" => "jason"})
    render_async(view, 5_000)
    refute has_element?(view, "[data-part='task-cas-error']")
    assert has_element?(view, "[data-part='cache-entry-outputs'] a[href*='#{digest}']")
  end

  test "cache details load only on the Cache tab", context do
    reject(&Cache.build_summary/2)
    reject(&Cache.build_events/3)
    {:ok, view, _} = live(context.conn, context.path)
    refute has_element?(view, "[data-part='cache-summary-card']")
  end

  test "cache search and outcome filtering do not change the build's summary", context do
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")
    render_async(view, 5_000)
    reject(&Cache.build_summary/2)
    view |> element("#mix-build-cache-search-form") |> render_change(%{"search" => "JASON"})
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cache-entries", "jason")
    refute has_element?(view, "#mix-build-cache-entries", "decimal")
    assert has_element?(view, "#mix-build-cache-widget-hit_rate", "50.0%")

    render_patch(view, context.path <> "?tab=cache&cache-outcome=bypass")
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cache-entries", "native")
    refute has_element?(view, "#mix-build-cache-entries", "jason")
    assert has_element?(view, "#mix-build-cache-widget-hits", "1")
    assert has_element?(view, "#mix-build-cache-widget-hit_rate", "50.0%")

    render_patch(view, context.path <> "?tab=cache&cache-search=missing")
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cache-entries", "No matching cache entries")
  end

  test "legacy builds show unavailable cache metrics rather than an invented rate", context do
    {:ok, id} =
      Mix.create_build(%{
        id: UUIDv7.generate(),
        project_id: context.project.id,
        account_id: context.user.account.id,
        duration_ms: 10,
        status: "success"
      })

    Buffer.flush()
    path = String.replace(context.path, context.build_id, id)
    {:ok, view, _} = live(context.conn, path <> "?tab=cache")
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cache-widget-hit_rate", "No data")
    assert has_element?(view, "#mix-build-cache-widget-read_bytes", "No data")
    assert has_element?(view, "#mix-build-cache-widget-write_bytes", "No data")
    assert has_element?(view, "#mix-build-cache-read-latency", "No data")
    assert has_element?(view, "#mix-build-cache-entries", "No cacheable tasks found")
    refute has_element?(view, "#mix-build-cache-breakdown-chart")
  end

  test "CAS outputs use Bazel's shared REAPI queries, graph and throughput without local-copy inference", context do
    events =
      for {dependency, outcome, digest, size, duration} <- [
            {"jason", "hit", String.duplicate("a", 64), 4_000, 1_000},
            {"decimal", "write", String.duplicate("b", 64), 2_000, 2_000}
          ] do
        %{
          client_kind: "mix",
          operation: "cas",
          outcome: outcome,
          action_digest: digest,
          size: size,
          duration_us: duration,
          invocation_id: context.build_id,
          action_mnemonic: "MixCompile",
          target_label: dependency,
          configuration_id: "dev",
          project_id: context.project.id,
          account_handle: context.project.account.name,
          project_handle: context.project.name,
          cache_endpoint: "test.kura.local"
        }
      end

    unrelated = [
      Map.merge(hd(events), %{project_id: context.project.id + 1, action_digest: String.duplicate("c", 64)}),
      Map.merge(hd(events), %{invocation_id: "another-build", action_digest: String.duplicate("d", 64)}),
      Map.merge(hd(events), %{client_kind: "bazel", action_digest: String.duplicate("e", 64)})
    ]

    Tuist.ReapiCache.create_cache_events(events ++ unrelated)
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")
    render_async(view, 5_000)
    render_click(view, "toggle-cache-entry", %{"dependency" => "jason"})
    render_async(view, 5_000)
    assert has_element?(view, "[data-part='cache-entry-outputs'] a", String.duplicate("a", 30))

    assert has_element?(
             view,
             "[data-part='cas-outputs-list'] > [data-part='cas-output-item'] > [data-part='cas-output-text']",
             "CAS output Dependency bundle:"
           )

    refute has_element?(view, "[data-part='cache-entry-details']")
    refute has_element?(view, "[data-part='cache-entry-outputs']", "Compilation time avoided")
    refute has_element?(view, "[data-part='cache-entry-outputs']", "Cache downloads")
    refute has_element?(view, "[data-part='cache-entry-outputs']", "Cache uploads")
    view |> element("[data-part='cache-entry-outputs'] a") |> render_click()
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cas-outputs", String.duplicate("a", 30))
    refute has_element?(view, "#mix-build-cas-outputs", String.duplicate("b", 30))
    assert has_element?(view, "#mix-build-cas-outputs-chart")
    assert has_element?(view, "#mix-build-cas-outputs-download-throughput", "32.0 Mbps")
    assert has_element?(view, "#mix-build-cas-outputs-upload-throughput", "8.0 Mbps")
    reject(&Cache.build_summary/2)
    render_patch(view, context.path <> "?tab=cache&cache-tab=cas-outputs")
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cas-outputs", String.duplicate("b", 30))
    for digest <- ["c", "d", "e"], do: refute(has_element?(view, "#mix-build-cas-outputs", String.duplicate(digest, 30)))
    assert has_element?(view, "#mix-build-cas-outputs-download-throughput", "32.0 Mbps")
  end

  test "CAS output pagination, filters and sort patches preserve unfiltered summary metrics", context do
    events =
      for index <- 1..23 do
        %{
          client_kind: "mix",
          operation: "cas",
          outcome: if(rem(index, 2) == 0, do: "write", else: "hit"),
          action_digest: index |> Integer.to_string(16) |> String.pad_leading(64, "0"),
          size: index,
          duration_us: 1_000,
          invocation_id: context.build_id,
          action_mnemonic: "MixCompile",
          target_label: "dependency",
          configuration_id: "dev",
          project_id: context.project.id,
          account_handle: context.project.account.name,
          project_handle: context.project.name,
          cache_endpoint: "test.kura.local"
        }
      end

    Tuist.ReapiCache.create_cache_events(events)
    base = context.path <> "?tab=cache&cache-tab=cas-outputs"
    {:ok, view, _} = live(context.conn, base <> "&cache-output-page=2")
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-build-cas-outputs tbody tr")) == 3
    reject(&Cache.build_summary/2)
    assert has_element?(view, "#mix-build-cas-outputs-chart")

    digest = hd(events).action_digest
    render_patch(view, base <> "&cache-output-page=2&cache-output-key=" <> digest)
    render_async(view, 5_000)
    refute has_element?(view, "a", "Clear key filter")
    view |> element("a.noora-tab-menu-horizontal-item", "CAS Outputs") |> render_click()
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-build-cas-outputs tbody tr")) == 20

    render_patch(view, base <> "&cache-output-operation=write&cache-output-sort-by=size&cache-output-sort-order=asc")
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-build-cas-outputs tbody tr")) == 11
    refute has_element?(view, "#mix-build-cas-outputs", "Download")
    assert has_element?(view, "#mix-build-cas-outputs-chart")
    render_patch(view, base <> "&cache-output-search=" <> digest)
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-build-cas-outputs tbody tr")) == 1
  end

  test "CAS Outputs is an honest empty state without fetching hidden task entries", context do
    reject(&Cache.build_events/3)
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache&cache-tab=cas-outputs")
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cas-outputs", "No CAS outputs found")
    assert has_element?(view, "#mix-build-cache-widget-read_bytes", "4.0 KB")
    refute has_element?(view, "#mix-build-cache-entries")
  end

  test "latency dropdowns and task sorting reuse the build summary", context do
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache")
    render_async(view, 5_000)
    reject(&Cache.build_summary/2)
    render_click(view, "select_cache_read_latency", %{"type" => "p99"})
    render_async(view, 5_000)
    assert has_element?(view, "#mix-build-cache-read-latency", "p99 latency reading cache artifacts")
    assert has_element?(view, "#mix-build-cache-read-latency", "5ms")
    render_patch(view, context.path <> "?tab=cache&cache-sort-order=asc")
    html = render_async(view, 5_000)

    names =
      html
      |> Floki.parse_document!()
      |> Floki.find("#mix-build-cache-entries tbody tr[data-expandable] td:first-child")
      |> Enum.map(&Floki.text/1)

    assert Enum.map(names, &String.trim/1) == ["decimal", "jason", "native"]
  end

  test "cache details are paginated and invalid parameters are normalized", context do
    for index <- 1..22 do
      Cache.insert(
        %{
          id: context.build_id,
          project_id: context.project.id,
          dependency_cache: [cache_event("entry-#{index}", "miss")]
        },
        NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      )
    end

    Mix.CacheEvent.Buffer.flush()
    {:ok, view, _} = live(context.conn, context.path <> "?tab=cache&cache-page=invalid&cache-outcome=invalid")
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-build-cache-entries tbody tr[data-expandable]")) == 20
    assert has_element?(view, "[data-part='pagination']")
    render_patch(view, context.path <> "?tab=cache&cache-page=2")
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-build-cache-entries tbody tr[data-expandable]")) == 5
    assert has_element?(view, "#mix-build-cache-widget-hit_rate", "4.2%")
  end

  defp cache_event(name, outcome, saved \\ nil) do
    %{
      dependency: name,
      outcome: outcome,
      duration_ms: 10,
      saved_duration_ms: saved,
      key: if(outcome == "bypass", do: "", else: String.duplicate("a", 64)),
      reason: if(outcome == "bypass", do: "custom_compiler", else: "")
    }
  end

  defp position(html, text), do: html |> :binary.match(text) |> elem(0)

  test "groups diagnostics into collapsible issue cards on the overview", %{conn: conn, path: path} do
    {:ok, lv, html} = live(conn, path)

    assert has_element?(lv, "#build-run [data-part=errors-and-warnings-card] .issue-card[data-type=warning]")
    assert html =~ "Warning when compiling Elixir file lib/greeter.ex"
    assert html =~ "unused variable in lib/greeter.ex#L4"
    # Client-supplied text is escaped, never rendered as markup.
    assert html =~ "unused alias &lt;b&gt;"
    refute has_element?(lv, ".issue-card[data-type=error]")
  end

  test "leaves the breakdown alone on the tabs that do not show it", %{conn: conn, path: path} do
    reject(&Mix.compiled_files_page/2)

    {:ok, _lv, html} = live(conn, path <> "?tab=warnings")

    assert html =~ "Warnings"
  end

  test "has Warnings and Errors tabs like the Xcode build page", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path <> "?tab=warnings")
    assert has_element?(lv, "[data-part=warnings-card] .issue-card[data-type=warning]")
    refute has_element?(lv, "[data-part=build-details]")

    {:ok, lv, html} = live(conn, path <> "?tab=errors")
    assert has_element?(lv, "[data-part=errors-card] [data-part=empty-state]")
    assert html =~ "No errors detected"
  end

  test "filters the breakdown by search", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path <> "?breakdown-search=greeter")

    assert lv |> element("#mix-breakdown-table") |> render() =~ "lib/greeter.ex"
    refute lv |> element("#mix-breakdown-table") |> render() =~ ">lib/macros.ex<"
  end

  test "treats a malformed page number as the first page", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path <> "?breakdown-page=nope")
    assert lv |> element("#mix-breakdown-table") |> render() =~ "lib/macros.ex"

    {:ok, lv, _html} = live(conn, path <> "?breakdown-page=-3")
    assert lv |> element("#mix-breakdown-table") |> render() =~ "lib/macros.ex"
  end
end
