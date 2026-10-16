defmodule TuistWeb.BuildEntityLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest, except: [render_async: 1]

  alias Tuist.Accounts.Account
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
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
      assert_native_inventory(view, resource, entity)
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

  for {key, native, expected} <- [
        {:gradle_tasks, %{label: "ShopApp", tags: ["Android"]}, "ShopApp Android"},
        {:xcode_modules, %{label: "generate", command_arguments: "generate --no-open"}, "tuist generate --no-open"},
        {:once_actions, %{label: "once build //app:binary"}, "once build //app:binary"},
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

  test "Xcode modules without measured durations omit the scatter toggle", context do
    %{conn: conn, project: project, account: account} = context
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :xcode_modules, duration_ms: nil)
    reject(BuildEntities, :duration_scatter, 5)

    {:ok, view, _} =
      live(
        conn,
        "/#{account.name}/#{project.name}/builds/xcode/modules/#{entity.id}?widget=duration&duration-chart-type=scatter"
      )

    html = render_async(view)
    assert html =~ "Shows the binary cache outcome each time tuist generate or tuist cache resolved this module."
    assert html =~ "Tuist does not record an execution duration or status for generated modules."
    refute has_element?(view, ".tuist-chart-type-toggle")
    assert has_element?(view, "#entity-duration[data-empty=true]", "Not recorded")
    assert has_element?(view, "[data-part=analytics-chart]", "No recorded durations")
    refute has_element?(view, "#build-entity-duration-scatter-chart")
  end

  test "Built by uses recorded local actors, CI and Unknown rather than viewer or guessed provenance", context do
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

  test "Built by preserves verified identities and unverified report claims", context do
    %{conn: conn, project: project, account: account} = context
    project = project |> Ecto.Changeset.change(build_system: :gradle) |> Repo.update!()
    %{entity: entity, observation: reported} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks, is_ci: false)
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

  defp assert_history_presentation(view, resource, observation) do
    table = view |> element("#build-entity-history") |> render() |> Floki.parse_fragment!()
    headers = table |> Floki.find("thead th") |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert headers == [
             BuildEntityLabels.parent(resource.system, resource.kind),
             "Status",
             "Branch",
             "Commit SHA",
             "Built by",
             BuildEntityLabels.duration(resource.system, resource.kind),
             "Cache",
             "Recorded at"
           ]

    refute "Environment" in headers

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
      gradle_tasks: ["Task", "Root project", "Build path", "Task type"],
      xcode_modules: ["Module", "Project"],
      once_actions: ["Action", "Target", "Capability", "Declared action index"],
      mix_files: ["File"],
      mix_modules: ["Module"]
    }

    Map.fetch!(native, resource) ++ ["First seen", "Last seen"]
  end

  defp render_async(view), do: Phoenix.LiveViewTest.render_async(view, 5_000)

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
