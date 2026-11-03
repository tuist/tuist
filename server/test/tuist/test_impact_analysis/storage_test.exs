defmodule Tuist.TestImpactAnalysis.StorageTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Shards.TestReport
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  describe "diffs" do
    test "reads back the changed files it stored", %{project: project} do
      :ok =
        Storage.put_diff(%{
          project_id: project.id,
          commit_sha: "merge",
          baseline_sha: "base",
          changed_files: [
            %{path: "App/Cart.swift", status: "M", blob: "b1", affected_modules: ["AppTests"]},
            %{path: "README.md", status: "D"}
          ],
          changed_files_count: 2
        })

      assert {:ok, diff} = Storage.get_diff(project.id, "merge", "base")
      assert diff.changed_files_count == 2

      assert diff.changed_files == [
               %{path: "App/Cart.swift", status: "M", blob: "b1", affected_modules: ["AppTests"]},
               %{path: "README.md", status: "D", blob: "", affected_modules: []}
             ]

      assert Storage.get_diff(project.id, "merge", "other") == {:error, :not_found}
    end

    test "keeps the first 5,000 files and the diff's total size", %{project: project} do
      files = for index <- 1..5_001, do: %{path: "File#{index}.swift", status: "A", blob: "b#{index}"}

      :ok =
        Storage.put_diff(%{
          project_id: project.id,
          commit_sha: "head",
          baseline_sha: "base",
          changed_files: files,
          changed_files_count: 7_000
        })

      assert {:ok, diff} = Storage.get_diff(project.id, "head", "base")
      assert length(diff.changed_files) == 5_000
      assert diff.changed_files_count == 7_000
    end
  end

  describe "runs" do
    test "reads back a selected run and its tests", %{project: project} do
      test_case_id = Ecto.UUID.generate()

      {:ok, run} =
        Storage.create_run(
          %{
            project_id: project.id,
            head_sha: "head",
            commit_sha: "merge",
            baseline_sha: "base",
            git_branch: "feature",
            build_system: "xcode",
            platform: "ios",
            build_context: %{"scheme" => "App", "destination" => String.duplicate("x", 2_000), "secret" => "dropped"},
            requested_modules: ["AppTests"],
            outcome: "selected",
            rules_version: "1",
            rule_trace: [
              %{rule: "tracked_files", selected: 0, skipped: 0, verdict: "continue"},
              %{rule: "unaffected", selected: 0, skipped: 3, verdict: "done"}
            ],
            requested_count: 4,
            skipped_count: 3,
            selected_count: 1
          },
          [
            %{
              test_case_id: test_case_id,
              module_name: "AppTests",
              suite_name: "CartTests",
              name: "testTotal()",
              reason: "impacted",
              matched_path: "App/Cart.swift"
            }
          ]
        )

      assert {:ok, stored} = Storage.get_run(project.id, run.id)
      assert stored.outcome == "selected"
      assert stored.baseline_sha == "base"
      assert stored.platform == "ios"
      assert stored.requested_modules == ["AppTests"]
      assert stored.build_context |> Map.keys() |> Enum.sort() == ["destination", "scheme"]
      assert String.length(stored.build_context["destination"]) == 1_024
      assert [%{rule: "tracked_files"}, %{rule: "unaffected", skipped: 3, verdict: "done"}] = stored.rule_trace
      assert {stored.requested_count, stored.skipped_count, stored.selected_count} == {4, 3, 1}

      assert [
               %{
                 test_case_id: ^test_case_id,
                 module_name: "AppTests",
                 suite_name: "CartTests",
                 name: "testTotal()",
                 reason: "impacted",
                 matched_path: "App/Cart.swift"
               }
             ] = Storage.list_run_tests(project.id, run.id)
    end

    test "records a fallback without a baseline or tests", %{project: project} do
      {:ok, run} =
        Storage.create_run(%{
          project_id: project.id,
          head_sha: "head",
          commit_sha: "head",
          build_system: "xcode",
          outcome: "fallback",
          reason: "no_baseline"
        })

      assert {:ok, %{outcome: "fallback", reason: "no_baseline", baseline_sha: nil}} =
               Storage.get_run(project.id, run.id)

      assert Storage.list_run_tests(project.id, run.id) == []
    end

    test "rejects a run without its required fields", %{project: project} do
      assert {:error, changeset} = Storage.create_run(%{project_id: project.id, build_system: "xcode"})
      assert %{outcome: _, head_sha: _, commit_sha: _} = errors_on(changeset)
    end

    test "scopes reads to the project", %{project: project} do
      {:ok, run} =
        Storage.create_run(%{
          project_id: project.id,
          head_sha: "head",
          commit_sha: "head",
          build_system: "xcode",
          outcome: "fallback"
        })

      assert Storage.get_run(project.id + 1, run.id) == {:error, :not_found}
    end
  end

  describe "references to an impact run" do
    test "a shard plan stores the impact run it distributes", %{project: project} do
      run_id = Ecto.UUID.generate()
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, test_impact_run_id: run_id)

      assert {:ok, %{test_impact_run_id: ^run_id}} = Tuist.Shards.get_shard_plan(plan.id)
    end

    test "a test run stores the impact run of its invocation", %{project: project} do
      run_id = Ecto.UUID.generate()
      {:ok, test} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: run_id)

      assert {:ok, %{test_impact_run_id: ^run_id}} = Tests.get_test(test.id)
    end

    test "a sharded run's reports merge the impact run into the run summary", %{project: project} do
      run_id = Ecto.UUID.generate()
      id = Ecto.UUID.generate()
      ran_at = NaiveDateTime.utc_now()

      IngestRepo.insert_all(TestReport, [
        %{
          id: id,
          project_id: project.id,
          status: "success",
          build_system: "xcode",
          ran_at: ran_at,
          inserted_at: ran_at,
          execution_started_at: ran_at,
          shard_index: 0,
          shard_count: 1,
          report_phase: 2,
          reporting_version: 1,
          test_impact_run_id: run_id
        }
      ])

      assert %{test_impact_run_id: ^run_id} =
               IngestRepo.one(from(t in Test.query(), where: t.project_id == ^project.id and t.id == ^id))
    end
  end
end
