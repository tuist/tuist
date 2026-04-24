defmodule Tuist.Builds.Workers.ProcessBuildWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Builds.Workers.ProcessBuildWorker
  alias Tuist.Processor.BuildProcessor
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup :verify_on_exit!

  @storage_key "tuist/builds/test-archive.zip"

  setup do
    %{account: account} =
      TuistTestSupport.Fixtures.AccountsFixtures.user_fixture(preload: [:account])

    project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: account.id,
        status: "processing",
        duration: 0
      )

    %{account: account, project: project, build: build}
  end

  defp job_args(build_id, account_id, project_id) do
    %{
      "build_id" => build_id,
      "storage_key" => @storage_key,
      "account_id" => account_id,
      "project_id" => project_id,
      "xcode_cache_upload_enabled" => true
    }
  end

  defp oban_job(args, attempt \\ 1, max_attempts \\ 3) do
    %Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}
  end

  defp parsed_data do
    %{
      "duration" => 1200,
      "status" => "success",
      "targets" => [%{"name" => "App", "duration" => 800, "status" => "success"}],
      "issues" => [],
      "files" => [],
      "cacheable_tasks" => [],
      "cas_outputs" => [],
      "machine_metrics" => []
    }
  end

  defp parsed_data_with_machine_metrics do
    Map.put(parsed_data(), "machine_metrics", [
      %{
        "timestamp" => 1_710_000_000,
        "cpu_usage_percent" => 75.5,
        "memory_used_bytes" => 8_000_000_000,
        "memory_total_bytes" => 16_000_000_000,
        "network_bytes_in" => 1_000_000,
        "network_bytes_out" => 500_000,
        "disk_bytes_read" => 2_000_000,
        "disk_bytes_written" => 1_500_000
      },
      %{
        "timestamp" => 1_710_000_005,
        "cpu_usage_percent" => 82.3,
        "memory_used_bytes" => 8_500_000_000,
        "memory_total_bytes" => 16_000_000_000,
        "network_bytes_in" => 1_200_000,
        "network_bytes_out" => 600_000,
        "disk_bytes_read" => 2_500_000,
        "disk_bytes_written" => 1_800_000
      }
    ])
  end

  describe "perform/1 happy path" do
    test "downloads, parses and writes the build run", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, path, ^account ->
        assert String.ends_with?(path, ".zip")
        {:ok, :done}
      end)

      expect(BuildProcessor, :process_build, fn path, true ->
        assert String.ends_with?(path, ".zip")
        {:ok, parsed_data()}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == build.id
        assert attrs.project_id == project.id
        assert attrs.duration == 1200
        assert attrs.status == "success"
        assert attrs.machine_metrics == []
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id)))
    end

    test "atomizes machine metrics keys", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)

      expect(BuildProcessor, :process_build, fn _path, true ->
        {:ok, parsed_data_with_machine_metrics()}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert length(attrs.machine_metrics) == 2

        [first, second] = attrs.machine_metrics
        assert first.timestamp == 1_710_000_000
        assert first.cpu_usage_percent == 75.5
        assert first.memory_used_bytes == 8_000_000_000
        assert first.memory_total_bytes == 16_000_000_000
        assert first.network_bytes_in == 1_000_000
        assert first.network_bytes_out == 500_000
        assert first.disk_bytes_read == 2_000_000
        assert first.disk_bytes_written == 1_500_000

        assert second.timestamp == 1_710_000_005
        assert second.cpu_usage_percent == 82.3
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id)))
    end
  end

  describe "perform/1 failure handling" do
    test "does not mark build as failed on non-final download error", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:error, :closed} end)
      reject(&Tuist.Builds.create_build/1)

      assert {:error, :closed} =
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id), 1, 3))
    end

    test "marks build as failed when download fails on final attempt", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:error, :not_found} end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, :not_found} =
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id), 3, 3))
    end

    test "marks build as failed when parse errors on final attempt", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)

      expect(BuildProcessor, :process_build, fn _path, _ ->
        {:error, {:parse_failed, "NIF not loaded"}}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, {:parse_failed, "NIF not loaded"}} =
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id), 3, 3))
    end

    test "marks build as failed when account is not found on final attempt", %{
      project: project,
      build: build
    } do
      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:error, :not_found} end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, :not_found} =
               ProcessBuildWorker.perform(oban_job(job_args(build.id, "999999", project.id), 3, 3))
    end
  end

  describe "perform/1 VCS comment" do
    test "enqueues VCS comment after successful processing when vcs_comment_params present", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)
      expect(BuildProcessor, :process_build, fn _, _ -> {:ok, parsed_data()} end)
      expect(Tuist.Builds, :create_build, fn _attrs -> {:ok, %{id: build.id}} end)

      vcs_params = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/1/merge",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id,
        "build_url_template" => "http://localhost/builds/:build_id"
      }

      expect(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn params ->
        assert params["git_commit_sha"] == "abc123"
        assert params["git_ref"] == "refs/pull/1/merge"
        assert params["project_id"] == project.id
        {:ok, %{}}
      end)

      args = build.id |> job_args(account.id, project.id) |> Map.put("vcs_comment_params", vcs_params)

      assert ProcessBuildWorker.perform(oban_job(args))
    end

    test "does not enqueue VCS comment when vcs_comment_params not present", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)
      expect(BuildProcessor, :process_build, fn _, _ -> {:ok, parsed_data()} end)
      expect(Tuist.Builds, :create_build, fn _attrs -> {:ok, %{id: build.id}} end)
      reject(&Tuist.VCS.enqueue_vcs_pull_request_comment/1)

      assert :ok ==
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id)))
    end

    test "does not enqueue VCS comment on failed processing", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)

      expect(BuildProcessor, :process_build, fn _, _ ->
        {:error, {:parse_failed, "boom"}}
      end)

      expect(Tuist.Builds, :create_build, fn _attrs -> {:ok, %{id: build.id}} end)
      reject(&Tuist.VCS.enqueue_vcs_pull_request_comment/1)

      assert {:error, _} =
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id), 3, 3))
    end
  end

  describe "perform/1 mark_failed_build_processing" do
    test "preserves existing build fields when marking as failed", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:error, :timeout} end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        assert attrs.duration == 0
        assert attrs.id == build.id
        assert attrs.account_id == account.id
        assert attrs.xcode_version == build.xcode_version
        assert attrs.macos_version == build.macos_version
        assert attrs.is_ci == build.is_ci
        {:ok, %{id: build.id}}
      end)

      assert {:error, :timeout} =
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id), 3, 3))
    end

    test "uses build metadata when no existing build found", %{
      account: account,
      project: project
    } do
      non_existent_build_id = Ecto.UUID.generate()

      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:error, :not_found} end)

      build_metadata = %{
        "xcode_version" => "16.0",
        "macos_version" => "15.0",
        "is_ci" => true,
        "scheme" => "App",
        "git_branch" => "main",
        "git_commit_sha" => "abc123"
      }

      expect(Tuist.Builds, :get_build, fn ^non_existent_build_id -> {:error, :not_found} end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        assert attrs.duration == 0
        assert attrs.id == non_existent_build_id
        assert attrs.xcode_version == "16.0"
        assert attrs.macos_version == "15.0"
        assert attrs.is_ci == true
        assert attrs.scheme == "App"
        assert attrs.git_branch == "main"
        assert attrs.git_commit_sha == "abc123"
        {:ok, %{id: non_existent_build_id}}
      end)

      args =
        non_existent_build_id
        |> job_args(account.id, project.id)
        |> Map.put("build_metadata", build_metadata)

      assert {:error, _} = ProcessBuildWorker.perform(oban_job(args, 3, 3))
    end
  end

  describe "perform/1 replace_build_run" do
    test "preserves original build fields when merging with parsed data", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)
      expect(BuildProcessor, :process_build, fn _, _ -> {:ok, parsed_data()} end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == build.id
        assert attrs.project_id == project.id
        assert attrs.account_id == account.id
        assert attrs.is_ci == false
        assert attrs.duration == 1200
        assert attrs.status == "success"
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id)))
    end

    test "does not carry over stale cacheable task counts from existing build", %{
      account: account,
      project: project,
      build: build
    } do
      parsed_data_with_cache =
        Map.put(parsed_data(), "cacheable_tasks", [
          %{
            "type" => "swift",
            "status" => "hit_remote",
            "key" => "cache-key-1",
            "description" => "Compiling Module",
            "read_duration" => 15.0,
            "write_duration" => nil,
            "cas_output_node_ids" => []
          },
          %{
            "type" => "swift",
            "status" => "hit_local",
            "key" => "cache-key-2",
            "description" => "Compiling OtherModule",
            "read_duration" => 10.0,
            "write_duration" => nil,
            "cas_output_node_ids" => []
          },
          %{
            "type" => "clang",
            "status" => "miss",
            "key" => "cache-key-3",
            "description" => "Compiling CModule",
            "read_duration" => nil,
            "write_duration" => 20.0,
            "cas_output_node_ids" => []
          }
        ])

      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)

      expect(BuildProcessor, :process_build, fn _, _ ->
        {:ok, parsed_data_with_cache}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        refute Map.has_key?(attrs, :cacheable_tasks_count)
        refute Map.has_key?(attrs, :cacheable_task_local_hits_count)
        refute Map.has_key?(attrs, :cacheable_task_remote_hits_count)
        assert length(attrs.cacheable_tasks) == 3
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id)))
    end

    test "handles missing machine_metrics in parsed data gracefully", %{
      account: account,
      project: project,
      build: build
    } do
      data_without_metrics = Map.delete(parsed_data(), "machine_metrics")

      expect(Tuist.Storage, :download_to_file, fn _, _, _ -> {:ok, :done} end)

      expect(BuildProcessor, :process_build, fn _, _ ->
        {:ok, data_without_metrics}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.machine_metrics == []
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(oban_job(job_args(build.id, account.id, project.id)))
    end
  end
end
