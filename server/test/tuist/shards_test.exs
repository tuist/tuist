defmodule Tuist.ShardsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Shards
  alias Tuist.Shards.ShardPlanTestSuite
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  defp planned_suite_durations(plan) do
    from(s in ShardPlanTestSuite,
      where: s.shard_plan_id == ^plan.id,
      select: {
        fragment("concat(?, '/', ?)", s.module_name, s.test_suite_name),
        s.estimated_duration_ms
      }
    )
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  defp planned_targets(result) do
    result.shard_assignments
    |> Enum.flat_map(fn assignment -> assignment["test_targets"] end)
    |> MapSet.new()
  end

  describe "create_shard_plan/2" do
    test "creates a shard plan with module-level granularity" do
      project = ProjectsFixtures.project_fixture()

      params = %{
        reference: "github-123-1",
        modules: ["AppTests", "CoreTests", "NetworkTests"],
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2
      assert length(result.shard_assignments) == 2

      all_targets =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(all_targets, MapSet.new(["AppTests", "CoreTests", "NetworkTests"]))
    end

    test "uses historical timing data for bin-packing" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{name: "SlowTests", status: "success", duration: 100_000, test_cases: []},
          %{name: "FastTests", status: "success", duration: 10_000, test_cases: []}
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "session-1",
        modules: ["SlowTests", "FastTests", "MediumTests"],
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2
    end

    test "uses timing data from non-default branches" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/some-branch",
        test_modules: [
          %{name: "SlowTests", status: "success", duration: 100_000, test_cases: []}
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "session-non-default",
        modules: ["SlowTests"],
        shard_total: 1
      }

      result = Shards.create_shard_plan(project, params)

      [assignment] = result.shard_assignments
      assert assignment["estimated_duration_ms"] == 100_000
    end

    test "creates a shard plan with suite-level granularity" do
      project = ProjectsFixtures.project_fixture()

      params = %{
        reference: "session-2",
        test_suites: ["LoginTest", "SignupTest", "ProfileTest"],
        granularity: "suite",
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2
    end

    test "uses the final suite shard as the catch-all" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      params = %{
        reference: "catch-all-1",
        test_suites: ["AppTests/LoginSuite", "AppTests/SignupSuite"],
        granularity: "suite",
        shard_max: 2
      }

      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)
      stub(Tuist.Storage, :generate_download_url, fn _key, _account -> "https://download.example.com" end)

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2

      assert result.shard_assignments == [
               %{"index" => 0, "test_targets" => ["AppTests/LoginSuite"], "estimated_duration_ms" => 5000},
               %{"index" => 1, "test_targets" => ["AppTests/SignupSuite"], "estimated_duration_ms" => 5000}
             ]

      catch_all_index = result.shard_count - 1

      assert {:ok, legacy_shard} = Shards.get_shard(project, account, "catch-all-1", catch_all_index)
      assert legacy_shard.skip == []
      assert legacy_shard.suites == %{"AppTests" => ["SignupSuite"]}

      assert {:ok, shard} =
               Shards.get_shard(project, account, "catch-all-1", catch_all_index, suite_catch_all?: true)

      # The catch-all carries no -only-testing and skips suites assigned to earlier shards, so it runs
      # its own planned suite plus any newly added / un-enumerated suites instead of dropping them.
      assert shard.modules == []
      assert shard.suites == %{}
      assert shard.skip == ["AppTests/LoginSuite"]

      # A regular shard still selects via suites, with an empty skip list.
      assert {:ok, regular} = Shards.get_shard(project, account, "catch-all-1", 0)
      assert regular.skip == []
      assert regular.suites == %{"AppTests" => ["LoginSuite"]}
    end

    test "catch-all shard downloads products for every module, including un-enumerated ones" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      # Only "AppTests" has suite history. "NewTests" is built and uploaded but has no recorded
      # suites, so it never appears in the plan's per-suite assignments — yet the catch-all still has
      # to run it (that's its whole purpose), so it must download its products.
      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 6_000},
              %{name: "SignupSuite", status: "success", duration: 4_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "catch-all-download-1",
        modules: ["AppTests", "NewTests"],
        granularity: "suite",
        shard_total: 2
      }

      # Split artifacts were uploaded (a shared bundle plus one per module). Echo the object key back
      # as the URL so we can assert which module products the shard is told to download.
      stub(Tuist.Storage, :object_exists?, fn _key, _account -> true end)
      stub(Tuist.Storage, :generate_download_url, fn key, _account -> key end)

      result = Shards.create_shard_plan(project, params)
      catch_all_index = result.shard_count - 1

      assert {:ok, shard} =
               Shards.get_shard(project, account, "catch-all-download-1", catch_all_index, suite_catch_all?: true)

      # The catch-all carries no -only-testing, but must still fetch every module's products so the
      # whole .xctestrun can load — including "NewTests", which has no planned suites.
      assert shard.modules == []
      assert Enum.any?(shard.download_urls, &String.ends_with?(&1, "/shared.aar"))
      assert Enum.any?(shard.download_urls, &String.ends_with?(&1, "/modules/AppTests.aar"))
      assert Enum.any?(shard.download_urls, &String.ends_with?(&1, "/modules/NewTests.aar"))

      # A regular shard downloads only its own suites' modules, not the un-enumerated ones.
      assert {:ok, regular} = Shards.get_shard(project, account, "catch-all-download-1", 0)
      assert Enum.any?(regular.download_urls, &String.ends_with?(&1, "/modules/AppTests.aar"))
      refute Enum.any?(regular.download_urls, &String.ends_with?(&1, "/modules/NewTests.aar"))
    end

    test "does not append a catch-all shard for module granularity" do
      project = ProjectsFixtures.project_fixture()

      params = %{
        reference: "no-catch-all-1",
        modules: ["AppTests", "CoreTests", "FeatureTests"],
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      # No extra shard appended; the module universe is the deterministic .xctestrun.
      assert result.shard_count == 2
    end

    test "matches suite timing data by module-qualified name" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 91_000,
            test_cases: [],
            test_suites: [
              %{name: "SlowSuite", status: "success", duration: 90_000},
              %{name: "FastSuite", status: "success", duration: 1_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "suite-qualified-timing",
        test_suites: ["AppTests/SlowSuite", "AppTests/FastSuite"],
        granularity: "suite",
        shard_total: 2
      }

      result = Shards.create_shard_plan(project, params)

      durations =
        result.shard_assignments
        |> Enum.reject(fn a -> a["test_targets"] == [] end)
        |> Map.new(fn a -> {hd(a["test_targets"]), a["estimated_duration_ms"]} end)

      assert durations["AppTests/SlowSuite"] == 90_000
      assert durations["AppTests/FastSuite"] == 1_000
    end

    test "prices suites of a parallelizable module by the module's measured concurrency" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "ParallelTests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites:
              Enum.map(1..4, fn index ->
                %{name: "Suite#{index}", status: "success", duration: 20_000}
              end)
          },
          %{
            name: "SerialTests",
            status: "success",
            duration: 30_000,
            test_cases: [],
            test_suites: [
              %{name: "SlowSuite", status: "success", duration: 20_000},
              %{name: "FastSuite", status: "success", duration: 10_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "suite-parallelism",
        parallelizable_modules: ["ParallelTests"],
        test_suites: [
          "ParallelTests/Suite1",
          "ParallelTests/Suite2",
          "ParallelTests/Suite3",
          "ParallelTests/Suite4",
          "SerialTests/SlowSuite",
          "SerialTests/FastSuite"
        ],
        granularity: "suite",
        shard_total: 6
      }

      result = Shards.create_shard_plan(project, params)
      durations = planned_suite_durations(result.plan)

      # ParallelTests finishes in 20s while its suites report 80s, so each suite costs a quarter of
      # what it reports. SerialTests' suites already add up to its wall clock and stay as measured.
      assert durations["ParallelTests/Suite1"] == 5_000
      assert durations["ParallelTests/Suite4"] == 5_000
      assert durations["SerialTests/SlowSuite"] == 20_000
      assert durations["SerialTests/FastSuite"] == 10_000
    end

    test "packs a parallelizable module alongside other work instead of giving it a whole shard" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "ParallelTests",
            status: "success",
            duration: 30_000,
            test_cases: [],
            test_suites:
              Enum.map(1..4, fn index ->
                %{name: "Suite#{index}", status: "success", duration: 30_000}
              end)
          },
          %{
            name: "SerialTests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites: [
              %{name: "SlowSuite", status: "success", duration: 10_000},
              %{name: "FastSuite", status: "success", duration: 10_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "suite-parallelism-packing",
        parallelizable_modules: ["ParallelTests"],
        test_suites: [
          "ParallelTests/Suite1",
          "ParallelTests/Suite2",
          "ParallelTests/Suite3",
          "ParallelTests/Suite4",
          "SerialTests/SlowSuite",
          "SerialTests/FastSuite"
        ],
        granularity: "suite",
        shard_total: 2
      }

      result = Shards.create_shard_plan(project, params)

      totals = Enum.map(result.shard_assignments, fn a -> a["estimated_duration_ms"] end)

      # Unscaled, ParallelTests alone reports 120s against SerialTests' 20s and fills a shard by
      # itself. Scaled to its 30s wall clock the plan is 50s of work that splits evenly.
      assert Enum.sum(totals) == 50_000
      assert Enum.max(totals) == 25_000
    end

    test "leaves a module the client did not declare parallelizable at its measured durations" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "ParallelTests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites:
              Enum.map(1..4, fn index ->
                %{name: "Suite#{index}", status: "success", duration: 20_000}
              end)
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      suites = Enum.map(1..4, fn index -> "ParallelTests/Suite#{index}" end)

      # History shows this module running four suites concurrently, but whether it still does is the
      # client's to state. Without a declaration the measured concurrency is not applied at all,
      # rather than being carried over from runs whose configuration may no longer hold.
      undeclared =
        Shards.create_shard_plan(project, %{
          reference: "undeclared",
          test_suites: suites,
          granularity: "suite",
          shard_total: 1
        })

      assert Map.values(planned_suite_durations(undeclared.plan)) == List.duplicate(20_000, 4)

      declared =
        Shards.create_shard_plan(project, %{
          reference: "declared",
          parallelizable_modules: ["ParallelTests"],
          test_suites: suites,
          granularity: "suite",
          shard_total: 1
        })

      assert Map.values(planned_suite_durations(declared.plan)) == List.duplicate(5_000, 4)
    end

    test "prices a partial suite inventory by what the plan actually holds" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "ParallelTests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites:
              Enum.map(1..4, fn index ->
                %{name: "Suite#{index}", status: "success", duration: 20_000}
              end)
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      # The module runs four suites concurrently in 20s, so history measures a factor of 4. A plan
      # holding one of them still has to wait for that suite in full: the other three are not there
      # to overlap with, so it cannot be priced at a quarter.
      single =
        Shards.create_shard_plan(project, %{
          reference: "partial-one",
          parallelizable_modules: ["ParallelTests"],
          test_suites: ["ParallelTests/Suite1"],
          granularity: "suite",
          shard_total: 1
        })

      assert planned_suite_durations(single.plan) == %{"ParallelTests/Suite1" => 20_000}

      # Two of the four overlap with each other and nothing else, so together they cost one suite.
      pair =
        Shards.create_shard_plan(project, %{
          reference: "partial-two",
          parallelizable_modules: ["ParallelTests"],
          test_suites: ["ParallelTests/Suite1", "ParallelTests/Suite2"],
          granularity: "suite",
          shard_total: 1
        })

      assert planned_suite_durations(pair.plan) == %{
               "ParallelTests/Suite1" => 10_000,
               "ParallelTests/Suite2" => 10_000
             }
    end

    test "measures concurrency from deduplicated rows" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites:
              Enum.map(1..4, fn index ->
                %{name: "Suite#{index}", status: "success", duration: 10_000}
              end)
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      # Both tables are ReplacingMergeTree keyed on the row id, so a rewritten row leaves a second
      # physical copy until the parts merge. A duplicated module row multiplies through the join
      # into every one of its suites on top of the duplicated suite rows themselves.
      IngestRepo.query!(
        "INSERT INTO test_module_runs SELECT * FROM test_module_runs WHERE project_id = {project_id:Int64}",
        %{project_id: project.id}
      )

      IngestRepo.query!(
        "INSERT INTO test_suite_runs SELECT * FROM test_suite_runs WHERE project_id = {project_id:Int64}",
        %{project_id: project.id}
      )

      result =
        Shards.create_shard_plan(project, %{
          reference: "deduplicated",
          parallelizable_modules: ["AppTests"],
          test_suites: [
            "AppTests/Suite1",
            "AppTests/Suite2",
            "AppTests/Suite3",
            "AppTests/Suite4"
          ],
          granularity: "suite",
          shard_total: 1
        })

      # 40s of suites in a 20s module is a factor of 2. Counting the physical copies would read it
      # as 4 or 8 and halve every suite.
      assert planned_suite_durations(result.plan) == %{
               "AppTests/Suite1" => 5_000,
               "AppTests/Suite2" => 5_000,
               "AppTests/Suite3" => 5_000,
               "AppTests/Suite4" => 5_000
             }
    end

    test "ignores concurrency measured from a module run with a single suite" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1_000,
            test_cases: [],
            test_suites: [%{name: "OnlySuite", status: "success", duration: 40_000}]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "suite-single",
        parallelizable_modules: ["AppTests"],
        test_suites: ["AppTests/OnlySuite"],
        granularity: "suite",
        shard_total: 1
      }

      result = Shards.create_shard_plan(project, params)

      [assignment] = result.shard_assignments
      assert assignment["estimated_duration_ms"] == 40_000
    end

    test "clamps concurrency so an inconsistently recorded module wall clock cannot zero it out" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 100,
            test_cases: [],
            test_suites:
              Enum.map(1..20, fn index ->
                %{name: "Suite#{index}", status: "success", duration: 40_000}
              end)
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      suites = Enum.map(1..20, fn index -> "AppTests/Suite#{index}" end)

      params = %{
        reference: "suite-clamped",
        parallelizable_modules: ["AppTests"],
        test_suites: suites,
        granularity: "suite",
        shard_total: 1
      }

      result = Shards.create_shard_plan(project, params)
      durations = planned_suite_durations(result.plan)

      # The raw ratio is 8000x. Twenty planned suites leave the per-plan cap at 20, so the clamp is
      # what holds the divisor at 16 rather than pricing the module at nothing.
      assert Map.values(durations) == List.duplicate(2_500, 20)
    end

    test "leaves module granularity timing untouched" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "ParallelTests",
            status: "success",
            duration: 10_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 20_000},
              %{name: "SignupSuite", status: "success", duration: 20_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "module-untouched",
        modules: ["ParallelTests"],
        granularity: "module",
        shard_total: 1
      }

      result = Shards.create_shard_plan(project, params)

      [assignment] = result.shard_assignments
      assert assignment["estimated_duration_ms"] == 10_000
    end

    test "derives suite units from history when the client does not enumerate" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 6_000},
              %{name: "SignupSuite", status: "success", duration: 4_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      # No test_suites: the client did not enumerate. Units come from historical suite timings,
      # scoped to the modules in the build.
      params = %{
        reference: "history-derived-1",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(planned, MapSet.new(["AppTests/LoginSuite", "AppTests/SignupSuite"]))
    end

    test "derives suite units from history when test_suites is present but nil" do
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: project.default_branch,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 6_000},
              %{name: "SignupSuite", status: "success", duration: 4_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      # The controller always sets test_suites from the request body, so a client that no longer
      # enumerates suites yields test_suites: nil (key present, value nil) rather than an omitted key.
      params = %{
        reference: "history-derived-nil",
        modules: ["AppTests"],
        test_suites: nil,
        granularity: "suite",
        shard_total: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(planned, MapSet.new(["AppTests/LoginSuite", "AppTests/SignupSuite"]))
    end

    test "derives suite units from history on other branches when no preferred branch has any" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")

      # Tests only ever run on pull-request branches, so the default branch has no history. The
      # build run the current branch would be read from is unresolvable here (it is written through
      # an async ingestion buffer in production and is typically still unflushed at plan time), so
      # neither preferred branch resolves anything.
      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/only-branch-with-history",
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 6_000},
              %{name: "SignupSuite", status: "success", duration: 4_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "history-derived-other-branch",
        modules: ["AppTests"],
        test_suites: nil,
        granularity: "suite",
        shard_total: 2
      }

      result = Shards.create_shard_plan(project, params)

      assert result.shard_count == 2

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(planned, MapSet.new(["AppTests/LoginSuite", "AppTests/SignupSuite"]))
    end

    test "prefers the linked build branch inventory over history on unrelated branches" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/unrelated",
        ran_at: NaiveDateTime.utc_now(),
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 7_000,
            test_cases: [],
            test_suites: [
              %{name: "UnrelatedSuite", status: "success", duration: 7_000}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/some-branch",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day),
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "BranchOnlySuite", status: "success", duration: 3_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          is_ci: true,
          git_branch: "feature/some-branch"
        )

      params = %{
        reference: "linked-branch-beats-fallback",
        modules: ["AppTests"],
        test_suites: nil,
        granularity: "suite",
        shard_total: 2,
        build_run_id: build.id
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      # The fallback must not pull in the newer run from the unrelated branch when the build's own
      # branch has history.
      assert MapSet.equal?(planned, MapSet.new(["AppTests/BranchOnlySuite"]))
    end

    test "prefers suite inventory from the linked build branch" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      older_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day)
      latest_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        ran_at: older_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 9_000,
            test_cases: [],
            test_suites: [
              %{name: "DeletedSuite", status: "success", duration: 9_000}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/some-branch",
        ran_at: NaiveDateTime.utc_now(),
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 7_000,
            test_cases: [],
            test_suites: [
              %{name: "BranchOnlySuite", status: "success", duration: 7_000}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        ran_at: latest_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 3_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          is_ci: true,
          git_branch: "feature/some-branch"
        )

      params = %{
        reference: "linked-build-branch-inventory",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 3,
        build_run_id: build.id
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(planned, MapSet.new(["AppTests/BranchOnlySuite"]))
    end

    test "uses the latest preferred branch suite inventory per module" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      default_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -4, :day)
      branch_older_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day)
      branch_latest_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        ran_at: default_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1_000,
            test_cases: [],
            test_suites: [
              %{name: "DefaultAppSuite", status: "success", duration: 1_000}
            ]
          },
          %{
            name: "CoreTests",
            status: "success",
            duration: 2_000,
            test_cases: [],
            test_suites: [
              %{name: "DefaultCoreSuite", status: "success", duration: 2_000}
            ]
          },
          %{
            name: "UITests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "DefaultUISuite", status: "success", duration: 3_000}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/selective",
        ran_at: branch_older_ran_at,
        test_modules: [
          %{
            name: "CoreTests",
            status: "success",
            duration: 2_500,
            test_cases: [],
            test_suites: [
              %{name: "BranchCoreSuite", status: "success", duration: 2_500}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/selective",
        ran_at: branch_latest_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1_500,
            test_cases: [],
            test_suites: [
              %{name: "BranchAppSuite", status: "success", duration: 1_500}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          is_ci: true,
          git_branch: "feature/selective"
        )

      params = %{
        reference: "per-module-branch-inventory",
        modules: ["AppTests", "CoreTests", "UITests"],
        granularity: "suite",
        shard_total: 3,
        build_run_id: build.id
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(
               planned,
               MapSet.new([
                 "AppTests/BranchAppSuite",
                 "CoreTests/BranchCoreSuite",
                 "UITests/DefaultUISuite"
               ])
             )
    end

    test "falls back to default branch suite inventory when linked build branch has no suite history" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "LoginSuite", status: "success", duration: 3_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          is_ci: true,
          git_branch: "feature/no-suite-history"
        )

      params = %{
        reference: "default-branch-fallback-inventory",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 3,
        build_run_id: build.id
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(planned, MapSet.new(["AppTests/LoginSuite"]))
    end

    # A run asked for a handful of a module's suites says nothing about what the module contains, so
    # it can't stand in for the module's inventory. The reported project's default branch runs only
    # such a job (an eight-suite smoke selection), which is what a branch with no history of its own
    # would otherwise inherit.
    test "ignores runs restricted to a caller-supplied selection while unrestricted history exists" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      smoke_suites = ["SmokeCartSuite", "SmokeHomeSuite"]
      full_suites = smoke_suites ++ ["CheckoutSuite", "OrderTrackingSuite", "SearchSuite"]

      for ran_at <- [-2, -1] do
        RunsFixtures.test_fixture(
          project_id: project.id,
          is_ci: true,
          git_branch: "main",
          has_explicit_test_selection: true,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), ran_at, :day),
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 4_000,
              test_cases: [],
              test_suites: Enum.map(smoke_suites, &%{name: &1, status: "success", duration: 2_000})
            }
          ]
        )
      end

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/full",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day),
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites: Enum.map(full_suites, &%{name: &1, status: "success", duration: 4_000})
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "restricted-history",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 2,
        git_branch: "feature/no-history-yet"
      }

      result = Shards.create_shard_plan(project, params)

      assert MapSet.equal?(
               planned_targets(result),
               MapSet.new(Enum.map(full_suites, &"AppTests/#{&1}"))
             )
    end

    # A run that restricts a module to specific suites doesn't have to be guessed at: the client
    # knows the selection and sends it, and it is the only thing that will run for that module.
    # Modules the client says nothing about still come from history.
    test "plans the client's declared suites for the modules that declare them" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 4_000,
            test_cases: [],
            test_suites: [
              %{name: "HistorySuite", status: "success", duration: 2_000},
              %{name: "AnotherHistorySuite", status: "success", duration: 2_000}
            ]
          },
          %{
            name: "CoreTests",
            status: "success",
            duration: 2_000,
            test_cases: [],
            test_suites: [%{name: "CoreSuite", status: "success", duration: 2_000}]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "declared-suites",
        modules: ["AppTests", "CoreTests"],
        test_suites: ["AppTests/DeclaredSuite"],
        granularity: "suite",
        shard_total: 2,
        git_branch: "main"
      }

      result = Shards.create_shard_plan(project, params)

      assert MapSet.equal?(
               planned_targets(result),
               MapSet.new(["AppTests/DeclaredSuite", "CoreTests/CoreSuite"])
             )
    end

    # The reported failure: a UI test module whose suites are spread across the shards that ran
    # them. Every shard of a run reports under one test run, they upload as each shard finishes, and
    # the catch-all shard finishes last, so the newest run is a fraction of the module when the next
    # plan is created. Reading only that run planned the fraction and left the rest to the catch-all
    # shard, which then ran them all serially.
    test "plans every suite of a sharded module while the newest run is still being ingested" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      branch = "feature/ui-tests"
      previous_run_id = UUIDv7.generate()
      previous_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :hour)
      newest_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -30, :minute)

      previous_run_shards = [
        ["CoreFlowFoodStoreCSESuite"],
        ["CoreFlowFoodStoreSuite", "StoreWallA11ySuite"],
        ["CheckoutA11ySuite", "OrderTrackingA11ySuite"],
        ["CartA11ySuite", "StoreA11ySuite", "HomeA11ySuite", "MealVoucherSuite", "RatingsSuite"]
      ]

      for {suites, shard_index} <- Enum.with_index(previous_run_shards) do
        RunsFixtures.test_fixture(
          id: previous_run_id,
          project_id: project.id,
          is_ci: true,
          git_branch: branch,
          ran_at: previous_ran_at,
          shard_index: shard_index,
          test_modules: [
            %{
              name: "UITests",
              status: "success",
              duration: 60_000,
              test_cases: [],
              test_suites: Enum.map(suites, &%{name: &1, status: "success", duration: 20_000})
            }
          ]
        )
      end

      # The run in flight: shard 0 has uploaded, the shards holding everything else have not.
      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: branch,
        ran_at: newest_ran_at,
        shard_index: 0,
        test_modules: [
          %{
            name: "UITests",
            status: "success",
            duration: 20_000,
            test_cases: [],
            test_suites: [
              %{name: "CoreFlowFoodStoreCSESuite", status: "success", duration: 20_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "sharded-partial-ingestion",
        modules: ["UITests"],
        granularity: "suite",
        shard_total: 4,
        git_branch: branch
      }

      result = Shards.create_shard_plan(project, params)

      assert MapSet.equal?(
               planned_targets(result),
               MapSet.new(Enum.map(List.flatten(previous_run_shards), &"UITests/#{&1}"))
             )

      # Nothing is left over for the catch-all shard to absorb, which is what made the last shard
      # run for 34 minutes while the others finished in three.
      catch_all = Enum.find(result.shard_assignments, &(&1["index"] == 3))
      assert length(catch_all["test_targets"]) < 5
    end

    # The other half of the reported failure: the branch under test runs the full UI suite while the
    # default branch runs a smaller nightly job. The plan links a build run that the async ingestion
    # buffer has not made readable yet, so the branch can only come from the parameter the CLI sends.
    # Without it the plan is the nightly's inventory and everything else falls to the catch-all shard.
    test "plans the branch's suites when the linked build run is not readable yet" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      branch = "feature/ui-tests"
      nightly_suites = ["CoreFlowFoodStoreCSESuite", "CartA11ySuite"]
      branch_suites = nightly_suites ++ ["MealVoucherSuite", "RatingsSuite", "HomeAdsSuite"]

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        test_modules: [
          %{
            name: "UITests",
            status: "success",
            duration: 40_000,
            test_cases: [],
            test_suites: Enum.map(nightly_suites, &%{name: &1, status: "success", duration: 20_000})
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: branch,
        test_modules: [
          %{
            name: "UITests",
            status: "success",
            duration: 100_000,
            test_cases: [],
            test_suites: Enum.map(branch_suites, &%{name: &1, status: "success", duration: 20_000})
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      base_params = %{
        modules: ["UITests"],
        granularity: "suite",
        shard_total: 3,
        build_run_id: Ecto.UUID.generate()
      }

      unreadable_build_run =
        Shards.create_shard_plan(project, Map.put(base_params, :reference, "unreadable-build-run"))

      assert MapSet.equal?(
               planned_targets(unreadable_build_run),
               MapSet.new(Enum.map(nightly_suites, &"UITests/#{&1}"))
             )

      with_git_branch =
        Shards.create_shard_plan(
          project,
          base_params |> Map.put(:reference, "git-branch-sent") |> Map.put(:git_branch, branch)
        )

      assert MapSet.equal?(
               planned_targets(with_git_branch),
               MapSet.new(Enum.map(branch_suites, &"UITests/#{&1}"))
             )
    end

    test "unions the branch suite inventory across recent runs" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      older_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day)
      latest_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/sharded",
        ran_at: older_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "CartSuite", status: "success", duration: 1_000},
              %{name: "CheckoutSuite", status: "success", duration: 1_000},
              %{name: "HomeSuite", status: "success", duration: 1_000}
            ]
          }
        ]
      )

      # A sharded execution uploads one test run per shard job, and the catch-all shard finishes
      # last, so moments after a build the newest run holds only a fraction of the module's suites.
      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/sharded",
        ran_at: latest_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1_000,
            test_cases: [],
            test_suites: [
              %{name: "CartSuite", status: "success", duration: 1_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "union-branch-inventory",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 2,
        git_branch: "feature/sharded"
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(
               planned,
               MapSet.new([
                 "AppTests/CartSuite",
                 "AppTests/CheckoutSuite",
                 "AppTests/HomeSuite"
               ])
             )
    end

    test "unions the any-branch fallback suite inventory across recent runs" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      older_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day)
      latest_ran_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/elsewhere",
        ran_at: older_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 2_000,
            test_cases: [],
            test_suites: [
              %{name: "CartSuite", status: "success", duration: 1_000},
              %{name: "CheckoutSuite", status: "success", duration: 1_000}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/elsewhere",
        ran_at: latest_ran_at,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1_000,
            test_cases: [],
            test_suites: [
              %{name: "CartSuite", status: "success", duration: 1_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "union-fallback-inventory",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 2,
        git_branch: "feature/no-history"
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(
               planned,
               MapSet.new(["AppTests/CartSuite", "AppTests/CheckoutSuite"])
             )
    end

    test "prefers the git_branch param over the linked build run's branch" do
      project = ProjectsFixtures.project_fixture(default_branch: "main")

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "main",
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "DefaultSuite", status: "success", duration: 3_000}
            ]
          }
        ]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        is_ci: true,
        git_branch: "feature/current",
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 3_000,
            test_cases: [],
            test_suites: [
              %{name: "CurrentSuite", status: "success", duration: 3_000}
            ]
          }
        ]
      )

      RunsFixtures.optimize_test_runs()

      params = %{
        reference: "git-branch-param-inventory",
        modules: ["AppTests"],
        granularity: "suite",
        shard_total: 2,
        git_branch: "feature/current"
      }

      result = Shards.create_shard_plan(project, params)

      planned =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(planned, MapSet.new(["AppTests/CurrentSuite"]))
    end

    test "stores build_run_id on the shard plan" do
      project = ProjectsFixtures.project_fixture()
      build_run_id = Ecto.UUID.generate()

      params = %{
        reference: "build-link-1",
        modules: ["AppTests"],
        shard_max: 2,
        build_run_id: build_run_id
      }

      result = Shards.create_shard_plan(project, params)
      {:ok, plan} = Shards.get_shard_plan(result.plan.id)
      assert plan.build_run_id == build_run_id
    end

    test "stores gradle_build_id on the shard plan" do
      project = ProjectsFixtures.project_fixture()
      gradle_build_id = Ecto.UUID.generate()

      params = %{
        reference: "gradle-link-1",
        modules: ["AppTests"],
        shard_max: 2,
        gradle_build_id: gradle_build_id
      }

      result = Shards.create_shard_plan(project, params)
      {:ok, plan} = Shards.get_shard_plan(result.plan.id)
      assert plan.gradle_build_id == gradle_build_id
    end
  end

  describe "create_shard_plan/2 edge cases" do
    test "creates a plan with empty modules list" do
      project = ProjectsFixtures.project_fixture()

      params = %{
        reference: "empty-modules-1",
        modules: [],
        shard_min: 3,
        shard_max: 5
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 1
      assert result.shard_assignments == [%{"index" => 0, "test_targets" => [], "estimated_duration_ms" => 0}]
    end

    test "uses shard_total override regardless of module count" do
      project = ProjectsFixtures.project_fixture()

      params = %{
        reference: "total-override-1",
        modules: ["A", "B", "C", "D", "E", "F"],
        shard_total: 3
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 3
      assert length(result.shard_assignments) == 3

      all_targets =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(all_targets, MapSet.new(["A", "B", "C", "D", "E", "F"]))
    end

    test "suite granularity with Module/Suite format names" do
      project = ProjectsFixtures.project_fixture()

      params = %{
        reference: "suite-split-1",
        test_suites: ["AppTests/LoginSuite", "AppTests/SignupSuite", "CoreTests/UtilSuite"],
        granularity: "suite",
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2
      assert length(result.shard_assignments) == 2

      all_targets =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(
               all_targets,
               MapSet.new(["AppTests/LoginSuite", "AppTests/SignupSuite", "CoreTests/UtilSuite"])
             )
    end
  end

  describe "get_shard_plan/1" do
    test "returns the shard plan when it exists" do
      project = ProjectsFixtures.project_fixture()

      plan =
        ShardsFixtures.shard_plan_fixture(
          project_id: project.id,
          reference: "get-plan-1",
          shard_count: 3
        )

      assert {:ok, fetched_plan} = Shards.get_shard_plan(plan.id)
      assert fetched_plan.id == plan.id
      assert fetched_plan.shard_count == 3
      assert fetched_plan.reference == "get-plan-1"
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Shards.get_shard_plan(Ecto.UUID.generate())
    end
  end

  describe "start_upload/3" do
    test "starts a multipart upload and returns upload_id" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      ShardsFixtures.shard_plan_fixture(
        project_id: project.id,
        reference: "upload-ref-1"
      )

      stub(Tuist.Storage, :multipart_start, fn key, _account ->
        assert key =~ "shards/"
        assert key =~ "/bundle.zip"
        "test-upload-id"
      end)

      assert {:ok, "test-upload-id"} = Shards.start_upload(project, account, "upload-ref-1")
    end

    test "starts a multipart upload for an already-created shard plan" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan =
        ShardsFixtures.shard_plan_fixture(
          project_id: project.id,
          reference: "upload-ref-2"
        )

      stub(Tuist.Storage, :multipart_start, fn key, _account ->
        assert key == Shards.bundle_object_key(account, project, plan.id)
        "test-upload-id"
      end)

      assert {:ok, "test-upload-id"} = Shards.start_upload_for_plan(project, account, plan)
    end

    test "starts a multipart upload for a shard plan id without reading the plan" do
      project = ProjectsFixtures.project_fixture()
      account = project.account
      plan_id = Ecto.UUID.generate()

      stub(Tuist.Storage, :multipart_start, fn key, _account ->
        assert key == Shards.bundle_object_key(account, project, plan_id)
        "test-upload-id"
      end)

      assert {:ok, "test-upload-id"} = Shards.start_upload_for_plan_id(project, account, plan_id)
    end

    test "returns not_found when plan does not exist" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      assert {:error, :not_found} = Shards.start_upload(project, account, "nonexistent-ref")
    end
  end

  describe "get_shard/4" do
    test "returns the requested plan when multiple plans share a reference" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      requested_plan =
        ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "reused-reference", granularity: "module")

      latest_plan =
        ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "reused-reference", granularity: "module")

      ShardsFixtures.shard_plan_module_fixture(
        shard_plan_id: requested_plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "RequestedTests"
      )

      ShardsFixtures.shard_plan_module_fixture(
        shard_plan_id: latest_plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "LatestTests"
      )

      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)
      stub(Tuist.Storage, :generate_download_url, fn key, _account -> key end)

      assert {:ok, result} = Shards.get_shard_for_plan_id(project, account, requested_plan.id, 0)
      assert result.shard_plan_id == requested_plan.id
      assert result.modules == ["RequestedTests"]
      assert String.contains?(result.download_url, requested_plan.id)
    end

    test "does not return a plan from another project by id" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      plan = ShardsFixtures.shard_plan_fixture(project_id: other_project.id, reference: "other-project")

      assert {:error, :not_found} =
               Shards.get_shard_for_plan_id(project, project.account, plan.id, 0)
    end

    test "returns modules for module granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "plan-1", granularity: "module")

      ShardsFixtures.shard_plan_module_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "AppTests"
      )

      ShardsFixtures.shard_plan_module_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "CoreTests"
      )

      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "plan-1", 0)
      assert Enum.sort(result.modules) == ["AppTests", "CoreTests"]
      assert result.suites == %{}
      assert result.download_url == "https://download.example.com"
      assert result.download_urls == ["https://download.example.com"]
    end

    test "returns suites grouped by module for suite granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan =
        ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "plan-2", granularity: "suite")

      ShardsFixtures.shard_plan_test_suite_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "AppTests",
        test_suite_name: "LoginTests"
      )

      ShardsFixtures.shard_plan_test_suite_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "AppTests",
        test_suite_name: "SignupTests"
      )

      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "plan-2", 0)
      assert result.modules == ["AppTests"]
      assert Enum.sort(result.suites["AppTests"]) == ["LoginTests", "SignupTests"]
      assert result.download_url == "https://download.example.com"
      assert result.download_urls == ["https://download.example.com"]
    end

    test "returns shared plus per-module download urls when split artifacts exist" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan =
        ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "plan-split", granularity: "module")

      ShardsFixtures.shard_plan_module_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "AppTests"
      )

      ShardsFixtures.shard_plan_module_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "CoreTests"
      )

      stub(Tuist.Storage, :object_exists?, fn _key, _account -> true end)
      stub(Tuist.Storage, :generate_download_url, fn key, _account -> key end)

      assert {:ok, result} = Shards.get_shard(project, account, "plan-split", 0)
      assert result.download_url == nil
      assert length(result.download_urls) == 3
      assert Enum.any?(result.download_urls, &String.ends_with?(&1, "/shared.aar"))

      assert "#{account.id}/#{project.id}/shards/#{plan.id}/modules/AppTests.aar" in result.download_urls

      assert "#{account.id}/#{project.id}/shards/#{plan.id}/modules/CoreTests.aar" in result.download_urls
    end

    test "returns legacy final suite shard as assigned suites when no catch-all rows exist" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan =
        ShardsFixtures.shard_plan_fixture(
          project_id: project.id,
          reference: "legacy-suite-plan",
          granularity: "suite",
          shard_count: 2
        )

      ShardsFixtures.shard_plan_test_suite_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 0,
        module_name: "AppTests",
        test_suite_name: "LoginTests"
      )

      ShardsFixtures.shard_plan_test_suite_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        shard_index: 1,
        module_name: "AppTests",
        test_suite_name: "SignupTests"
      )

      stub(Tuist.Storage, :object_exists?, fn _key, _account -> false end)

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "legacy-suite-plan", 1)
      assert result.modules == ["AppTests"]
      assert result.suites == %{"AppTests" => ["SignupTests"]}
      assert result.skip == []
    end

    test "returns error for nonexistent plan" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      assert {:error, :not_found} =
               Shards.get_shard(project, account, "nonexistent", 0)
    end

    test "returns error for out-of-range shard index" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "plan-3", granularity: "module")

      assert {:error, :invalid_shard_index} =
               Shards.get_shard(project, account, "plan-3", 5)
    end
  end

  describe "generate_upload_url/5" do
    test "returns upload URL" do
      project = ProjectsFixtures.project_fixture()
      account = project.account
      ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "session-1")

      stub(Tuist.Storage, :multipart_generate_url, fn _key, _upload_id, _part_number, _account ->
        "https://upload.example.com/part"
      end)

      assert {:ok, url} = Shards.generate_upload_url(project, account, "session-1", "upload-id", 1)
      assert url == "https://upload.example.com/part"
    end

    test "returns upload URL for an already-created shard plan id" do
      project = ProjectsFixtures.project_fixture()
      account = project.account
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "session-2")

      stub(Tuist.Storage, :multipart_generate_url, fn key, _upload_id, _part_number, _account ->
        assert key == Shards.bundle_object_key(account, project, plan.id)
        "https://upload.example.com/part"
      end)

      assert {:ok, url} = Shards.generate_upload_url_for_plan(project, account, plan.id, "upload-id", 1)
      assert url == "https://upload.example.com/part"
    end
  end

  describe "complete_upload/5" do
    test "completes the multipart upload" do
      project = ProjectsFixtures.project_fixture()
      account = project.account
      ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "session-1")

      stub(Tuist.Storage, :multipart_complete_upload, fn _key, _upload_id, _parts, _account ->
        :ok
      end)

      assert :ok =
               Shards.complete_upload(project, account, "session-1", "upload-id", [])
    end

    test "completes the multipart upload for an already-created shard plan id" do
      project = ProjectsFixtures.project_fixture()
      account = project.account
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "session-2")

      stub(Tuist.Storage, :multipart_complete_upload, fn key, _upload_id, _parts, _account ->
        assert key == Shards.bundle_object_key(account, project, plan.id)
        :ok
      end)

      assert :ok =
               Shards.complete_upload_for_plan(project, account, plan.id, "upload-id", [])
    end
  end
end
