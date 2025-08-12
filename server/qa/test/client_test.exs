defmodule Tuist.QA.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias QA.Client
  alias QA.LogStreamer

  describe "create_step/6" do
    test "makes POST request with correct parameters" do
      # Given
      summary = "Login test completed successfully"
      description = "Successfully completed login test with valid credentials"
      issues = ["Minor UI alignment issue in button"]
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}/steps"

        assert opts[:json] == %{summary: summary, description: description, issues: issues}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: ""}}
      end)

      # When
      result =
        Client.create_step(%{
          summary: summary,
          description: description,
          issues: issues,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == :ok
    end

    test "returns error on server failure" do
      # Given
      summary = "Failed test step"
      description = "Test failed due to timeout"
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
          summary: summary,
          description: description,
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
      assert result == :ok
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

        assert opts[:json] == %{status: "completed", summary: summary}
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
      assert result == :ok
    end
  end

  describe "screenshot_upload/6" do
    test "makes POST request and returns upload URL" do
      # Given
      name = "login_screen"
      title = "Login Screen"
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}/screenshots/upload"

        assert opts[:json] == %{file_name: name, title: title}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}

        {:ok,
         %{
           status: 200,
           body: %{"url" => "https://s3.example.com/upload-url", "expires_at" => 1_234_567_890}
         }}
      end)

      # When
      result =
        Client.screenshot_upload(%{
          file_name: name,
          title: title,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert {:ok, %{"url" => "https://s3.example.com/upload-url", "expires_at" => 1_234_567_890}} =
               result
    end
  end

  describe "create_screenshot/6" do
    test "makes POST request successfully" do
      # Given
      name = "success_screen"
      title = "Success Screen"
      server_url = "https://example.com"
      run_id = "test-run-123"
      auth_token = "test-token"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "#{server_url}/api/projects/test-account/test-project/qa/runs/#{run_id}/screenshots"

        assert opts[:json] == %{file_name: name, title: title}
        assert opts[:headers] == %{"Authorization" => "Bearer #{auth_token}"}
        {:ok, %{status: 201, body: ""}}
      end)

      # When
      result =
        Client.create_screenshot(%{
          file_name: name,
          title: title,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: "test-account",
          project_handle: "test-project"
        })

      # Then
      assert result == :ok
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
      message = "Test log message"
      level = "info"
      timestamp = DateTime.utc_now()

      expect(LogStreamer, :stream_log, fn pid, params ->
        assert pid == streamer_pid
        assert params.message == message
        assert params.level == level
        assert params.timestamp == timestamp
        :ok
      end)

      # When
      result =
        Client.stream_log(streamer_pid, %{
          message: message,
          level: level,
          timestamp: timestamp
        })

      # Then
      assert result == :ok
    end
  end
end
