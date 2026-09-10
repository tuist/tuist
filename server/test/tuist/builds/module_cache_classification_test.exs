defmodule Tuist.Builds.ModuleCacheClassificationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    stub(DateTime, :utc_now, fn -> ~U[2024-04-03 12:00:00Z] end)
    project = ProjectsFixtures.project_fixture()

    %{
      project: project,
      opts: [
        project_id: project.id,
        start_datetime: ~U[2024-04-01 00:00:00Z],
        end_datetime: ~U[2024-04-02 23:59:59Z]
      ]
    }
  end

  for view <- [:history, :breakdown] do
    @view view

    test "#{view}: the first observation of each module is cold", %{project: project, opts: opts} do
      event = observation(project, 1)
      insert_chain(event, :miss, "v1")

      assert_reasons(@view, opts, event, %{"A" => "cold", "B" => "cold", "C" => "cold"})
    end

    test "#{view}: changing A changes A directly and invalidates B and C upstream", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1")

      changed = observation(project, 2)
      insert_chain(changed, :miss, "v2", a_sources: "a-sources-v2")

      assert_reasons(@view, opts, changed, %{
        "A" => "changed",
        "B" => "upstream",
        "C" => "upstream"
      })
    end

    test "#{view}: updating Xcode's compiler changes every module in a warmed graph", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1, xcode_version: "15.3", swift_version: "5.10")
      insert_chain(warmed, :remote, "v1", compiler: "5.10.0.13")

      upgraded = observation(project, 2, xcode_version: "16.0", swift_version: "6.0")
      insert_chain(upgraded, :miss, "v2", compiler: "6.0.0.9")

      assert_reasons(@view, opts, upgraded, %{
        "A" => "changed",
        "B" => "changed",
        "C" => "changed"
      })
    end

    test "#{view}: a direct settings change takes precedence over changed dependencies", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1")

      changed = observation(project, 2)

      insert_chain(changed, :miss, "v2",
        a_sources: "a-sources-v2",
        b_settings: "b-settings-v2"
      )

      assert_reasons(@view, opts, changed, %{
        "A" => "changed",
        "B" => "changed",
        "C" => "upstream"
      })
    end

    test "#{view}: the precise compiler input changes even when the reported Swift version does not", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1, swift_version: "6.0")
      insert_chain(warmed, :remote, "v1", compiler: "6.0.0.9")

      upgraded = observation(project, 2, swift_version: "6.0")
      insert_chain(upgraded, :miss, "v2", compiler: "6.0.0.10")

      assert_reasons(@view, opts, upgraded, %{"A" => "changed", "B" => "changed", "C" => "changed"})
    end

    for missing <- [:earlier, :later] do
      @missing missing
      test "#{view}: missing #{@missing} compiler inputs do not imply a direct change", %{
        project: project,
        opts: opts
      } do
        inputs = ["Debug", "6.0.0.9", "7"]
        warmed = observation(project, 1)
        insert_chain(warmed, :remote, "v1", additional_strings: if(@missing == :earlier, do: [], else: inputs))

        current = observation(project, 2)
        insert_chain(current, :miss, "v2", additional_strings: if(@missing == :later, do: [], else: inputs))

        assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "upstream", "C" => "upstream"})
      end
    end
  end

  defp observation(project, day, attrs \\ []) do
    created_at = NaiveDateTime.new!(2024, 4, day, 10, 0, 0)

    build =
      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: DateTime.from_naive!(created_at, "Etc/UTC"),
        xcode_version: Keyword.get(attrs, :xcode_version, "15.3"),
        is_ci: true
      )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      build_run_id: build.id,
      git_branch: "main",
      git_commit_sha: "same-commit",
      created_at: created_at,
      swift_version: Keyword.get(attrs, :swift_version, "5.10"),
      is_ci: true
    )
  end

  # A is a leaf, B depends on A, and C depends on B. Every revision uses new
  # cache keys, including downstream modules whose own sources remain unchanged.
  defp insert_chain(event, hit, revision, attrs \\ []) do
    compiler = Keyword.get(attrs, :compiler, "5.10.0.13")

    for {name, dependencies, dependency_hash, sources, settings} <- [
          {"A", [], "no-dependencies", Keyword.get(attrs, :a_sources, "a-sources-v1"), "a-settings"},
          {"B", ["A"], "dependencies-of-A-#{revision}", "b-sources", Keyword.get(attrs, :b_settings, "b-settings")},
          {"C", ["B"], "dependencies-of-B-#{revision}", "c-sources", "c-settings"}
        ] do
      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: name,
        product: "framework",
        binary_cache_hash: "#{name}-#{revision}",
        binary_cache_hit: hit,
        sources_hash: sources,
        target_settings_hash: settings,
        dependencies: dependencies,
        dependencies_hash: dependency_hash,
        additional_strings: Keyword.get(attrs, :additional_strings, ["Debug", compiler, "7"])
      )
    end
  end

  defp assert_reasons(:history, opts, event, expected) do
    actual =
      Map.new(expected, fn {name, _reason} ->
        page = Analytics.module_build_history(Keyword.put(opts, :name, name))
        row = Enum.find(page.rows, &(&1.id == event.id))
        assert row, "Missing history for #{name} in #{event.id}"
        assert row.hit == "miss"
        {name, row.reason}
      end)

    assert actual == expected
  end

  defp assert_reasons(:breakdown, opts, _event, expected) do
    actual =
      opts
      |> Analytics.module_invalidations()
      |> Map.new(fn row ->
        assert row.invalidations == 1
        {row.name, {row.self_changes, row.dependency_induced, row.unclassified}}
      end)

    counts = %{"changed" => {1, 0, 0}, "upstream" => {0, 1, 0}, "cold" => {0, 0, 1}}

    assert actual ==
             Map.new(expected, fn {name, reason} -> {name, Map.fetch!(counts, reason)} end)
  end
end
