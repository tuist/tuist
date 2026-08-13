defmodule Tuist.MCP.Components.Tools.GetPreviewAppBuildTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.AppBuilds
  alias Tuist.MCP.Components.Tools.GetPreviewAppBuild
  alias Tuist.Projects
  alias Tuist.Storage

  @project %{id: 1, name: "app", account: %{name: "acme"}}

  defp conn_with_subject, do: %Plug.Conn{assigns: %{current_subject: :subject}}

  defp app_build(attrs \\ %{}) do
    Map.merge(
      %{
        id: "app-build-1",
        preview_id: "preview-1",
        preview: %{id: "preview-1", project_id: 1},
        type: :ipa,
        supported_platforms: [:ios]
      },
      attrs
    )
  end

  defp authorized(attrs \\ %{}) do
    stub(AppBuilds, :app_build_by_id, fn "app-build-1", _opts -> {:ok, app_build(attrs)} end)
    stub(Projects, :get_project_by_id, fn 1 -> @project end)
    stub(Tuist.Authorization, :authorize, fn :preview_read, :subject, _project -> :ok end)
  end

  defp decode(result) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    JSON.decode!(text)
  end

  describe "get_preview_app_build" do
    test "returns a download URL for the app build" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 40_960} end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)

      result = decode(GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "app-build-1"}))

      assert result["app_build_id"] == "app-build-1"
      assert result["preview_id"] == "preview-1"
      assert result["type"] == "ipa"
      assert result["supported_platforms"] == ["ios"]
      assert result["build"]["object_key"] == "acme/app/previews/app-build-1.zip"
      assert result["build"]["download_url"] == "https://storage.test/signed"
    end

    test "uses the apk extension for an Android build" do
      authorized(%{type: :apk, supported_platforms: [:android]})
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 1} end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)

      result = decode(GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "app-build-1"}))

      assert result["build"]["object_key"] == "acme/app/previews/app-build-1.apk"
    end

    test "reports a null build when the binary was never uploaded" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :not_found} end)

      result = decode(GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "app-build-1"}))

      assert result["build"] == nil
    end

    test "errors rather than reporting null when storage cannot be reached" do
      authorized()
      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :timeout} end)

      result = GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "app-build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Could not reach artifact storage."
    end

    test "requires :preview_read authorization" do
      stub(AppBuilds, :app_build_by_id, fn "app-build-1", _opts -> {:ok, app_build()} end)
      stub(Projects, :get_project_by_id, fn 1 -> @project end)
      stub(Tuist.Authorization, :authorize, fn :preview_read, :subject, _project -> {:error, :forbidden} end)
      reject(&Storage.get_object_size/2)

      result = GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "app-build-1"})

      assert %{"isError" => true} = result
    end

    test "reports an app build that does not exist" do
      stub(AppBuilds, :app_build_by_id, fn "missing", _opts -> {:error, :not_found} end)

      result = GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "missing"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "App build not found: missing"
    end

    test "reports a malformed app build id as not found" do
      stub(AppBuilds, :app_build_by_id, fn "not-a-uuid", _opts ->
        {:error, "The provided app build identifier not-a-uuid doesn't have a valid format."}
      end)

      result = GetPreviewAppBuild.call(conn_with_subject(), %{"app_build_id" => "not-a-uuid"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "App build not found: not-a-uuid"
    end

    test "requires an app_build_id" do
      result = GetPreviewAppBuild.call(conn_with_subject(), %{})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "app_build_id is required"
    end
  end
end
