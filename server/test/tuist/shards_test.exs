defmodule Tuist.ShardsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Shards
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  describe "create_shard_plan/2" do
    test "creates a shard plan with module-level granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.ClickHouseRepo, :all, fn _query -> [] end)
      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id-123" end)

      params = %{
        reference: "github-123-1",
        modules: ["AppTests", "CoreTests", "NetworkTests"],
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2
      assert result.upload_id == "upload-id-123"
      assert length(result.shard_assignments) == 2

      all_targets =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(all_targets, MapSet.new(["AppTests", "CoreTests", "NetworkTests"]))
    end

    test "uses historical timing data for bin-packing" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.ClickHouseRepo, :all, fn _query ->
        [
          %{name: "SlowTests", avg_duration: 100_000.0},
          %{name: "FastTests", avg_duration: 10_000.0}
        ]
      end)

      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id" end)

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
      account = project.account

      stub(Tuist.ClickHouseRepo, :all, fn _query -> [] end)
      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id" end)

      params = %{
        reference: "session-2",
        test_suites: ["LoginTest", "SignupTest", "ProfileTest"],
        granularity: "suite",
        shard_max: 2
      }

      result = Shards.create_shard_plan(project, params)
      assert result.shard_count == 2
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

      ShardsFixtures.optimize_shard_plans()
      ShardsFixtures.optimize_shard_plan_modules()

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

      ShardsFixtures.optimize_shard_plans()
      ShardsFixtures.optimize_shard_plan_test_suites()

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "plan-2", 0)
      assert result.modules == ["AppTests"]
      assert result.suites == %{"AppTests" => ["LoginTests", "SignupTests"]}
      assert result.download_url == "https://download.example.com"
    end

    test "returns error for nonexistent plan" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      ShardsFixtures.optimize_shard_plans()

      assert {:error, :not_found} =
               Shards.get_shard(project, account, "nonexistent", 0)
    end

    test "returns error for out-of-range shard index" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      ShardsFixtures.shard_plan_fixture(project_id: project.id, reference: "plan-3", granularity: "module")
      ShardsFixtures.optimize_shard_plans()
      ShardsFixtures.optimize_shard_plan_modules()

      assert {:error, :invalid_shard_index} =
               Shards.get_shard(project, account, "plan-3", 5)
    end
  end

  describe "generate_upload_url/5" do
    test "returns upload URL" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

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

      stub(Tuist.Storage, :multipart_complete_upload, fn _key, _upload_id, _parts, _account ->
        :ok
      end)

      assert :ok =
               Shards.complete_upload(project, account, "session-1", "upload-id", [])
    end
  end
end
