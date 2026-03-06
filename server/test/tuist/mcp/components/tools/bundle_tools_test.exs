defmodule Tuist.MCP.Components.Tools.BundleToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Anubis.Server.Frame
  alias Tuist.Bundles
  alias Tuist.MCP.Server
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

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundles",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

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

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundles",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
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

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_bundle",
          "arguments" => %{"bundle_id" => "bundle-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert result["id"] == "bundle-1"
      assert result["install_size"] == 50_000_000
      refute Map.has_key?(result, "artifacts")
    end
  end

  describe "list_bundle_artifacts" do
    test "returns artifacts for a bundle" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok, %{id: "bundle-1", project_id: 1}}
      end)

      stub(Bundles, :list_bundle_artifacts, fn "bundle-1", [] ->
        [
          %{
            id: "art-1",
            artifact_type: :directory,
            path: "MyApp.app",
            size: 50_000_000,
            shasum: "sha256abc"
          },
          %{
            id: "art-2",
            artifact_type: :file,
            path: "MyApp.app/MyApp",
            size: 20_000_000,
            shasum: "sha256def"
          }
        ]
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundle_artifacts",
          "arguments" => %{"bundle_id" => "bundle-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["artifacts"]) == 2
      assert result["bundle_id"] == "bundle-1"
      assert result["parent_artifact_id"] == nil

      dir = Enum.find(result["artifacts"], &(&1["artifact_type"] == "directory"))
      assert dir["has_children"] == true

      file = Enum.find(result["artifacts"], &(&1["artifact_type"] == "file"))
      assert file["has_children"] == false
    end

    test "returns artifacts with parent_artifact_id filter" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok, %{id: "bundle-1", project_id: 1}}
      end)

      stub(Bundles, :list_bundle_artifacts, fn "bundle-1", [parent_artifact_id: "art-1"] ->
        [
          %{
            id: "art-3",
            artifact_type: :file,
            path: "MyApp.app/Info.plist",
            size: 1_000,
            shasum: "sha256ghi"
          }
        ]
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundle_artifacts",
          "arguments" => %{"bundle_id" => "bundle-1", "parent_artifact_id" => "art-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["artifacts"]) == 1
      assert result["parent_artifact_id"] == "art-1"
    end
  end

  defp message(error), do: Map.get(error.data, :message) || Map.get(error.data, "message")
end
