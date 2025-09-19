defmodule Runner.QA.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Runner.QA.Client
  alias Runner.QA.LogStreamer

  describe "create_step/6" do
    test "makes POST request with correct parameters" do
      # Given
      action = "Login test completed successfully"
      result = "Successfully completed login test with valid credentials"
      issues = ["Minor UI alignment issue in button"]
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}/steps"

        assert opts[:json] == %{action: action, result: result, issues: issues}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: ""}}
      end)

      # When
      result =
        Client.create_step(%{
          action: action,
          result: result,
          issues: issues,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == {:ok, ""}
    end

    test "returns error on server failure" do
      # Given
      action = "Failed test step"
      result = "Test failed due to timeout"
      issues = ["Timeout error", "Server unresponsive"]
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn _opts ->
        {:ok, %{status: 500}}
      end)

      # When
      result =
        Client.create_step(%{
          action: action,
          result: result,
          issues: issues,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == {:error, "Server returned unexpected status 500"}
    end

    test "includes started_at in request body when provided" do
      # Given
      action = "Test step with timestamp"
      issues = []
      started_at = DateTime.utc_now()
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}/steps"

        assert opts[:json] == %{
                 action: action,
                 issues: issues,
                 started_at: DateTime.to_iso8601(started_at)
               }

        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: %{"id" => "step-123"}}}
      end)

      # When
      result =
        Client.create_step(%{
          action: action,
          issues: issues,
          started_at: started_at,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == {:ok, "step-123"}
    end
  end

  describe "start_run/3" do
    test "makes PATCH request to update status to running" do
      # Given
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :patch, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}"

        assert opts[:json] == %{status: "running"}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: ""}}
      end)

      # When
      result =
        Client.start_run(%{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == {:ok, ""}
    end
  end

  describe "finalize_run/4" do
    test "makes PATCH request with correct parameters" do
      # Given
      summary = "All tests completed successfully"
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :patch, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}"

        assert opts[:json] == %{status: "completed"}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: ""}}
      end)

      # When
      result =
        Client.finalize_run(%{
          summary: summary,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == {:ok, ""}
    end
  end

  describe "create_screenshot/6" do
    test "makes POST request successfully" do
      # Given
      step_id = "test-step-123"
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}/screenshots"

        assert opts[:json] == %{step_id: step_id}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: ""}}
      end)

      # When
      result =
        Client.create_screenshot(%{
          step_id: step_id,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == {:ok, ""}
    end
  end

  describe "start_log_stream/1" do
    test "starts LogStreamer with correct parameters" do
      # Given
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(LogStreamer, :start_link, fn params ->
        assert params.server_url == server_url
        assert params.run_id == run_id
        assert params.auth_token == auth_token
        {:ok, :fake_pid}
      end)

      # When
      result =
        Client.start_log_stream(%{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token
        })

      # Then
      assert result == {:ok, :fake_pid}
    end
  end

  describe "stream_log/2" do
    test "forwards log message to LogStreamer" do
      # Given
      streamer_pid = :fake_pid
      data = JSON.encode!(%{"message" => "Test log message"})
      type = "message"
      timestamp = DateTime.utc_now()

      expect(LogStreamer, :stream_log, fn pid, params ->
        assert pid == streamer_pid
        assert params.data == data
        assert params.type == type
        assert params.timestamp == timestamp
        :ok
      end)

      # When
      result =
        Client.stream_log(streamer_pid, %{
          data: data,
          type: type,
          timestamp: timestamp
        })

      # Then
      assert result == :ok
    end
  end

  describe "upload_recording/1" do
    test "successfully uploads recording in chunks" do
      # Given
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"
      account_handle = "test-account"
      project_handle = "test-project"
      recording_path = "/tmp/recording.mp4"
      file_size = 10_485_760
      started_at = DateTime.utc_now()
      duration_ms = 60_000

      stub(File, :stat, fn ^recording_path, [:size] ->
        {:ok, %{size: file_size}}
      end)

      stub(File, :stream!, fn ^recording_path, _chunk_size, [] ->
        ["chunk1_data_5MB", "chunk2_data_5MB"]
      end)

      expect(Req, :post, 1, fn opts ->
        if String.ends_with?(opts[:url], "/recordings/upload/start") do
          {:ok, %{status: 201, body: %{"upload_id" => "upload-123", "storage_key" => "test-key"}}}
        end
      end)

      expect(Req, :post, 2, fn opts ->
        if String.ends_with?(opts[:url], "/recordings/upload/generate-url") do
          part_number = opts[:json][:part_number]

          {:ok,
           %{
             status: 200,
             body: %{"url" => "https://s3.example.com/presigned-url-part-#{part_number}"}
           }}
        end
      end)

      expect(Req, :put, 2, fn url, _opts ->
        assert String.starts_with?(url, "https://s3.example.com/presigned-url-part-")
        {:ok, %{status: 200, headers: [{"etag", ["\"etag-for-part\""]}]}}
      end)

      expect(Req, :post, 1, fn opts ->
        if String.ends_with?(opts[:url], "/recordings/upload/complete") do
          assert opts[:json][:parts] == [
                   %{part_number: 1, etag: "etag-for-part"},
                   %{part_number: 2, etag: "etag-for-part"}
                 ]

          assert opts[:json][:started_at] == DateTime.to_iso8601(started_at)
          assert opts[:json][:duration] == duration_ms
          {:ok, %{status: 200, body: %{"status" => "success"}}}
        end
      end)

      # When
      result =
        Client.upload_recording(%{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          recording_path: recording_path,
          started_at: started_at,
          duration_ms: duration_ms
        })

      # Then
      assert result == {:ok, %{upload_id: "upload-123", storage_key: "test-key"}}
    end
  end
end
