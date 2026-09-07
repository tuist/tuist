defmodule Tuist.MCP.Components.Tools.ProjectLogoToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.CompleteProjectLogoUpload
  alias Tuist.MCP.Components.Tools.StartProjectLogoUpload
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "start_project_logo_upload" do
    setup do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      stub(Projects, :get_project_by_account_and_project_handles, fn account_handle, project_handle ->
        if account_handle == project.account.name and project_handle == project.name do
          project
        end
      end)

      stub(Tuist.Authorization, :authorize, fn :project_update, :subject, ^project -> :ok end)

      %{project: project}
    end

    test "returns a presigned URL and upload token", %{project: project} do
      stub(Tuist.Storage, :generate_upload_url, fn key, :project_logos, opts ->
        assert String.starts_with?(key, "project-logos/#{project.id}/")
        assert Keyword.fetch!(opts, :expires_in) == 3_600
        "https://storage.example.com/#{key}?signed=1"
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               StartProjectLogoUpload.call(conn, %{
                 "account_handle" => project.account.name,
                 "project_handle" => project.name,
                 "content_type" => "image/png"
               })

      result = JSON.decode!(text)
      assert result["method"] == "PUT"
      assert result["content_type"] == "image/png"
      assert result["expires_in_seconds"] == 3_600
      assert String.starts_with?(result["upload_url"], "https://storage.example.com/")
      assert String.ends_with?(result["storage_key"], ".png")
      assert is_binary(result["upload_token"])
    end

    test "rejects unsupported content types", %{project: project} do
      reject(&Tuist.Storage.generate_upload_url/3)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{
               "content" => [%{"type" => "text", "text" => "Arguments do not match the tool schema."}],
               "isError" => true
             } =
               StartProjectLogoUpload.call(conn, %{
                 "account_handle" => project.account.name,
                 "project_handle" => project.name,
                 "content_type" => "image/gif"
               })
    end
  end

  describe "complete_project_logo_upload" do
    setup do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      stub(Projects, :get_project_by_account_and_project_handles, fn account_handle, project_handle ->
        if account_handle == project.account.name and project_handle == project.name do
          project
        end
      end)

      stub(Tuist.Authorization, :authorize, fn :project_update, :subject, ^project -> :ok end)

      %{project: project}
    end

    test "commits the logo when the object is present", %{project: project} do
      stub(Tuist.Storage, :generate_upload_url, fn _key, :project_logos, _opts ->
        "https://storage.example.com/upload"
      end)

      {:ok, prepared} = Projects.prepare_project_logo_upload(project, "image/png")

      stub(Tuist.Storage, :object_exists?, fn key, :project_logos ->
        assert key == prepared.storage_key
        true
      end)

      reject(&Tuist.Storage.delete_object/2)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               CompleteProjectLogoUpload.call(conn, %{
                 "account_handle" => project.account.name,
                 "project_handle" => project.name,
                 "upload_token" => prepared.upload_token
               })

      result = JSON.decode!(text)
      assert result["storage_key"] == prepared.storage_key
      assert String.ends_with?(result["logo_url"], "/#{project.account.name}/#{project.name}/logo")

      assert Projects.get_project_by_id(project.id).logo_storage_key == prepared.storage_key
    end

    test "errors when the object is not in storage", %{project: project} do
      stub(Tuist.Storage, :generate_upload_url, fn _key, :project_logos, _opts ->
        "https://storage.example.com/upload"
      end)

      {:ok, prepared} = Projects.prepare_project_logo_upload(project, "image/png")

      stub(Tuist.Storage, :object_exists?, fn _key, :project_logos -> false end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               CompleteProjectLogoUpload.call(conn, %{
                 "account_handle" => project.account.name,
                 "project_handle" => project.name,
                 "upload_token" => prepared.upload_token
               })

      assert text =~ "No object at the storage key"
    end

    test "rejects tokens issued for a different project", %{project: project} do
      other_project = ProjectsFixtures.project_fixture(preload: [:account])

      stub(Projects, :get_project_by_account_and_project_handles, fn account_handle, project_handle ->
        cond do
          account_handle == project.account.name and project_handle == project.name ->
            project

          account_handle == other_project.account.name and project_handle == other_project.name ->
            other_project

          true ->
            nil
        end
      end)

      stub(Tuist.Authorization, :authorize, fn :project_update, :subject, _project -> :ok end)

      stub(Tuist.Storage, :generate_upload_url, fn _key, :project_logos, _opts ->
        "https://storage.example.com/upload"
      end)

      {:ok, prepared} = Projects.prepare_project_logo_upload(other_project, "image/png")

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               CompleteProjectLogoUpload.call(conn, %{
                 "account_handle" => project.account.name,
                 "project_handle" => project.name,
                 "upload_token" => prepared.upload_token
               })

      assert text =~ "issued for a different project"
    end

    test "rejects garbage tokens", %{project: project} do
      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               CompleteProjectLogoUpload.call(conn, %{
                 "account_handle" => project.account.name,
                 "project_handle" => project.name,
                 "upload_token" => "not-a-real-token"
               })

      assert text =~ "invalid or has expired"
    end
  end
end
