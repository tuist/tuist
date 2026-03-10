defmodule Tuist.Builds.Workers.ProcessBuildWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds.Workers.ProcessBuildWorker

  setup :verify_on_exit!

  @build_id "B12673DA-1345-4077-BB30-D7576FEACE09"
  @storage_key "tuist/builds/test-archive.zip"
  @project_id "P12673DA-1345-4077-BB30-D7576FEACE09"

  setup do
    %{account: account} =
      TuistTestSupport.Fixtures.AccountsFixtures.user_fixture(preload: [:account])

    %{account: account}
  end

  defp job_args(account_id, opts \\ []) do
    xcode_cache_upload_enabled = Keyword.get(opts, :xcode_cache_upload_enabled, true)

    %{
      "build_id" => @build_id,
      "storage_key" => @storage_key,
      "account_id" => account_id,
      "project_id" => @project_id,
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
      "cas_outputs" => []
    }
  end

  describe "perform/1 with processor_url configured (HTTP path)" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> "http://localhost:4002" end)
      stub(Tuist.Environment, :processor_webhook_secret, fn -> "test-secret" end)
      :ok
    end

    test "sends build to remote processor and writes result to ClickHouse", %{account: account} do
      expect(Req, :post, fn url, opts ->
        assert url == "http://localhost:4002/webhooks/process-build"
        body = Jason.decode!(opts[:body])
        assert body["build_id"] == @build_id
        assert body["storage_key"] == @storage_key
        assert body["xcode_cache_upload_enabled"] == true
        assert Enum.any?(opts[:headers], fn {k, _v} -> k == "x-webhook-signature" end)
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Builds, :get_build, fn @build_id -> nil end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == @build_id
        assert attrs.project_id == @project_id
        assert attrs.duration == 1200
        assert attrs.status == "success"
        {:ok, %{id: @build_id}}
      end)

      assert :ok == ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end

    test "marks build as failed when processor returns non-200", %{account: account} do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "internal error"}}}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        assert attrs.id == @build_id
        {:ok, %{id: @build_id}}
      end)

      assert {:error, _} = ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end

    test "marks build as failed when HTTP request fails", %{account: account} do
      expect(Req, :post, fn _url, _opts ->
        {:error, :timeout}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: @build_id}}
      end)

      assert {:error, :timeout} =
               ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end
  end

  describe "perform/1 without processor_url (local processing path)" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> nil end)
      :ok
    end

    test "processes locally when processor module is available", %{account: account} do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, path, ^account ->
        assert String.ends_with?(path, ".zip")
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn path, true ->
        assert String.ends_with?(path, ".zip")
        {:ok, parsed_data()}
      end)

      expect(Tuist.Builds, :get_build, fn @build_id -> nil end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == @build_id
        assert attrs.project_id == @project_id
        assert attrs.duration == 1200
        assert attrs.status == "success"
        {:ok, %{id: @build_id}}
      end)

      assert :ok == ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end

    test "marks build as failed when download fails", %{account: account} do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:error, :not_found}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: @build_id}}
      end)

      assert {:error, :not_found} =
               ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end

    test "marks build as failed when local processing returns error", %{account: account} do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn _path, _xcode_cache_upload_enabled ->
        {:error, {:parse_failed, "NIF not loaded"}}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: @build_id}}
      end)

      assert {:error, {:parse_failed, "NIF not loaded"}} =
               ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end

    test "marks build as failed when account is not found" do
      expect(Tuist.Accounts, :get_account_by_id, fn _id ->
        {:error, :not_found}
      end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.status == "failed_processing"
        {:ok, %{id: @build_id}}
      end)

      assert {:error, :not_found} =
               ProcessBuildWorker.perform(%Oban.Job{args: job_args("999999")})
    end
  end

  describe "perform/1 with empty processor_url" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> "" end)
      :ok
    end

    test "treats empty string as unconfigured and processes locally", %{account: account} do
      expect(Tuist.Storage, :download_to_file, fn @storage_key, _path, ^account ->
        {:ok, :done}
      end)

      expect(Processor.BuildProcessor, :process_build, fn path, true ->
        assert String.ends_with?(path, ".zip")
        {:ok, parsed_data()}
      end)

      expect(Tuist.Builds, :get_build, fn @build_id -> nil end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.id == @build_id
        assert attrs.status == "success"
        {:ok, %{id: @build_id}}
      end)

      assert :ok == ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end
  end

  describe "perform/1 replace_build_run" do
    setup do
      stub(Tuist.Environment, :processor_url, fn -> "http://localhost:4002" end)
      stub(Tuist.Environment, :processor_webhook_secret, fn -> "test-secret" end)
      :ok
    end

    test "sets project_id on parsed data before writing", %{account: account} do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Builds, :get_build, fn @build_id -> nil end)

      expect(Tuist.Builds, :create_build, fn attrs ->
        assert attrs.project_id == @project_id
        {:ok, %{id: @build_id}}
      end)

      assert :ok == ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end

    test "returns error when create_build fails", %{account: account} do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Builds, :get_build, fn @build_id -> nil end)

      expect(Tuist.Builds, :create_build, fn _attrs ->
        {:error, %Ecto.Changeset{errors: [id: {"is invalid", []}]}}
      end)

      assert {:error, "failed_to_create_build"} =
               ProcessBuildWorker.perform(%Oban.Job{args: job_args(account.id)})
    end
  end
end
