defmodule Tuist.ShardsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Shards
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

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

    test "returns not_found when plan does not exist" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      assert {:error, :not_found} = Shards.start_upload(project, account, "nonexistent-ref")
    end
  end

  describe "get_shard/4" do
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

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "plan-1", 0)
      assert Enum.sort(result.modules) == ["AppTests", "CoreTests"]
      assert result.suites == %{}
      assert result.download_url == "https://download.example.com"
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

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "plan-2", 0)
      assert result.modules == ["AppTests"]
      assert Enum.sort(result.suites["AppTests"]) == ["LoginTests", "SignupTests"]
      assert result.download_url == "https://download.example.com"
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
  end
end
