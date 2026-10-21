defmodule TuistWeb.BuildEntityLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest, except: [render_async: 1]

  alias Tuist.Accounts.Account
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Producers
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.API.BuildEntityResources
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.BuildEntityLabels

  setup %{project: project} do
    FunWithFlags.enable(:build_entities, for_actor: project)
    %{account: project.account}
  end

  test "pages are hidden before any query while legacy build pages stay reachable when build entities are off",
       context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    FunWithFlags.disable(:build_entities, for_actor: project)
    reject(BuildEntities, :get, 4)
    reject(BuildEntities, :list, 4)
    reject(BuildEntities, :inventory_analytics, 4)
    reject(BuildEntities, :inventory_duration_scatter, 4)
    root = "/#{account.name}/#{project.name}"

    for path <- ["/builds/gradle/tasks", "/builds/gradle/tasks/#{Ecto.UUID.generate()}"] do
      assert_raise NotFoundError, fn -> live(conn, root <> path) end
    end

    {:ok, view, _html} = live(conn, root <> "/builds/tasks")
    assert has_element?(view, "a[href='#{root}/builds/tasks']", "Tasks")
    refute has_element?(view, "a[href^='#{root}/builds/gradle/tasks']")
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} have an inventory and independent overview/history page", context do
      resource = unquote(Macro.escape(resource))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      %{entity: entity, observation: observation} = BuildEntitiesFixtures.entity_fixture(project, resource.key)
      path = "/#{account.name}/#{project.name}#{resource.path}"

      {:ok, view, _html} = live(conn, path)
      render_async(view)
      assert has_element?(view, "#build-entity-inventory", entity.name)
      refute has_element?(view, "#build-entity > [data-part=header]")
      assert has_element?(view, "#build-entity > [data-part=filters] #entity-environment-overview")
      assert has_element?(view, "#inventory-observations [data-part=value]", "1")
      assert has_element?(view, "#inventory-entities [data-part=value]", "1")
      assert has_element?(view, "#inventory-failures [data-part=value]", "0")
      assert has_element?(view, "#inventory-duration [data-part=value]", "120ms")
      assert has_element?(view, "#build-entity-inventory-chart")

      assert has_element?(
               view,
               "#build-entity > .noora-card[data-part=analytics] + .noora-card [data-part=inventory-section]"
             )

      [series] = chart_data(view, "build-entity-inventory-chart")["series"]
      assert series["type"] == "line"
      assert Enum.any?(series["data"], &(List.last(&1) == 1))
      assert_native_inventory(view, resource, entity)
      assert has_element?(view, "#build-entity-inventory", "120ms")
      assert has_element?(view, "#build-entity-inventory", "Passed")
      assert has_element?(view, "#build-entity-inventory", DateFormatter.from_now(observation.observed_at))
      assert has_element?(view, "#build-entity-inventory a[href*='sort=last_ran_at']")
      refute has_element?(view, "#build-entity-inventory", "First seen")
      refute has_element?(view, "#build-entity-inventory", "Last seen")
      assert_shared_table_section(view, "inventory-section", "entity-search-form", "build-entity-inventory")
      assert render(view) =~ BuildEntityLabels.plural(resource.system, resource.kind)
      refute render(view) =~ "Build entities"

      render_patch(view, path <> "/#{entity.id}")
      overview = render_async(view)
      assert overview =~ entity.name
      assert overview =~ "Overview"
      assert overview =~ BuildEntityLabels.history(resource.system, resource.kind)
      assert has_element?(view, "#build-entity-history", "main")
      assert_shared_table_section(view, "activity-section", "entity-activity-search-form", "build-entity-history")

      assert overview =~ observation.parent_id
      assert_history_presentation(view, resource, observation)

      assert overview =~ BuildEntityLabels.duration(resource.system, resource.kind)

      assert_duration_semantics(overview, resource.key)

      render_patch(view, path <> "/#{entity.id}?tab=history&environment=local")
      render_async(view)
      assert has_element?(view, "#build-entity-history", "No observations in this period")
      assert_shared_table_section(view, "activity-section", "entity-activity-search-form", "build-entity-history")
      assert render(view) =~ entity.name

      render_patch(view, path <> "/#{entity.id}?environment=local")
      render_async(view, 5_000)

      for widget <- ~w(observations hit-rate duration) do
        assert has_element?(view, "#entity-#{widget}[data-empty=true]", "No data")
        refute has_element?(view, "#entity-#{widget}", "No change")
      end

      assert has_element?(view, "[data-part=analytics-chart]", "No data in this period")

      render_patch(view, path <> "/#{entity.id}?tab=history&environment=ci&branch=main")
      render_async(view)
      assert has_element?(view, "#build-entity-history", "main")
      assert render(view) =~ observation.parent_id
      assert_history_presentation(view, resource, observation)
    end
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} inventory and detail widgets share Test Cases comparison footers", context do
      resource = unquote(Macro.escape(resource))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      now = DateTime.utc_now()

      %{entity: entity} =
        BuildEntitiesFixtures.entity_fixture(project, resource.key,
          observed_at: DateTime.add(now, -10, :day),
          status: "failure",
          duration_ms: 1000
        )

      BuildEntitiesFixtures.entity_fixture(project, resource.key, status: "failure", duration_ms: 2000)
      BuildEntitiesFixtures.entity_fixture(project, resource.key, status: "failure", duration_ms: 4000)
      path = "/#{account.name}/#{project.name}#{resource.path}?analytics-date-range=last-7-days"
      {:ok, view, _} = live(conn, path)
      render_async(view)
      assert_comparison_footer(view, "inventory-observations", "+100.0%", "neutral", "since last week")
      assert_comparison_footer(view, "inventory-failures", "+100.0%", "destructive", "since last week")
      assert_comparison_footer(view, "inventory-duration", "+200.0%", "destructive", "since last week")
      assert_comparison_footer(view, "inventory-entities", "No change", "neutral", "since last week")
      render_click(view, "select_inventory_duration", %{"type" => "p99"})
      render_async(view)
      assert_comparison_footer(view, "inventory-duration", "+298.0%", "destructive", "since last week")

      render_patch(view, "/#{account.name}/#{project.name}#{resource.path}/#{entity.id}?analytics-date-range=last-7-days")
      render_async(view)
      assert_comparison_footer(view, "entity-observations", "+100.0%", "neutral", "since last week")
      assert_comparison_footer(view, "entity-duration", "+280.0%", "destructive", "since last week")
      assert has_element?(view, "#entity-hit-rate[data-empty=true]", "No recorded lookups")
      refute has_element?(view, "#entity-hit-rate [data-part=trend]")
    end
  end

  test "comparison labels follow the selected preset and custom period", %{conn: conn, project: project, account: account} do
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    now = DateTime.utc_now()

    for hours <- [1, 36, 240, 1080] do
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, observed_at: DateTime.add(now, -hours, :hour))
    end

    root = "/#{account.name}/#{project.name}/builds/gradle/tasks"
    {:ok, view, _} = live(conn, root)

    for {preset, label} <- [
          {"last-24-hours", "since yesterday"},
          {"last-7-days", "since last week"},
          {"last-30-days", "since last month"}
        ] do
      render_patch(view, root <> "?analytics-date-range=" <> preset)
      render_async(view)
      assert has_element?(view, "#inventory-observations [data-part=trend] > [data-part=label]", label)
    end

    query =
      URI.encode_query(%{
        "analytics-date-range" => "custom",
        "analytics-start-date" => Date.to_iso8601(Date.add(Date.utc_today(), -7)),
        "analytics-end-date" => Date.to_iso8601(Date.utc_today())
      })

    render_patch(view, root <> "?" <> query)
    render_async(view)
    assert has_element?(view, "#inventory-observations [data-part=trend] > [data-part=label]", "since last period")
  end

  test "zero baselines use absolute changes and detail cache comparisons use percentage points", %{
    conn: conn,
    project: project,
    account: account
  } do
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()

    %{entity: entity} =
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks,
        observed_at: DateTime.add(DateTime.utc_now(), -36, :hour),
        duration_ms: 0,
        cache_status: "miss"
      )

    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks,
      status: "failure",
      duration_ms: 500,
      cache_status: "miss"
    )

    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, duration_ms: nil, cache_status: "hit")
    root = "/#{account.name}/#{project.name}/builds/gradle/tasks"
    {:ok, view, _} = live(conn, root <> "?analytics-date-range=last-24-hours")
    render_async(view)
    assert_comparison_footer(view, "inventory-failures", "+1", "destructive", "since yesterday")
    refute has_element?(view, "#inventory-failures [data-part=trend]", "%")
    assert_comparison_footer(view, "inventory-duration", "+500ms", "destructive", "since yesterday")
    render_patch(view, root <> "/#{entity.id}?analytics-date-range=last-24-hours")
    render_async(view)
    assert_comparison_footer(view, "entity-duration", "+500ms", "destructive", "since yesterday")
    assert_comparison_footer(view, "entity-hit-rate", "+50.0 pp", "success", "since yesterday")
    assert_comparison_footer(view, "entity-observations", "+100.0%", "neutral", "since yesterday")
  end

  test "two recorded zero durations and cache rates show neutral No change", %{
    conn: conn,
    project: project,
    account: account
  } do
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()

    %{entity: entity} =
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks,
        duration_ms: 0,
        cache_status: "miss",
        observed_at: DateTime.add(DateTime.utc_now(), -36, :hour)
      )

    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, duration_ms: 0, cache_status: "miss")
    root = "/#{account.name}/#{project.name}/builds/gradle/tasks"
    {:ok, view, _} = live(conn, root <> "?analytics-date-range=last-24-hours")
    render_async(view)
    assert_comparison_footer(view, "inventory-duration", "No change", "neutral", "since yesterday")
    render_patch(view, root <> "/#{entity.id}?analytics-date-range=last-24-hours")
    render_async(view)
    assert_comparison_footer(view, "entity-duration", "No change", "neutral", "since yesterday")
    assert_comparison_footer(view, "entity-hit-rate", "No change", "neutral", "since yesterday")
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} missing previous measurements never become fabricated comparisons", context do
      resource = unquote(Macro.escape(resource))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, resource.key, duration_ms: 500)
      root = "/#{account.name}/#{project.name}#{resource.path}"
      {:ok, view, _} = live(conn, root)
      render_async(view)
      assert_comparison_footer(view, "inventory-observations", "+1", "neutral", "since last month")
      assert_comparison_footer(view, "inventory-entities", "+1", "neutral", "since last month")
      refute has_element?(view, "#inventory-duration [data-part=trend]")
      refute has_element?(view, "#inventory-failures [data-part=trend]")
      render_patch(view, root <> "/#{entity.id}")
      render_async(view)
      refute has_element?(view, "#entity-duration [data-part=trend]")
      refute has_element?(view, "#entity-hit-rate [data-part=trend]")
    end
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} inventory sorts measured percentiles and keeps period and environment", context do
      resource = unquote(Macro.escape(resource))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      %{entity: slow} = BuildEntitiesFixtures.entity_fixture(project, resource.key, name: "Slow", duration_ms: 1200)
      identity = Map.new(slow.identity, fn {key, value} -> {key, value <> "-fast"} end)
      BuildEntitiesFixtures.entity_fixture(project, resource.key, name: "Fast", identity: identity, duration_ms: 20)
      identity = Map.new(slow.identity, fn {key, value} -> {key, value <> "-unknown"} end)

      BuildEntitiesFixtures.entity_fixture(project, resource.key,
        name: "Unmeasured",
        identity: identity,
        duration_ms: nil
      )

      path = "/#{account.name}/#{project.name}#{resource.path}?environment=ci&analytics-date-range=last-7-days"
      {:ok, view, _} = live(conn, path)
      render_async(view)
      assert inventory_names(view) == ["Slow", "Fast", "Unmeasured"]
      assert has_element?(view, "#build-entity-inventory", "Not recorded")

      render_patch(view, path <> "&sort=p90_duration_ms&order=asc")
      render_async(view)
      assert inventory_names(view) == ["Fast", "Slow", "Unmeasured"]
      assert has_element?(view, "#entity-inventory-sort")

      assert has_element?(
               view,
               "#build-entity-inventory a[href*='sort=p50_duration_ms'][href*='environment=ci'][href*='analytics-date-range=last-7-days']"
             )
    end
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} inventory filters reuse analytics and scatter and survive table navigation", context do
      resource = unquote(Macro.escape(resource))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      %{entity: passed} = BuildEntitiesFixtures.entity_fixture(project, resource.key)

      identity =
        Map.new(passed.identity, fn {field, value} ->
          {field, if(field == "action_index", do: value, else: value <> "-other")}
        end)

      %{entity: failed} =
        BuildEntitiesFixtures.entity_fixture(project, resource.key,
          identity: identity,
          name: "Failed unit",
          status: "failure",
          cache_status: "miss",
          git_branch: "feature/slow",
          duration_ms: 900
        )

      caller = self()

      stub(BuildEntities, :inventory_analytics, fn project_id, system, kind, opts ->
        send(caller, :inventory_analytics_loaded)
        Mimic.call_original(BuildEntities, :inventory_analytics, [project_id, system, kind, opts])
      end)

      stub(BuildEntities, :inventory_duration_scatter, fn project_id, system, kind, opts ->
        send(caller, :inventory_scatter_loaded)
        Mimic.call_original(BuildEntities, :inventory_duration_scatter, [project_id, system, kind, opts])
      end)

      path = "/#{account.name}/#{project.name}#{resource.path}"
      {:ok, view, _} = live(conn, path <> "?environment=ci&widget=duration&duration-chart-type=scatter&page=2")
      render_async(view)
      assert_receive :inventory_analytics_loaded
      assert_receive :inventory_scatter_loaded
      assert has_element?(view, "#entity-inventory-filter")
      assert has_element?(view, "#build-entity-inventory", "Nothing recorded for these filters")

      for {id, value} <- [{"status", "failure"}, {"git_branch", "FEATURE/"}, {"cache_status", "miss"}] do
        render_click(view, "add_filter", %{"value" => id})
        render_click(view, "update_filter", %{"type" => "change_value", "payload_filter_id" => id, "value" => value})
        render_async(view)
        assert has_element?(view, "#build-entity-inventory", failed.name)
        refute has_element?(view, "#build-entity-inventory", passed.name)
      end

      assert has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Outcome")
      assert has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Branch")
      assert has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Cache")
      view |> element("#entity-search-form") |> render_change(%{"q" => "Failed"})
      render_async(view)

      sort_path =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[data-value=p50_duration_ms]")
        |> Floki.attribute("href")
        |> hd()

      query = URI.decode_query(URI.parse(sort_path).query)
      assert query["filter_status_val"] == "failure"
      assert query["filter_git_branch_val"] == "FEATURE/"
      assert query["filter_cache_status_val"] == "miss"
      assert query["q"] == "Failed"
      assert query["environment"] == "ci"
      refute Map.has_key?(query, "page")
      render_patch(view, sort_path)
      render_async(view)
      assert has_element?(view, "#build-entity-inventory", "900ms")
      refute_receive :inventory_analytics_loaded
      refute_receive :inventory_scatter_loaded

      render_click(view, "update_filter", %{
        "type" => "change_value",
        "payload_filter_id" => "git_branch",
        "value" => "missing"
      })

      render_async(view)
      assert has_element?(view, "#build-entity-inventory", "Nothing recorded for these filters")
      render_click(view, "update_filter", %{"type" => "delete", "payload_filter_id" => "git_branch"})
      render_async(view)
      assert has_element?(view, "#build-entity-inventory", failed.name)
      refute has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Branch")
      assert_shared_table_section(view, "inventory-section", "entity-search-form", "build-entity-inventory")

      destination =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("#build-entity-inventory a[data-part=row-link]")
        |> Floki.attribute("href")
        |> hd()

      render_patch(view, destination)
      render_async(view)
      assert has_element?(view, "#build-entity-history", "Failed")

      back =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[data-part=back-button]")
        |> Floki.attribute("href")
        |> hd()

      render_patch(view, back)
      render_async(view)
      assert has_element?(view, "#build-entity-inventory", failed.name)
      assert has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Outcome")
      assert has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Cache")
    end
  end

  for {key, native, expected} <- [
        {:gradle_tasks, %{label: "ShopApp", tags: ["Android"]}, "ShopApp Android"},
        {:xcode_modules, %{label: "generate", command_arguments: "generate --no-open"}, "tuist generate --no-open"},
        {:once_actions, %{label: "once build //app:binary"}, "once build //app:binary"},
        {:bazel_actions, %{label: "bazel build //app:lib"}, "bazel build //app:lib"},
        {:mix_files, %{label: "mix compile"}, "mix compile"},
        {:mix_modules, %{label: "mix compile"}, "mix compile"}
      ] do
    test "#{key} use the native human-readable build context in Recent activity and History", context do
      key = unquote(key)
      native = unquote(Macro.escape(native))
      expected = unquote(expected)
      resource = Enum.find(BuildEntityResources.all(), &(&1.key == key))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      %{entity: entity, observation: observation} = BuildEntitiesFixtures.entity_fixture(project, key)
      caller = self()

      stub(BuildEntities, :parent_contexts, fn project_id, system, kind, ids ->
        send(caller, {:native_context, project_id, system, kind, ids})
        %{observation.parent_id => Map.put(native, :ran_by_name, nil)}
      end)

      path = "/#{account.name}/#{project.name}#{resource.path}/#{entity.id}"
      {:ok, view, _} = live(conn, path)

      for query <- ["", "?tab=history"] do
        if query != "", do: render_patch(view, path <> query)
        render_async(view)
        assert_receive {:native_context, project_id, system, kind, [parent_id]}

        assert {project_id, system, kind, parent_id} ==
                 {project.id, resource.system, resource.kind, observation.parent_id}

        first = view |> element("#build-entity-history tbody tr:first-child td:first-child") |> render()
        text = first |> Floki.parse_fragment!() |> Floki.text(sep: " ") |> String.split() |> Enum.join(" ")
        assert text == expected
        refute text =~ observation.parent_id
        assert has_element?(view, "#build-entity-history [title='#{observation.parent_id}']")
        assert has_element?(view, "#build-entity-history", "Passed")
      end
    end
  end

  test "inventory widgets and table patches reuse analytics while cohort changes reload both sections", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    metrics = BuildEntities.inventory_analytics(project.id, :gradle, "task")
    caller = self()

    stub(BuildEntities, :inventory_analytics, fn _, _, _, opts ->
      send(caller, {:inventory_analytics_loaded, opts})
      metrics
    end)

    stub(BuildEntities, :list, fn project_id, system, kind, opts ->
      send(caller, {:inventory_loaded, opts})
      Mimic.call_original(BuildEntities, :list, [project_id, system, kind, opts])
    end)

    path = "/#{account.name}/#{project.name}/builds/gradle/tasks"
    {:ok, view, _} = live(conn, path)
    render_async(view)
    assert_receive {:inventory_analytics_loaded, original_opts}
    assert_receive {:inventory_loaded, _}

    for widget <- ~w(entities failures) do
      render_click(view, "select_widget", %{"widget" => widget})
      render_async(view)
      [series] = chart_data(view, "build-entity-inventory-chart")["series"]
      assert series["type"] == "line"
    end

    render_click(view, "select_inventory_duration", %{"type" => "p99"})
    render_async(view)
    assert has_element?(view, "#inventory-duration", "p99 execution duration")
    assert length(chart_data(view, "build-entity-inventory-chart")["series"]) == 4
    refute_receive {:inventory_analytics_loaded, _}
    refute_receive {:inventory_loaded, _}

    render_patch(view, path <> "?sort=p50_duration_ms&order=asc")
    render_async(view)
    assert_receive {:inventory_loaded, _}
    refute_receive {:inventory_analytics_loaded, _}

    view |> element("#entity-search-form") |> render_change(%{"q" => "missing"})
    render_async(view)
    assert_receive {:inventory_loaded, _}
    refute_receive {:inventory_analytics_loaded, _}
    assert has_element?(view, "#inventory-entities [data-part=value]", "1")
    assert has_element?(view, "#build-entity-inventory", "Nothing recorded for these filters")

    render_patch(view, path <> "?environment=local")
    render_async(view)
    assert_receive {:inventory_analytics_loaded, local_opts}
    assert_receive {:inventory_loaded, _}
    assert local_opts[:environment] == "local"
    assert local_opts[:start_datetime] == original_opts[:start_datetime]
    assert local_opts[:end_datetime] == original_opts[:end_datetime]

    render_patch(view, path <> "?environment=local&analytics-date-range=last-7-days")
    render_async(view)
    assert_receive {:inventory_analytics_loaded, new_opts}
    assert_receive {:inventory_loaded, _}
    refute new_opts[:start_datetime] == original_opts[:start_datetime]
  end

  for {system, resource, route, label} <- [
        {:gradle, :gradle_tasks, "/builds/gradle/tasks", "Task executions"},
        {:once, :once_actions, "/builds/once/actions", "Action executions"},
        {:bazel, :bazel_actions, "/builds/bazel/actions", "Action executions"}
      ] do
    test "#{system} inventory execution counts exclude cache hits and skipped work, independently of timing", context do
      %{conn: conn, project: project, account: account} = context
      system = unquote(system)
      resource = unquote(resource)
      project = project |> Ecto.Changeset.change(build_system: system) |> Repo.update!()
      observed_at = DateTime.add(DateTime.utc_now(), -300, :second)

      for {status, cache, duration} <- [
            {"success", "none", nil},
            {"success", "none", 0},
            {"failure", "none", 1000},
            {"success", "hit", nil},
            {"success", "hit_local", nil},
            {"success", "hit_remote", nil},
            {"skipped", "none", nil},
            {"up_to_date", "none", nil},
            {"no_source", "none", nil},
            {"cancelled", "none", nil},
            {"unknown", "none", nil}
          ] do
        BuildEntitiesFixtures.entity_fixture(project, resource,
          observed_at: observed_at,
          status: status,
          cache_status: cache,
          duration_ms: duration
        )
      end

      BuildEntitiesFixtures.entity_fixture(project, resource,
        observed_at: DateTime.add(observed_at, -10, :day),
        duration_ms: nil
      )

      path = "/#{account.name}/#{project.name}#{unquote(route)}"
      {:ok, view, _} = live(conn, path <> "?analytics-date-range=last-7-days")
      render_async(view)
      assert has_element?(view, "#inventory-observations", unquote(label))
      assert has_element?(view, "#inventory-observations [data-part=value]", "3")
      assert has_element?(view, "#inventory-observations [data-part=trend]", "+200.0%")
      [series] = chart_data(view, "build-entity-inventory-chart")["series"]
      assert series["name"] == unquote(label)
      assert Enum.sum(Enum.map(series["data"], &List.last/1)) == 3
    end
  end

  test "Xcode inventory counts compilations rather than cache resolutions in its widget, trend and chart", context do
    %{conn: conn, project: project, account: account} = context

    for cache_status <- ["hit_remote", "miss"] do
      BuildEntitiesFixtures.entity_fixture(project, :xcode_modules,
        duration_ms: nil,
        status: "unknown",
        cache_status: cache_status
      )
    end

    build = %{
      id: UUIDv7.generate(),
      project_id: project.id,
      git_branch: "main",
      git_commit_sha: "abc123",
      is_ci: true,
      started_at: DateTime.add(DateTime.utc_now(), -300, :second)
    }

    targets = [%{project: "App", name: "App", compilation_duration: 120, status: :success}]
    Producers.xcode_build(build, targets)
    Producers.xcode_build(build, targets)

    Producers.xcode_build(
      %{build | id: UUIDv7.generate(), started_at: DateTime.add(build.started_at, -10, :day)},
      targets ++ targets
    )

    Producers.xcode_build(%{build | id: UUIDv7.generate(), is_ci: false}, targets ++ targets ++ targets)

    path = "/#{account.name}/#{project.name}/builds/xcode/modules"
    {:ok, view, _} = live(conn, path <> "?environment=ci&analytics-date-range=last-7-days")
    render_async(view)
    assert has_element?(view, "#inventory-observations", "Compilations")
    refute has_element?(view, "#inventory-observations", "Module activity")
    assert has_element?(view, "#inventory-observations [data-part=value]", "1")
    assert has_element?(view, "#inventory-observations [data-part=trend]", "-50.0%")
    [series] = chart_data(view, "build-entity-inventory-chart")["series"]
    assert series["name"] == "Compilations"
    assert Enum.sum(Enum.map(series["data"], &List.last/1)) == 1

    render_patch(view, path <> "?environment=local&analytics-date-range=last-7-days")
    render_async(view)
    assert has_element?(view, "#inventory-observations [data-part=value]", "3")
    [series] = chart_data(view, "build-entity-inventory-chart")["series"]
    assert Enum.sum(Enum.map(series["data"], &List.last/1)) == 3
  end

  test "cache-only inventory activity does not invent compilations, durations or outcomes", context do
    %{conn: conn, project: project, account: account} = context

    BuildEntitiesFixtures.entity_fixture(project, :xcode_modules,
      duration_ms: nil,
      status: "unknown",
      cache_status: "hit_remote"
    )

    reject(BuildEntities, :duration_scatter, 5)
    path = "/#{account.name}/#{project.name}/builds/xcode/modules"
    {:ok, view, _} = live(conn, path)
    render_async(view)
    assert has_element?(view, "#inventory-observations", "Compilations")
    assert has_element?(view, "#inventory-observations [data-part=value]", "0")
    assert has_element?(view, "#inventory-entities [data-part=value]", "1")
    [series] = chart_data(view, "build-entity-inventory-chart")["series"]
    assert series["name"] == "Compilations"
    assert Enum.all?(series["data"], &(List.last(&1) == 0))
    assert has_element?(view, "#inventory-failures[data-empty=true]", "Not recorded")
    assert has_element?(view, "#inventory-duration[data-empty=true]", "Not recorded")

    render_patch(view, path <> "?widget=duration&duration-chart-type=scatter")
    render_async(view)
    assert has_element?(view, "[data-part=analytics-chart]", "No recorded durations")
    refute has_element?(view, ".tuist-chart-type-toggle")

    render_patch(view, path <> "?widget=failures")
    render_async(view)
    assert has_element?(view, "[data-part=analytics-chart]", "No recorded outcomes")

    render_patch(view, path <> "?environment=local")
    render_async(view)

    for widget <- ~w(observations failures duration entities) do
      assert has_element?(view, "#inventory-#{widget}[data-empty=true]", "No data")
      refute has_element?(view, "#inventory-#{widget}", "No change")
    end
  end

  test "measured zero duration and zero failures remain numeric in inventory analytics", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, duration_ms: 0)
    {:ok, view, _} = live(conn, "/#{account.name}/#{project.name}/builds/gradle/tasks?widget=duration")
    render_async(view)
    assert has_element?(view, "#inventory-duration [data-part=value]", "0ms")
    assert has_element?(view, "#inventory-failures [data-part=value]", "0")
    refute has_element?(view, "#inventory-duration[data-empty=true]")
    [average | _] = chart_data(view, "build-entity-inventory-chart")["series"]
    assert Enum.any?(average["data"], &(List.last(&1["value"]) == 0))
  end

  test "inventory analytics query failures retain the table and filters and can be retried", context do
    %{conn: conn, project: project, account: account} = context
    BuildEntitiesFixtures.entity_fixture(project, :xcode_modules)
    metrics = BuildEntities.inventory_analytics(project.id, :xcode, "module")
    stub(BuildEntities, :inventory_analytics, fn _, _, _, _ -> raise QueryLimitError end)
    {:ok, view, _} = live(conn, "/#{account.name}/#{project.name}/builds/xcode/modules")
    render_async(view)
    assert has_element?(view, "[data-async-card][data-state=failed]")
    assert has_element?(view, "#build-entity > [data-part=filters] #entity-environment-overview")
    assert has_element?(view, "#entity-search-form")
    assert has_element?(view, "#build-entity-inventory", "120ms")

    stub(BuildEntities, :inventory_analytics, fn _, _, _, _ -> metrics end)
    render_click(view, "select_widget", %{"widget" => "duration"})
    render_async(view)
    refute has_element?(view, "[data-async-card][data-state=failed]")
    assert has_element?(view, "#build-entity-inventory-chart")
  end

  test "widget and tab changes reuse analytics while identity changes reset them", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)

    %{entity: other_entity} =
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks,
        name: "Other compilation",
        identity: %{
          "root_project_name" => "app",
          "build_path" => ":",
          "task_path" => ":app:compile",
          "task_type" => "Compile"
        }
      )

    metrics = BuildEntities.analytics(project.id, :gradle, "task", entity.id)
    caller = self()

    stub(BuildEntities, :analytics, fn _project_id, _system, _kind, id, opts ->
      send(caller, {:analytics_loaded, id, opts})
      metrics
    end)

    root = "/#{account.name}/#{project.name}/builds/gradle/tasks"
    {:ok, view, _html} = live(conn, root <> "/#{entity.id}")
    render_async(view)
    assert_receive {:analytics_loaded, id, original_opts}
    assert id == entity.id

    render_click(view, "select_widget", %{"widget" => "duration"})
    render_async(view)
    refute_receive {:analytics_loaded, _, _}

    render_patch(view, root <> "/#{entity.id}?tab=history")
    render_async(view)
    render_patch(view, root <> "/#{entity.id}?tab=overview")
    render_async(view)
    refute_receive {:analytics_loaded, _, _}

    render_patch(view, root <> "/#{other_entity.id}")
    render_async(view)
    assert_receive {:analytics_loaded, other_id, new_opts}
    assert other_id == other_entity.id
    assert original_opts[:start_datetime] == new_opts[:start_datetime]
    assert original_opts[:end_datetime] == new_opts[:end_datetime]
    assert render(view) =~ other_entity.name
  end

  test "analytics failures keep history and filters available and can be retried", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    metrics = BuildEntities.analytics(project.id, :gradle, "task", entity.id)
    stub(BuildEntities, :analytics, fn _project_id, _system, _kind, _id, _opts -> raise QueryLimitError end)

    {:ok, view, _html} = live(conn, "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}")
    render_async(view)
    assert has_element?(view, "[data-async-card][data-state=failed]")
    assert has_element?(view, "#entity-environment-overview")
    refute has_element?(view, "#entity-branch-form-overview")
    assert has_element?(view, "#entity-activity-filter")
    assert has_element?(view, "#build-entity-history", "main")

    stub(BuildEntities, :analytics, fn _project_id, _system, _kind, _id, _opts -> metrics end)
    render_click(view, "select_widget", %{"widget" => "duration"})
    render_async(view)
    refute has_element?(view, "[data-async-card][data-state=failed]")
  end

  test "cache-only inventory activity shows no last execution and last-ran sorting preserves filters", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :xcode) |> Repo.update!()
    BuildEntitiesFixtures.entity_fixture(project, :xcode_modules, cache_status: "hit_remote", duration_ms: nil)

    path =
      "/#{account.name}/#{project.name}/builds/xcode/modules?environment=ci&q=Recorded&filter_cache_status_op=%3D%3D&filter_cache_status_val=hit_remote"

    {:ok, view, _} = live(conn, path)
    render_async(view)
    assert has_element?(view, "#build-entity-inventory tbody tr td:nth-last-child(2)", "Not recorded")
    assert has_element?(view, "#build-entity-inventory tbody tr td:last-child", "Not recorded")

    sort_path =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("a[href*='sort=last_ran_at']")
      |> Floki.attribute("href")
      |> hd()

    query = URI.decode_query(URI.parse(sort_path).query)
    assert query["environment"] == "ci"
    assert query["q"] == "Recorded"
    assert query["filter_cache_status_val"] == "hit_remote"
    render_patch(view, sort_path)
    render_async(view)
    assert has_element?(view, "#build-entity-inventory th:last-child a", "Last ran at")
    assert has_element?(view, "#build-entity-inventory tbody tr td:last-child", "Not recorded")
  end

  test "inventory query-limit failures retain filter controls so removing a filter recovers", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)

    stub(BuildEntities, :list, fn project_id, system, kind, opts ->
      if Enum.any?(opts[:filters] || [], &(&1.field == :status)) do
        raise QueryLimitError, code: 159
      else
        Mimic.call_original(BuildEntities, :list, [project_id, system, kind, opts])
      end
    end)

    path = "/#{account.name}/#{project.name}/builds/gradle/tasks?filter_status_op=%3D%3D&filter_status_val=failure"
    {:ok, view, _} = live(conn, path)
    render_async(view)
    assert has_element?(view, "[data-part=inventory-section]", "Something went wrong")
    assert has_element?(view, "#entity-inventory-filter")
    assert has_element?(view, "#entity-search-form")
    assert has_element?(view, "#entity-inventory-sort")
    assert has_element?(view, "[data-part=inventory-section] [data-part=active-filters]", "Outcome")
    assert has_element?(view, "#inventory-observations [data-part=value]", "1")
    render_click(view, "update_filter", %{"type" => "delete", "payload_filter_id" => "status"})
    render_async(view)
    assert has_element?(view, "#build-entity-inventory", entity.name)
    refute has_element?(view, "[data-part=inventory-section]", "Something went wrong")
  end

  test "adding outcome filters preserves a legacy branch cohort without reloading analytics", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)

    expect(BuildEntities, :inventory_analytics, fn project_id, system, kind, opts ->
      assert opts[:branch] == "main"
      Mimic.call_original(BuildEntities, :inventory_analytics, [project_id, system, kind, opts])
    end)

    path = "/#{account.name}/#{project.name}/builds/gradle/tasks?branch=main"
    {:ok, view, _} = live(conn, path)
    render_async(view)
    render_click(view, "add_filter", %{"value" => "status"})

    render_click(view, "update_filter", %{"type" => "change_value", "payload_filter_id" => "status", "value" => "failure"})

    render_async(view)
    assert has_element?(view, "#build-entity-inventory", "Nothing recorded for these filters")
    assert has_element?(view, "#inventory-observations [data-part=value]", "1")
    render_click(view, "update_filter", %{"type" => "delete", "payload_filter_id" => "status"})
    render_async(view)
    assert has_element?(view, "#build-entity-inventory", entity.name)
    html = render(view)
    assert html =~ "branch=main"
  end

  test "search narrows the inventory and preserves filters on navigation", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    path = "/#{account.name}/#{project.name}/builds/gradle/tasks?environment=ci&branch=main"
    {:ok, view, _html} = live(conn, path)
    render_async(view)

    view |> element("#entity-search-form") |> render_change(%{"q" => "no-such-task"})
    render_async(view)
    assert has_element?(view, "#build-entity-inventory", "Nothing recorded for these filters")

    view |> element("#entity-search-form") |> render_change(%{"q" => "Recorded"})
    render_async(view)
    assert has_element?(view, "#build-entity-inventory", entity.name)
    html = render(view)
    assert html =~ "environment=ci"
    assert html =~ "branch=main"
    assert html =~ entity.id
    assert has_element?(view, "a[href*='/builds/tasks']", "Task rankings")

    destination =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("#build-entity-inventory a[data-part='row-link']")
      |> Floki.attribute("href")
      |> hd()

    assert URI.decode_query(URI.parse(destination).query) == %{
             "environment" => "ci",
             "branch" => "main",
             "q" => "Recorded"
           }

    render_patch(view, destination)
    render_async(view)
    assert has_element?(view, "#build-entity-history", "main")

    back =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("a[data-part='back-button']")
      |> Floki.attribute("href")
      |> hd()

    assert URI.decode_query(URI.parse(back).query)["branch"] == "main"
    assert URI.decode_query(URI.parse(back).query)["environment"] == "ci"
  end

  test "compact activity rows retain cache evidence and native skipped status on overview and history", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()

    %{entity: entity} =
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks,
        status: "skipped",
        cache_status: "none",
        duration_ms: nil,
        git_branch: "",
        git_commit_sha: ""
      )

    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, cache_status: "hit_remote", duration_ms: nil)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, status: "failure", cache_status: "miss", duration_ms: 0)
    path = "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}"
    {:ok, view, _} = live(conn, path)

    for suffix <- ["", "?tab=history"] do
      if suffix != "", do: render_patch(view, path <> suffix)
      render_async(view)
      assert has_element?(view, "#build-entity-history .noora-status-badge[data-status=warning]", "Skipped")
      assert has_element?(view, "#build-entity-history .noora-status-badge[data-status=error]", "Failed")

      assert has_element?(
               view,
               "#build-entity-history td:nth-child(2) [data-cache-status=hit_remote]",
               "Cache: Remote hit"
             )

      assert has_element?(view, "#build-entity-history td:nth-child(2) [data-cache-status=miss]", "Cache: Miss")
      refute has_element?(view, "#build-entity-history [data-cache-status=none]")
      assert has_element?(view, "#build-entity-history td:nth-child(3) [data-type=text]", "Unknown")
      refute has_element?(view, "#build-entity-history td:nth-child(3) [data-type=text_and_description]")
      assert has_element?(view, "#build-entity-history td:nth-child(5)", "0ms")
      assert has_element?(view, "#build-entity-history td:nth-child(5)", "Not recorded")
      headers = view |> element("#build-entity-history") |> render() |> Floki.parse_fragment!() |> Floki.find("thead th")
      assert length(headers) == 6
    end
  end

  test "recent activity has independent search, native filters and sorting without reloading analytics", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)

    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks,
      status: "failure",
      cache_status: "miss",
      duration_ms: 900,
      git_branch: "feature/slow",
      git_commit_sha: "feedbeef"
    )

    metrics = BuildEntities.analytics(project.id, :gradle, "task", entity.id)
    caller = self()

    stub(BuildEntities, :analytics, fn _project, _system, _kind, _id, opts ->
      send(caller, {:analytics_loaded, opts})
      metrics
    end)

    root = "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}"
    {:ok, view, _} = live(conn, root <> "?q=Recorded&environment=ci&widget=duration")
    render_async(view)
    assert_receive {:analytics_loaded, original_opts}
    refute has_element?(view, "[data-part=analytics-controls] input[name=branch]")
    assert has_element?(view, "#entity-activity-filter")
    assert has_element?(view, "#entity-activity-sort")

    chart =
      view
      |> element("#build-entity-analytics-chart [data-part=data]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> JSON.decode!()

    assert chart["legend"]["left"] == "left"
    assert chart["legend"]["itemHeight"] == 4
    assert chart["legend"]["textStyle"]["fontSize"] == 10
    assert chart["grid"]["right"] == "3%"
    assert chart["xAxis"]["boundaryGap"] == false

    view |> element("#entity-activity-search-form") |> render_change(%{"search" => "FEED"})
    render_async(view)
    assert has_element?(view, "#build-entity-history", "feature/slow")
    refute has_element?(view, "#build-entity-history", "Passed")

    view |> element("#entity-activity-search-form") |> render_change(%{"search" => ""})
    render_async(view)
    render_click(view, "add_filter", %{"value" => "status"})

    render_click(view, "update_filter", %{"type" => "change_value", "payload_filter_id" => "status", "value" => "failure"})

    render_async(view)
    assert has_element?(view, "#build-entity-history", "Failed")
    refute has_element?(view, "#build-entity-history", "Passed")
    assert has_element?(view, "[data-part=active-filters]", "Outcome")

    render_click(view, "update_filter", %{"type" => "delete", "payload_filter_id" => "status"})
    render_async(view)

    sort_path =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("a[data-value=duration_ms]")
      |> Floki.attribute("href")
      |> hd()

    render_patch(view, sort_path)
    render_async(view)
    assert has_element?(view, "#build-entity-history", "Passed")
    assert has_element?(view, "#entity-environment-overview")
    assert URI.decode_query(URI.parse(sort_path).query)["environment"] == "ci"
    refute_receive {:analytics_loaded, _}
    assert original_opts[:environment] == "ci"

    render_patch(
      view,
      root <>
        "?tab=history&activity-sort=duration_ms&activity-order=asc&page=2&filter_git_branch_op=%3D%7E&filter_git_branch_val=feature"
    )

    render_async(view)

    render_click(view, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "git_branch",
      "value" => "main"
    })

    render_async(view)
    assert has_element?(view, "#build-entity-history", "main")
    refute has_element?(view, "#build-entity-history", "feature/slow")
  end

  test "recorded executions distinguish unavailable metrics from a real zero duration", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, duration_ms: nil)
    root = "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}"
    {:ok, view, _} = live(conn, root)
    render_async(view)
    refute has_element?(view, "#entity-observations[data-empty=true]")
    assert has_element?(view, "#entity-hit-rate[data-empty=true]", "No recorded lookups")
    assert has_element?(view, "#entity-duration[data-empty=true]", "Not recorded")

    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, duration_ms: 0, cache_status: "miss")
    render_patch(view, root <> "?environment=ci")
    render_async(view)
    refute has_element?(view, "#entity-hit-rate[data-empty=true]")
    assert has_element?(view, "#entity-hit-rate", "0.0%")
    refute has_element?(view, "#entity-duration[data-empty=true]")
    assert has_element?(view, "#entity-duration", "0ms")
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} inventory duration scatter is lazy, linked and reused across table and widget changes",
         context do
      resource = unquote(Macro.escape(resource))
      %{conn: conn, project: project, account: account} = context
      project = project |> Ecto.Changeset.change(build_system: resource.system) |> Repo.update!()
      BuildEntitiesFixtures.entity_fixture(project, resource.key)
      BuildEntitiesFixtures.entity_fixture(project, resource.key, duration_ms: 0, status: "failure")
      BuildEntitiesFixtures.entity_fixture(project, resource.key, duration_ms: nil)
      scatter = BuildEntities.inventory_duration_scatter(project.id, resource.system, resource.kind)
      caller = self()

      stub(BuildEntities, :inventory_duration_scatter, fn _, _, _, opts ->
        send(caller, {:inventory_scatter_loaded, opts})
        scatter
      end)

      path = "/#{account.name}/#{project.name}#{resource.path}"
      {:ok, view, _} = live(conn, path)
      render_async(view)
      refute has_element?(view, ".tuist-chart-type-toggle")
      refute_receive {:inventory_scatter_loaded, _}
      render_click(view, "select_widget", %{"widget" => "duration"})
      render_async(view)
      assert has_element?(view, ".tuist-chart-type-toggle", "Scatter plot")
      assert has_element?(view, "#build-entity-inventory-chart")
      refute_receive {:inventory_scatter_loaded, _}
      render_click(view, "select_duration_chart_type", %{"type" => "scatter"})
      render_async(view)
      assert_receive {:inventory_scatter_loaded, original_opts}
      refute has_element?(view, "#build-entity-inventory-chart")
      points = Enum.flat_map(chart_data(view, "build-entity-inventory-scatter-chart")["series"], & &1["data"])
      assert Enum.sort(Enum.map(points, &List.last(&1["value"]))) == [0, 120]
      assert Enum.all?(points, &String.contains?(&1["url"], "/#{account.name}/#{project.name}/"))

      assert Enum.all?(
               points,
               &Enum.any?(&1["tooltipExtra"], fn field ->
                 field["label"] == BuildEntityLabels.singular(resource.system, resource.kind)
               end)
             )

      assert_inventory_scatter_measurement(resource, points)

      view |> element("#entity-search-form") |> render_change(%{"q" => "no-match"})
      render_async(view)
      assert has_element?(view, "#build-entity-inventory-scatter-chart")
      render_click(view, "select_inventory_duration", %{"type" => "p99"})
      render_async(view)
      render_patch(view, path <> "?widget=duration&duration-chart-type=scatter&duration-group-by=environment")
      render_async(view)
      assert [%{"name" => "CI"}] = chart_data(view, "build-entity-inventory-scatter-chart")["series"]
      refute_receive {:inventory_scatter_loaded, _}
      render_click(view, "select_widget", %{"widget" => "failures"})
      render_async(view)
      refute has_element?(view, ".tuist-chart-type-toggle")
      assert has_element?(view, "#build-entity-inventory-chart")
      render_patch(view, path <> "?widget=duration&duration-chart-type=scatter&environment=local")
      render_async(view)
      assert_receive {:inventory_scatter_loaded, local_opts}
      assert local_opts[:environment] == "local"
      assert local_opts[:start_datetime] == original_opts[:start_datetime]
    end
  end

  test "inventory scatter failures leave analytics and the table available and retry independently", context do
    %{conn: conn, project: project, account: account} = context
    BuildEntitiesFixtures.entity_fixture(project, :xcode_modules)
    scatter = BuildEntities.inventory_duration_scatter(project.id, :xcode, "module")
    stub(BuildEntities, :inventory_duration_scatter, fn _, _, _, _ -> raise QueryLimitError end)
    path = "/#{account.name}/#{project.name}/builds/xcode/modules"
    {:ok, view, _} = live(conn, path <> "?widget=duration&duration-chart-type=scatter")
    render_async(view)
    assert has_element?(view, "[data-part=analytics-chart]", "Something went wrong")
    assert has_element?(view, "#inventory-duration [data-part=value]", "120ms")
    assert has_element?(view, "#build-entity-inventory", "120ms")
    render_click(view, "select_duration_chart_type", %{"type" => "line"})
    render_async(view)
    assert has_element?(view, "#build-entity-inventory-chart")
    stub(BuildEntities, :inventory_duration_scatter, fn _, _, _, _ -> %{scatter | truncated: true} end)
    render_click(view, "select_duration_chart_type", %{"type" => "scatter"})
    render_async(view)
    assert has_element?(view, "#build-entity-inventory-scatter-chart")
    assert has_element?(view, "[data-part=analytics-chart]", "Showing the latest 10,000 measured durations")
  end

  test "duration scatter loads lazily and reuses measured points across grouping and table changes", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, status: "failure", cache_status: "miss", duration_ms: 0)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, cache_status: "hit_remote", duration_ms: nil)
    metrics = BuildEntities.analytics(project.id, :gradle, "task", entity.id)
    scatter = BuildEntities.duration_scatter(project.id, :gradle, "task", entity.id)
    caller = self()

    stub(BuildEntities, :analytics, fn _project, _system, _kind, id, opts ->
      send(caller, {:analytics_loaded, id, opts})
      metrics
    end)

    stub(BuildEntities, :duration_scatter, fn _project, _system, _kind, id, opts ->
      send(caller, {:scatter_loaded, id, opts})
      scatter
    end)

    root = "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}"
    {:ok, view, _} = live(conn, root)
    render_async(view)
    assert_receive {:analytics_loaded, _, original_opts}
    refute_receive {:scatter_loaded, _, _}
    refute has_element?(view, ".tuist-chart-type-toggle")

    render_click(view, "select_widget", %{"widget" => "duration"})
    render_async(view)
    assert has_element?(view, ".tuist-chart-type-toggle", "Scatter plot")
    refute_receive {:scatter_loaded, _, _}
    [average | _] = chart_data(view, "build-entity-analytics-chart")["series"]
    assert average["connectNulls"] == false
    assert average["symbol"] == "circle"
    measured_point = Enum.find(average["data"], &(List.last(&1["value"]) != nil))
    assert List.last(measured_point["tooltipExtra"]) == %{"label" => "Measured durations", "value" => "2"}

    render_click(view, "select_duration_chart_type", %{"type" => "scatter"})
    render_async(view)
    assert_receive {:scatter_loaded, id, scatter_opts}
    assert id == entity.id
    assert scatter_opts == original_opts
    points = Enum.flat_map(chart_data(view, "build-entity-duration-scatter-chart")["series"], & &1["data"])
    assert Enum.sort(Enum.map(points, &List.last(&1["value"]))) == [0, 120]
    assert Enum.all?(points, &String.contains?(&1["url"], "/builds/build-runs/"))
    assert Enum.all?(points, &Enum.any?(&1["tooltipExtra"], fn field -> field["label"] == "Recorded at" end))

    render_patch(view, root <> "?widget=duration&duration-chart-type=scatter&duration-group-by=environment")
    render_async(view)
    assert [%{"name" => "CI"}] = chart_data(view, "build-entity-duration-scatter-chart")["series"]
    view |> element("#entity-activity-search-form") |> render_change(%{"search" => "no-match"})
    render_async(view)
    assert has_element?(view, "#build-entity-duration-scatter-chart")
    refute_receive {:scatter_loaded, _, _}
    refute_receive {:analytics_loaded, _, _}

    render_click(view, "select_widget", %{"widget" => "hit_rate"})
    render_async(view)
    [rate] = chart_data(view, "build-entity-analytics-chart")["series"]
    assert rate["connectNulls"] == false
    assert rate["showAllSymbol"] == true
    assert Enum.any?(rate["data"], &(List.last(&1["value"]) == nil))
    rate_point = Enum.find(rate["data"], &(List.last(&1["value"]) != nil))

    assert rate_point["tooltipExtra"] == [
             %{"label" => "Cache hit rate", "value" => "50.0%"},
             %{"label" => "Hits", "value" => "1"},
             %{"label" => "Misses", "value" => "1"},
             %{"label" => "Recorded lookups", "value" => "2"}
           ]

    refute has_element?(view, ".tuist-chart-type-toggle")
  end

  test "scatter errors are independent, line remains available and failed scatter requests retry", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    scatter = BuildEntities.duration_scatter(project.id, :gradle, "task", entity.id)
    stub(BuildEntities, :duration_scatter, fn _, _, _, _, _ -> raise QueryLimitError end)
    root = "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}"
    {:ok, view, _} = live(conn, root <> "?widget=duration&duration-chart-type=scatter")
    render_async(view)
    assert has_element?(view, "[data-part=analytics-chart]", "Something went wrong")
    assert has_element?(view, "#entity-duration")
    assert has_element?(view, ".tuist-chart-type-toggle", "Line")
    assert has_element?(view, "#build-entity-history")

    render_click(view, "select_duration_chart_type", %{"type" => "line"})
    render_async(view)
    assert has_element?(view, "#build-entity-analytics-chart")
    refute has_element?(view, "[data-part=analytics-chart]", "Something went wrong")
    stub(BuildEntities, :duration_scatter, fn _, _, _, _, _ -> %{scatter | truncated: true} end)
    render_click(view, "select_duration_chart_type", %{"type" => "scatter"})
    render_async(view)
    assert has_element?(view, "#build-entity-duration-scatter-chart")
    assert has_element?(view, "[data-part=analytics-chart]", "Showing the latest 10,000 measured durations")
  end

  test "Xcode compilation durations link history and scatter to the native build", context do
    %{conn: conn, project: project, account: account} = context

    %{entity: entity} =
      BuildEntitiesFixtures.entity_fixture(project, :xcode_modules, duration_ms: nil, cache_status: "hit_remote")

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "AppScheme",
        is_ci: true,
        targets: [%{name: "App", project: "App", build_duration: 5000, compilation_duration: 1200, status: "success"}]
      )

    root = "/#{account.name}/#{project.name}"
    {:ok, view, _} = live(conn, root <> "/builds/xcode/modules/#{entity.id}?widget=duration&duration-chart-type=scatter")
    render_async(view)
    assert has_element?(view, ".tuist-chart-type-toggle")
    assert has_element?(view, "#build-entity-history", "AppScheme")
    assert has_element?(view, "#build-entity-history a[href='#{root}/builds/build-runs/#{build.id}']")
    data = chart_data(view, "build-entity-duration-scatter-chart")
    [point] = Enum.flat_map(data["series"], & &1["data"])
    assert List.last(point["value"]) == 1200
    assert point["url"] == root <> "/builds/build-runs/#{build.id}"
  end

  test "Xcode modules without measured durations omit the scatter toggle", context do
    %{conn: conn, project: project, account: account} = context
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :xcode_modules, duration_ms: nil)

    {:ok, view, _} =
      live(
        conn,
        "/#{account.name}/#{project.name}/builds/xcode/modules/#{entity.id}?widget=duration&duration-chart-type=scatter"
      )

    render_async(view)
    assert has_element?(view, "[data-part=header] [data-part=badges]", "Project: App")
    assert has_element?(view, "[data-part=header] [data-part=badges]", "Target: App")
    refute has_element?(view, "[data-part=identity-note]")
    refute has_element?(view, ".tuist-chart-type-toggle")
    assert has_element?(view, "#entity-duration[data-empty=true]", "Not recorded")
    assert has_element?(view, "[data-part=analytics-chart]", "No recorded durations")
    refute has_element?(view, "#build-entity-duration-scatter-chart")
  end

  test "Ran by uses recorded local actors, CI and Unknown rather than viewer or guessed provenance", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity, observation: local} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: false)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: false, parent_id: local.parent_id)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: true)
    %{observation: unknown} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: nil)
    caller = self()

    stub(BuildEntities, :parent_contexts, fn project_id, system, kind, ids ->
      send(caller, {:parent_contexts, project_id, system, kind, ids})

      %{
        local.parent_id => %{label: "ShopApp", tags: ["Android"], ran_by_name: "recorded-builder"},
        unknown.parent_id => %{label: "ShopApp", tags: [], ran_by_name: "untrusted-attribution"}
      }
    end)

    {:ok, view, _} = live(conn, "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}?tab=history")
    render_async(view)
    assert_receive {:parent_contexts, project_id, :gradle, "task", parent_ids}
    assert project_id == project.id
    assert local.parent_id in parent_ids
    assert unknown.parent_id in parent_ids
    assert length(parent_ids) == 3
    assert has_element?(view, "#build-entity-history [data-part=project-with-tags]", "ShopApp")
    assert has_element?(view, "#build-entity-history [data-part=project-with-tags]", "Android")
    assert has_element?(view, "#build-entity-history .noora-badge[data-color=primary]", "recorded-builder")
    assert has_element?(view, "#build-entity-history .noora-badge[data-color=information]", "CI")
    assert has_element?(view, "#build-entity-history .noora-badge[data-color=neutral]", "Unknown")
    refute has_element?(view, "#build-entity-history", "untrusted-attribution")
    refute has_element?(view, "#build-entity-history", account.name)
  end

  test "Ran by preserves verified identities and unverified report claims", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()

    %{entity: entity, observation: reported} =
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: false)

    %{observation: verified} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: false)

    stub(BuildEntities, :parent_contexts, fn _, _, _, _ ->
      %{
        reported.parent_id => %{
          ran_by_name: "publisher-not-actor",
          submission_auth: "network_trusted",
          claimed_actor_id: "reported-builder"
        },
        verified.parent_id => %{
          ran_by_name: "verified-builder",
          submission_auth: "token",
          actor_account: %Account{name: "verified-builder"}
        }
      }
    end)

    {:ok, view, _} = live(conn, "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}?tab=history")
    render_async(view)
    assert has_element?(view, "#build-entity-history .noora-badge[data-color=neutral]", "reported-builder")
    assert has_element?(view, "#build-entity-history [data-actor-source=reported] .icon-tabler-device-laptop")
    refute has_element?(view, "#build-entity-history [data-actor-source=reported]", "Unverified")
    assert has_element?(view, "#build-entity-history .noora-badge[data-color=primary]", "verified-builder")
    refute has_element?(view, "#build-entity-history .noora-badge[data-color=primary]", "reported-builder")
    refute has_element?(view, "#build-entity-history", "publisher-not-actor")
  end

  test "optional parent context limits leave observations and navigation available", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()

    %{entity: entity, observation: observation} =
      BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: false)

    stub(BuildEntities, :parent_contexts, fn _, _, _, _ -> raise QueryLimitError end)
    {:ok, view, _} = live(conn, "/#{account.name}/#{project.name}/builds/gradle/tasks/#{entity.id}?tab=history")
    render_async(view)
    assert has_element?(view, "#build-entity-history [title='#{observation.parent_id}']", "Not reported")
    refute has_element?(view, "#build-entity-history", observation.parent_id)
    assert render(view) =~ observation.parent_id
    assert has_element?(view, "#build-entity-history .noora-badge[data-color=neutral]", "Unknown")
    refute has_element?(view, "[data-part=activity-section]", "Something went wrong")
  end

  test "history failures retain search and filter controls", context do
    %{conn: conn, project: project, account: account} = context
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :xcode_modules)
    stub(BuildEntities, :history, fn _, _, _, _, _ -> raise QueryLimitError end)
    {:ok, view, _} = live(conn, "/#{account.name}/#{project.name}/builds/xcode/modules/#{entity.id}")
    render_async(view)
    assert has_element?(view, "#entity-activity-search-form")
    assert has_element?(view, "#entity-activity-filter")
    assert has_element?(view, "[data-chart-frame=small]", "Something went wrong")
  end

  defp assert_comparison_footer(view, widget, value, color, label) do
    assert has_element?(view, "##{widget} [data-part=trend] .noora-badge[data-color=#{color}]", value)
    assert has_element?(view, "##{widget} [data-part=trend] > [data-part=label]", label)
  end

  defp assert_history_presentation(view, resource, observation) do
    table = view |> element("#build-entity-history") |> render() |> Floki.parse_fragment!()
    headers = table |> Floki.find("thead th") |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert headers == [
             BuildEntityLabels.parent(resource.system, resource.kind),
             "Status",
             "Branch",
             "Ran by",
             BuildEntityLabels.duration(resource.system, resource.kind),
             "Recorded at"
           ]

    refute "Environment" in headers
    refute "Commit SHA" in headers
    refute "Cache" in headers

    branch_cell = Floki.find(table, "tbody tr:first-child td:nth-child(3) > [data-part=cell]")

    test_case_branch_cell =
      (&Noora.Table.text_cell/1)
      |> render_component(icon: "git_branch", label: observation.git_branch)
      |> Floki.parse_fragment!()
      |> Floki.find("[data-part=cell]")

    assert branch_cell == test_case_branch_cell
    refute has_element?(view, "#build-entity-history td:nth-child(3) [data-part=description]")
    refute has_element?(view, "#build-entity-history td:nth-child(3) [title]")
    refute has_element?(view, "#build-entity-history td:nth-child(3)", String.slice(observation.git_commit_sha, 0, 7))

    assert has_element?(
             view,
             "#entity-activity-search-form[phx-debounce='200'] [data-part=search][placeholder='Search...']"
           )

    assert has_element?(
             view,
             "#build-entity-history td:last-child [data-part=sublabel]",
             DateFormatter.from_now(observation.observed_at)
           )

    refute has_element?(view, "#build-entity-history [data-cache-status]")

    assert table |> Floki.find("tbody tr:first-child td:first-child") |> Floki.text() |> String.trim() ==
             "Not reported"

    assert has_element?(view, "#build-entity-history [title='#{observation.parent_id}']")
    refute has_element?(view, "#build-entity-history", observation.parent_id)

    assert has_element?(view, "#build-entity-history .noora-badge[data-color=information]", "CI")
  end

  defp assert_duration_semantics(overview, :mix_modules) do
    assert overview =~ "Durations measure compilation of the containing file, which every module in that file shares."
  end

  defp assert_duration_semantics(_overview, _kind), do: :ok

  defp assert_native_inventory(view, resource, entity) do
    inventory = view |> element("#build-entity-inventory") |> render() |> Floki.parse_fragment!()
    headers = inventory |> Floki.find("thead th") |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
    assert headers == inventory_headers(resource.key)

    if resource.system == :gradle do
      assert Floki.text(inventory) =~ "Root build"
      assert length(Regex.scan(~r/:app:test/, Floki.text(inventory))) == 1
    end

    if resource.system == :mix do
      assert Floki.text(inventory) =~ hd(Map.values(entity.identity))
    end
  end

  defp inventory_headers(resource) do
    native = %{
      bazel_actions: ["Action", "Target", "Mnemonic"],
      gradle_tasks: ["Task", "Root project", "Build path", "Task type"],
      xcode_modules: ["Module"],
      once_actions: ["Action", "Target", "Capability", "Declared action index"],
      mix_files: ["File"],
      mix_modules: ["Module"]
    }

    Map.fetch!(native, resource) ++ ["p50", "p90", "p99", "Avg.", "Last status", "Last ran at"]
  end

  defp inventory_names(view) do
    view
    |> element("#build-entity-inventory")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("tbody tr td:first-child [data-part=label]")
    |> Enum.map(&Floki.text/1)
  end

  defp render_async(view), do: Phoenix.LiveViewTest.render_async(view, 5_000)

  defp assert_inventory_scatter_measurement(%{key: :mix_modules}, points) do
    assert Enum.all?(
             points,
             &Enum.any?(&1["tooltipExtra"], fn field -> field["value"] == "Shared containing-file compilation" end)
           )
  end

  defp assert_inventory_scatter_measurement(_resource, _points), do: :ok

  defp chart_data(view, id) do
    view
    |> element("##{id} [data-part=data]")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> JSON.decode!()
  end

  defp assert_shared_table_section(view, part, search_id, table_id) do
    [{"div", _attrs, children}] =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find(".noora-card__section[data-part='#{part}']")

    assert [_] = Floki.find(children, "##{search_id}")
    assert [_] = Floki.find(children, "##{table_id}")
    assert [] = Floki.find(children, ".noora-card__section")
  end
end
