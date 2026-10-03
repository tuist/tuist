defmodule Tuist.Builds.ModuleCacheClassificationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds.Analytics
  alias Tuist.IngestRepo
  alias Tuist.Xcode.XcodeTarget
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
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1", compiler: "6.0.0.9")

      upgraded = observation(project, 2)
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

    for {input, old, new} <- [
          {:additional_strings, ["Debug", "6.0.0.9", "7"], ["Release", "6.0.0.9", "7"]},
          {:hashed_destinations, ["mac"], ["iphone"]},
          {:embedded_product_references_hash, "", "embedded"},
          {:foreign_build_hash, "", "foreign"},
          {:test_device, "iPhone 16", "iPhone 17"},
          {:test_runtime, "iOS 18", "iOS 26"}
        ] do
      @input input
      @old old
      @new new
      test "#{view}: a change to #{@input} changes every affected module", %{project: project, opts: opts} do
        warmed = observation(project, 1)
        insert_chain(warmed, :remote, "v1", [{@input, @old}])
        current = observation(project, 2)
        insert_chain(current, :miss, "v2", [{@input, @new}])
        assert_reasons(@view, opts, current, %{"A" => "changed", "B" => "changed", "C" => "changed"})
      end
    end

    for missing <- [:earlier, :later] do
      @missing missing
      test "#{view}: missing #{@missing} optional inputs do not imply a change", %{project: project, opts: opts} do
        reported = [
          hashed_destinations: ["mac"],
          foreign_build_hash: "",
          embedded_product_references_hash: "",
          test_device: "",
          test_runtime: ""
        ]

        warmed = observation(project, 1)
        insert_chain(warmed, :remote, "v1", if(@missing == :earlier, do: [], else: reported))
        current = observation(project, 2)
        insert_chain(current, :miss, "v2", if(@missing == :later, do: [], else: reported))
        assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "upstream", "C" => "upstream"})
      end
    end

    test "#{view}: known empty destinations differ from a reported nonempty set", %{project: project, opts: opts} do
      known_empty = [
        hashed_destinations: [],
        foreign_build_hash: "",
        embedded_product_references_hash: "",
        test_device: "",
        test_runtime: ""
      ]

      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1", known_empty)
      current = observation(project, 2)
      insert_chain(current, :miss, "v2", Keyword.put(known_empty, :hashed_destinations, ["mac"]))
      assert_reasons(@view, opts, current, %{"A" => "changed", "B" => "changed", "C" => "changed"})
    end

    test "#{view}: new destination telemetry does not hide an existing compiler change", %{project: project, opts: opts} do
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1", compiler: "6.0.0.9")
      current = observation(project, 2)
      insert_chain(current, :miss, "v2", compiler: "6.0.0.10", hashed_destinations: ["mac"])
      assert_reasons(@view, opts, current, %{"A" => "changed", "B" => "changed", "C" => "changed"})
    end

    test "#{view}: a future end date does not shorten the available evidence window", %{project: project, opts: opts} do
      warmed = observation(project, 1, observed_at: ~N[2024-03-04 13:00:00])
      insert_chain(warmed, :remote, "v1")
      current = observation(project, 2)
      insert_chain(current, :miss, "v1")

      assert_reasons(@view, Keyword.put(opts, :end_datetime, ~U[2024-04-04 23:59:59Z]), current, %{
        "A" => "evicted",
        "B" => "evicted",
        "C" => "evicted"
      })
    end

    test "#{view}: a runner clock ahead cannot use a hit reported after its server-derived start", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 2, observed_at: ~N[2024-04-02 10:01:00])
      insert_chain(warmed, :remote, "v1")

      current =
        observation(project, 2,
          observed_at: ~N[2024-04-02 10:05:00],
          reported_at: ~N[2024-04-02 10:02:00],
          duration: 120_000
        )

      insert_chain(current, :miss, "v1")
      assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
    end

    test "#{view}: an earlier remote hit for the exact key and endpoint makes a miss evicted", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1")
      current = observation(project, 2)
      insert_chain(current, :miss, "v1")
      assert_reasons(@view, opts, current, %{"A" => "evicted", "B" => "evicted", "C" => "evicted"})
      filtered = Analytics.module_build_history(opts ++ [name: "A", reason: "evicted"])
      assert Enum.map(filtered.rows, & &1.id) == [current.id]
      series = Analytics.module_miss_reasons_timeseries(opts)
      assert series.evicted == [0, 3]
      assert series.cold == [0, 0]
    end

    for prior_hit <- [:local, :miss] do
      @prior_hit prior_hit
      test "#{view}: a previous #{@prior_hit} does not establish remote availability", %{project: project, opts: opts} do
        warmed = observation(project, 1)
        insert_chain(warmed, @prior_hit, "v1")
        current = observation(project, 2)
        insert_chain(current, :miss, "v1")
        current_opts = Keyword.put(opts, :start_datetime, ~U[2024-04-02 00:00:00Z])
        assert_reasons(@view, current_opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
      end
    end

    for endpoint <- ["", "https://other-cache.example.com"] do
      @endpoint endpoint
      test "#{view}: an unknown or different endpoint #{inspect(endpoint)} does not establish availability", %{
        project: project,
        opts: opts
      } do
        warmed = observation(project, 1, cache_endpoint: @endpoint)
        insert_chain(warmed, :remote, "v1")
        current = observation(project, 2)
        insert_chain(current, :miss, "v1")
        assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
      end
    end

    test "#{view}: matching partial inputs with a different full key do not establish availability", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1")
      current = observation(project, 2)
      insert_chain(current, :miss, "v1", key_revision: "v2")
      assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
    end

    test "#{view}: empty cache keys do not establish availability", %{project: project, opts: opts} do
      warmed = observation(project, 1)
      insert_chain(warmed, :remote, "v1", hash: "")
      current = observation(project, 2)
      insert_chain(current, :miss, "v1", hash: "")
      assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
    end

    test "#{view}: remote availability crosses branch, environment, and selected start-date filters", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1, git_branch: "main", is_ci: false)
      insert_chain(warmed, :remote, "v1")
      current = observation(project, 2, git_branch: "feature", is_ci: true)
      insert_chain(current, :miss, "v1")
      scoped = Keyword.merge(opts, start_datetime: ~U[2024-04-02 00:00:00Z], git_branch: "feature", is_ci: true)
      assert_reasons(@view, scoped, current, %{"A" => "evicted", "B" => "evicted", "C" => "evicted"})
    end

    for reported_at <- [~N[2024-04-02 10:00:00], ~N[2024-04-02 10:05:00]] do
      @reported_at reported_at
      test "#{view}: a remote-hit report at #{reported_at} cannot establish availability before command start", %{
        project: project,
        opts: opts
      } do
        warmed = observation(project, 1, reported_at: @reported_at)
        insert_chain(warmed, :remote, "v1")
        current = observation(project, 2)
        insert_chain(current, :miss, "v1")
        assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
      end
    end

    test "#{view}: remote hits outside the available 30-day history do not establish availability", %{
      project: project,
      opts: opts
    } do
      warmed = observation(project, 1, observed_at: ~N[2024-03-01 10:00:00])
      insert_chain(warmed, :remote, "v1")
      current = observation(project, 2)
      insert_chain(current, :miss, "v1")
      assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
    end

    test "#{view}: another project's remote hit is not evidence", %{project: project, opts: opts} do
      other = ProjectsFixtures.project_fixture()
      warmed = observation(other, 1)
      insert_chain(warmed, :remote, "v1")
      current = observation(project, 2)
      insert_chain(current, :miss, "v1")
      assert_reasons(@view, opts, current, %{"A" => "cold", "B" => "cold", "C" => "cold"})
    end

    test "#{view}: returning to a previously served key takes precedence over intervening input changes", %{
      project: project,
      opts: opts
    } do
      first = observation(project, 1)
      insert_chain(first, :remote, "v1")
      other = observation(project, 2)
      insert_chain(other, :remote, "v2", a_sources: "changed-sources")
      current = observation(project, 3)
      insert_chain(current, :miss, "v1")
      opts = Keyword.put(opts, :end_datetime, ~U[2024-04-03 23:59:59Z])
      assert_reasons(@view, opts, current, %{"A" => "evicted", "B" => "evicted", "C" => "evicted"})
    end
  end

  test "a named breakdown binds the same module batch for availability", %{project: project, opts: opts} do
    warmed = observation(project, 1)
    insert_chain(warmed, :remote, "v1")
    current = observation(project, 2)
    insert_chain(current, :miss, "v1")
    assert [row] = Analytics.module_invalidations(Keyword.put(opts, :name, "A"))
    assert row.name == "A"
    assert row.evicted == 1
  end

  test "availability remains correct across multiple bounded name batches", %{project: project, opts: opts} do
    warmed = observation(project, 1)
    current = observation(project, 2)

    targets =
      for index <- 1..257, {event, hit} <- [{warmed, 2}, {current, 0}] do
        %{
          id: UUIDv7.generate(),
          project_id: project.id,
          command_event_id: event.id,
          inserted_at: NaiveDateTime.truncate(event.created_at, :second),
          name: "Module#{index}",
          binary_cache_hash: "key#{index}",
          binary_cache_hit: hit
        }
      end

    IngestRepo.insert_all(XcodeTarget, targets)
    rows = Analytics.module_invalidations(Keyword.put(opts, :limit, 300))
    assert length(rows) == 257
    assert Enum.all?(rows, &(&1.evicted == 1 and &1.unclassified == 0))
  end

  defp observation(project, day, attrs \\ []) do
    created_at = Keyword.get_lazy(attrs, :observed_at, fn -> NaiveDateTime.new!(2024, 4, day, 10, 0, 0) end)

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: DateTime.from_naive!(created_at, "Etc/UTC"),
        xcode_version: Keyword.get(attrs, :xcode_version, "15.3"),
        is_ci: true
      )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      build_run_id: build.id,
      git_branch: Keyword.get(attrs, :git_branch, "main"),
      git_commit_sha: "same-commit",
      created_at: Keyword.get(attrs, :reported_at, created_at),
      ran_at: DateTime.from_naive!(created_at, "Etc/UTC"),
      cache_endpoint: Keyword.get(attrs, :cache_endpoint, "https://cache.example.com"),
      duration: Keyword.get(attrs, :duration, 0),
      is_ci: Keyword.get(attrs, :is_ci, true)
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
        binary_cache_hash: Keyword.get(attrs, :hash, "#{name}-#{Keyword.get(attrs, :key_revision, revision)}"),
        binary_cache_hit: hit,
        sources_hash: sources,
        target_settings_hash: settings,
        dependencies: dependencies,
        dependencies_hash: dependency_hash,
        additional_strings: Keyword.get(attrs, :additional_strings, ["Debug", compiler, "7"]),
        hashed_destinations: Keyword.get(attrs, :hashed_destinations, []),
        embedded_product_references_hash: Keyword.get(attrs, :embedded_product_references_hash),
        foreign_build_hash: Keyword.get(attrs, :foreign_build_hash),
        test_device: Keyword.get(attrs, :test_device),
        test_runtime: Keyword.get(attrs, :test_runtime)
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
        {row.name, {row.self_changes, row.dependency_induced, row.unclassified, row.evicted}}
      end)

    counts = %{
      "changed" => {1, 0, 0, 0},
      "upstream" => {0, 1, 0, 0},
      "cold" => {0, 0, 1, 0},
      "evicted" => {0, 0, 0, 1}
    }

    assert actual ==
             Map.new(expected, fn {name, reason} -> {name, Map.fetch!(counts, reason)} end)
  end
end
