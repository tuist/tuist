defmodule Tuist.MCP.Components.Tools.BundleToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Bundles
  alias Tuist.MCP.Components.Tools.GetBundle
  alias Tuist.MCP.Components.Tools.GetBundleArtifactTree
  alias Tuist.MCP.Components.Tools.ListBundles
  alias Tuist.Projects

  describe "list_bundles" do
    test "returns paginated bundles" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      stub(Bundles, :list_bundles, fn _attrs ->
        {[
           %{
             id: "bundle-1",
             name: "MyApp",
             app_bundle_id: "com.acme.app",
             version: "1.0.0",
             type: :ipa,
             supported_platforms: [:ios],
             install_size: 50_000_000,
             download_size: 30_000_000,
             git_branch: "main",
             git_commit_sha: "abc123",
             inserted_at: ~U[2024-01-01 12:00:00Z]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListBundles.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      result = JSON.decode!(text)
      assert length(result["bundles"]) == 1
      assert hd(result["bundles"])["name"] == "MyApp"
      assert hd(result["bundles"])["install_size"] == 50_000_000
    end

    test "requires :bundle_read authorization" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               ListBundles.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      assert text =~ "You do not have access to project: acme/app"
    end
  end

  describe "get_bundle" do
    test "returns bundle details" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok,
         %{
           id: "bundle-1",
           name: "MyApp",
           app_bundle_id: "com.acme.app",
           version: "1.0.0",
           type: :ipa,
           supported_platforms: [:ios],
           install_size: 50_000_000,
           download_size: 30_000_000,
           git_branch: "main",
           git_commit_sha: "abc123",
           git_ref: "refs/tags/v1.0.0",
           project_id: 1,
           inserted_at: ~U[2024-01-01 12:00:00Z]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetBundle.call(conn, %{"bundle_id" => "bundle-1"})

      result = JSON.decode!(text)
      assert result["id"] == "bundle-1"
      assert result["install_size"] == 50_000_000
      refute Map.has_key?(result, "artifacts")
    end
  end

  describe "get_bundle_artifact_tree" do
    test "returns flat artifact tree for a bundle" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok, %{id: "bundle-1", project_id: 1}}
      end)

      stub(Bundles, :get_bundle_artifact_tree, fn "bundle-1" ->
        [
          %{
            artifact_type: :directory,
            path: "MyApp.app",
            size: 50_000_000
          },
          %{
            artifact_type: :file,
            path: "MyApp.app/Info.plist",
            size: 1_000
          },
          %{
            artifact_type: :file,
            path: "MyApp.app/MyApp",
            size: 20_000_000
          }
        ]
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetBundleArtifactTree.call(conn, %{"bundle_id" => "bundle-1"})

      result = JSON.decode!(text)
      assert length(result["artifacts"]) == 3
      assert result["bundle_id"] == "bundle-1"

      paths = Enum.map(result["artifacts"], & &1["path"])
      assert paths == ["MyApp.app", "MyApp.app/Info.plist", "MyApp.app/MyApp"]

      first = hd(result["artifacts"])
      assert first["artifact_type"] == "directory"
      assert first["size"] == 50_000_000
      refute Map.has_key?(first, "id")
      refute Map.has_key?(first, "shasum")
    end
  end
end
