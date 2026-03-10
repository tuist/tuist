defmodule Tuist.Builds.Workers.ProcessBuildWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Builds.Workers.ProcessBuildWorker
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

  defp job_args(build_id, account_id, project_id, opts \\ []) do
    xcode_cache_upload_enabled = Keyword.get(opts, :xcode_cache_upload_enabled, true)

    %{
      "build_id" => build_id,
      "storage_key" => @storage_key,
      "account_id" => account_id,
      "project_id" => project_id,
      "xcode_cache_upload_enabled" => xcode_cache_upload_enabled
    }
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
        "cpuUsagePercent" => 75.5,
        "memoryUsedBytes" => 8_000_000_000,
        "memoryTotalBytes" => 16_000_000_000,
        "networkBytesIn" => 1_000_000,
        "networkBytesOut" => 500_000,
        "diskBytesRead" => 2_000_000,
        "diskBytesWritten" => 1_500_000
      },
      %{
        "timestamp" => 1_710_000_005,
        "cpuUsagePercent" => 82.3,
        "memoryUsedBytes" => 8_500_000_000,
        "memoryTotalBytes" => 16_000_000_000,
        "networkBytesIn" => 1_200_000,
        "networkBytesOut" => 600_000,
        "diskBytesRead" => 2_500_000,
        "diskBytesWritten" => 1_800_000
      }
    ])
  end

  describe "perform/1 with processor_url configured (HTTP path)" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> "http://localhost:4002" end)
      stub(Tuist.Environment, :processor_webhook_secret, fn -> "test-secret" end)
      :ok
    end

    test "sends build to remote processor and writes result", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Req, :post, fn url, opts ->
        assert url == "http://localhost:4002/webhooks/process-build"
        body = Jason.decode!(opts[:body])
        assert body["build_id"] == build.id
        assert body["storage_key"] == @storage_key
        assert body["xcode_cache_upload_enabled"] == true
        assert Enum.any?(opts[:headers], fn {k, _v} -> k == "x-webhook-signature" end)
        {:ok, %{status: 200, body: parsed_data()}}
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
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "converts machine metrics from camelCase to snake_case", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: parsed_data_with_machine_metrics()}}
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
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "signs webhook request with HMAC-SHA256", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Req, :post, fn _url, opts ->
        body = opts[:body]
        {_, signature} = Enum.find(opts[:headers], fn {k, _v} -> k == "x-webhook-signature" end)

        expected_signature =
          :hmac
          |> :crypto.mac(:sha256, "test-secret", body)
          |> Base.encode16(case: :lower)

        assert signature == expected_signature
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Builds, :create_build, fn _attrs -> {:ok, %{id: build.id}} end)

      assert :ok ==
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "marks build as failed when processor returns non-200", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "internal error"}}}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        assert attrs.id == build.id
        {:ok, %{id: build.id}}
      end)

      assert {:error, _} =
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "marks build as failed when HTTP request fails", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Req, :post, fn _url, _opts ->
        {:error, :timeout}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, :timeout} =
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end
  end

  describe "perform/1 without processor_url (local processing path)" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> nil end)
      :ok
    end

    test "processes locally when processor module is available", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, path, ^account ->
        assert String.ends_with?(path, ".zip")
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn path, true ->
        assert String.ends_with?(path, ".zip")
        {:ok, parsed_data()}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == build.id
        assert attrs.project_id == project.id
        assert attrs.duration == 1200
        assert attrs.status == "success"
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "processes locally with machine metrics", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn _path, true ->
        {:ok, parsed_data_with_machine_metrics()}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert length(attrs.machine_metrics) == 2

        [first | _] = attrs.machine_metrics
        assert first.timestamp == 1_710_000_000
        assert first.cpu_usage_percent == 75.5
        assert first.memory_used_bytes == 8_000_000_000
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "marks build as failed when download fails", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:error, :not_found}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, :not_found} =
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "marks build as failed when local processing returns error", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn _path, _xcode_cache_upload_enabled ->
        {:error, {:parse_failed, "NIF not loaded"}}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, {:parse_failed, "NIF not loaded"}} =
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "marks build as failed when account is not found", %{project: project, build: build} do
      expect(Tuist.Accounts, :get_account_by_id, fn _id ->
        {:error, :not_found}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: build.id}}
      end)

      assert {:error, :not_found} =
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, "999999", project.id)
               })
    end
  end

  describe "perform/1 with empty processor_url" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> "" end)
      :ok
    end

    test "treats empty string as unconfigured and processes locally", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn path, true ->
        assert String.ends_with?(path, ".zip")
        {:ok, parsed_data()}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == build.id
        assert attrs.status == "success"
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end
  end

  describe "perform/1 replace_build_run" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> "http://localhost:4002" end)
      stub(Tuist.Environment, :processor_webhook_secret, fn -> "test-secret" end)
      :ok
    end

    test "preserves original build fields when merging with parsed data", %{
      account: account,
      project: project,
      build: build
    } do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: parsed_data()}}
      end)

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
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end

    test "handles missing machine_metrics in parsed data gracefully", %{
      account: account,
      project: project,
      build: build
    } do
      data_without_metrics = Map.delete(parsed_data(), "machine_metrics")

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: data_without_metrics}}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.machine_metrics == []
        {:ok, %{id: build.id}}
      end)

      assert :ok ==
               ProcessBuildWorker.perform(%Oban.Job{
                 args: job_args(build.id, account.id, project.id)
               })
    end
  end
end
