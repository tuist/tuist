defmodule Tuist.MCP.Components.Tools.GetXcodeBuildArchiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Builds
  alias Tuist.MCP.Components.Tools.GetXcodeBuildArchive
  alias Tuist.Projects
  alias Tuist.Storage

  @project %{id: 1, name: "app", account: %{name: "acme"}}

  defp conn_with_subject, do: %Plug.Conn{assigns: %{current_subject: :subject}}

  defp authorized do
    stub(Builds, :get_build, fn "build-1" -> {:ok, %{id: "build-1", project_id: 1}} end)
    stub(Projects, :get_project_by_id, fn 1 -> @project end)
    stub(Tuist.Authorization, :authorize, fn :build_read, :subject, _project -> :ok end)
  end

  defp decode(result) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    JSON.decode!(text)
  end

  describe "get_xcode_build_archive" do
    test "returns a download URL for the uploaded build archive" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 8192} end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)

      result = decode(GetXcodeBuildArchive.call(conn_with_subject(), %{"build_run_id" => "build-1"}))

      assert result["build_run_id"] == "build-1"
      assert result["archive"]["object_key"] == "acme/app/builds/build-1/build.zip"
      assert result["archive"]["byte_size"] == 8192
      assert result["archive"]["download_url"] == "https://storage.test/signed"
    end

    test "reports a null archive when the build was never uploaded" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :not_found} end)

      result = decode(GetXcodeBuildArchive.call(conn_with_subject(), %{"build_run_id" => "build-1"}))

      assert result["archive"] == nil
    end

    test "errors rather than reporting null when storage cannot be reached" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :timeout} end)

      result = GetXcodeBuildArchive.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Could not reach artifact storage."
    end

    test "requires :build_read authorization" do
      stub(Builds, :get_build, fn "build-1" -> {:ok, %{id: "build-1", project_id: 1}} end)
      stub(Projects, :get_project_by_id, fn 1 -> @project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, _project -> {:error, :forbidden} end)
      reject(&Storage.get_object_size/2)

      result = GetXcodeBuildArchive.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"isError" => true} = result
    end

    test "reports a build that does not exist" do
      stub(Builds, :get_build, fn "missing" -> {:error, :not_found} end)

      result = GetXcodeBuildArchive.call(conn_with_subject(), %{"build_run_id" => "missing"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Build not found: missing"
    end

    test "requires a build_run_id" do
      result = GetXcodeBuildArchive.call(conn_with_subject(), %{})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "build_run_id is required"
    end
  end
end
