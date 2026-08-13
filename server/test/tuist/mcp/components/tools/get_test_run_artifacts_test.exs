defmodule Tuist.MCP.Components.Tools.GetTestRunArtifactsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.CommandEvents
  alias Tuist.MCP.Components.Tools.GetTestRunArtifacts
  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests

  @project %{id: 1, name: "app", account: %{name: "acme"}}

  defp conn_with_subject, do: %Plug.Conn{assigns: %{current_subject: :subject}}

  defp authorized do
    stub(Projects, :get_project_by_id, fn 1 -> @project end)
    stub(Tuist.Authorization, :authorize, fn :test_read, :subject, _project -> :ok end)
  end

  defp stored(byte_size \\ 1024) do
    stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, byte_size} end)
    stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)
  end

  defp decode(result) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    JSON.decode!(text)
  end

  describe "get_test_run_artifacts" do
    test "returns a download URL for the result bundle and the session archive" do
      stub(Tests, :get_test, fn "run-1" -> {:ok, %{id: "run-1", project_id: 1}} end)
      authorized()
      stored(2048)

      result = decode(GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "run-1"}))

      assert result["test_run_id"] == "run-1"
      assert result["result_bundle"]["object_key"] == "acme/app/runs/run-1/result_bundle.zip"
      assert result["result_bundle"]["byte_size"] == 2048
      assert result["result_bundle"]["download_url"] == "https://storage.test/signed"
      assert result["session"]["object_key"] == "acme/app/runs/run-1/session.zip"
    end

    test "signs the URL for an hour" do
      stub(Tests, :get_test, fn "run-1" -> {:ok, %{id: "run-1", project_id: 1}} end)
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 1} end)

      stub(Storage, :generate_download_url, fn _object_key, _actor, opts ->
        assert Keyword.fetch!(opts, :expires_in) == 3600
        "https://storage.test/signed"
      end)

      result = decode(GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "run-1"}))

      assert result["result_bundle"]["expires_at"]
    end

    # An older `tuist test` run has no row in `test_runs`, only a command event,
    # and its bundle lives under the same `runs/<id>/` prefix.
    test "falls back to a command event when the id is not a test run" do
      stub(Tests, :get_test, fn "event-1" -> {:error, :not_found} end)
      stub(CommandEvents, :get_command_event_by_id, fn "event-1" -> {:ok, %{id: "event-1", project_id: 1}} end)
      authorized()
      stored()

      result = decode(GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "event-1"}))

      assert result["result_bundle"]["object_key"] == "acme/app/runs/event-1/result_bundle.zip"
    end

    # The row outliving its artifact is the common shape when someone looks into
    # a failure days later.
    test "reports a null artifact when the object was never stored" do
      stub(Tests, :get_test, fn "run-1" -> {:ok, %{id: "run-1", project_id: 1}} end)
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :not_found} end)

      result = decode(GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "run-1"}))

      assert result["result_bundle"] == nil
      assert result["session"] == nil
    end

    # "We could not look" must not read as "it was never uploaded".
    test "errors rather than reporting null when storage cannot be reached" do
      stub(Tests, :get_test, fn "run-1" -> {:ok, %{id: "run-1", project_id: 1}} end)
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :timeout} end)

      result = GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "run-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Could not reach artifact storage."
    end

    test "requires :test_read authorization" do
      stub(Tests, :get_test, fn "run-1" -> {:ok, %{id: "run-1", project_id: 1}} end)
      stub(Projects, :get_project_by_id, fn 1 -> @project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, _project -> {:error, :forbidden} end)
      reject(&Storage.get_object_size/2)

      result = GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "run-1"})

      assert %{"isError" => true} = result
    end

    test "reports a run that does not exist" do
      stub(Tests, :get_test, fn "missing" -> {:error, :not_found} end)
      stub(CommandEvents, :get_command_event_by_id, fn "missing" -> {:error, :not_found} end)

      result = GetTestRunArtifacts.call(conn_with_subject(), %{"test_run_id" => "missing"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Test run not found: missing"
    end

    test "requires a test_run_id" do
      result = GetTestRunArtifacts.call(conn_with_subject(), %{})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "test_run_id is required"
    end
  end
end
