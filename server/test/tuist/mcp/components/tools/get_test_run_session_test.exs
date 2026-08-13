defmodule Tuist.MCP.Components.Tools.GetTestRunSessionTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.GetTestRunSession
  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests

  # The record lookup, the command-event fallback and the authorization check
  # live in `Tuist.MCP.TestRunArtifact`, shared with `get_test_run_result_bundle`
  # and covered there. These cover what is specific to this tool.

  @project %{id: 1, name: "app", account: %{name: "acme"}}

  defp conn_with_subject, do: %Plug.Conn{assigns: %{current_subject: :subject}}

  defp authorized do
    stub(Tests, :get_test, fn "run-1" -> {:ok, %{id: "run-1", project_id: 1}} end)
    stub(Projects, :get_project_by_id, fn 1 -> @project end)
    stub(Tuist.Authorization, :authorize, fn :test_read, :subject, _project -> :ok end)
  end

  defp decode(result) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    JSON.decode!(text)
  end

  describe "get_test_run_session" do
    test "returns a download URL for the session archive" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 512} end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)

      result = decode(GetTestRunSession.call(conn_with_subject(), %{"test_run_id" => "run-1"}))

      assert result["test_run_id"] == "run-1"
      assert result["session"]["object_key"] == "acme/app/runs/run-1/session.zip"
      assert result["session"]["byte_size"] == 512
      assert result["session"]["download_url"] == "https://storage.test/signed"
    end

    test "reports a null session when the object was never stored" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :not_found} end)

      result = decode(GetTestRunSession.call(conn_with_subject(), %{"test_run_id" => "run-1"}))

      assert result["session"] == nil
    end

    test "errors rather than reporting null when storage cannot be reached" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :timeout} end)

      result = GetTestRunSession.call(conn_with_subject(), %{"test_run_id" => "run-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Could not reach artifact storage."
    end

    test "requires a test_run_id" do
      result = GetTestRunSession.call(conn_with_subject(), %{})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "test_run_id is required"
    end
  end
end
