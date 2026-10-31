defmodule Tuist.MCP.Components.Tools.PreviewToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.GetLatestPreview
  alias Tuist.MCP.Components.Tools.GetPreview
  alias Tuist.MCP.Components.Tools.ListPreviews
  alias Tuist.MCP.Components.Tools.PreviewSerializer
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "rejects an unsupported platform instead of removing the filter" do
    assert {:error, "supported_platforms contains an unsupported platform."} =
             PreviewSerializer.cast_supported_platforms(["not-a-platform"])
  end

  describe "members-only previews of public projects" do
    setup do
      member = AccountsFixtures.user_fixture(preload: [:account])
      non_member = AccountsFixtures.user_fixture(preload: [:account])

      project =
        ProjectsFixtures.project_fixture(account_id: member.account.id, visibility: :public, preload: [:account])

      public_preview =
        AppBuildsFixtures.preview_fixture(project: project, visibility: :public, inserted_at: ~U[2024-01-01 00:00:00Z])

      private_preview =
        AppBuildsFixtures.preview_fixture(project: project, visibility: :private, inserted_at: ~U[2024-01-02 00:00:00Z])

      AppBuildsFixtures.app_build_fixture(preview: public_preview)

      AppBuildsFixtures.app_build_fixture(
        preview: private_preview,
        binary_id: "550E8400-E29B-41D4-A716-446655440077",
        build_version: "1"
      )

      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      %{
        member: member,
        non_member: non_member,
        project: project,
        public_preview: public_preview,
        private_preview: private_preview
      }
    end

    test "list_previews returns only public previews to non-members", %{
      non_member: non_member,
      project: project,
      public_preview: public_preview
    } do
      result = ListPreviews.call(conn_for(non_member), project_args(project))

      assert %{"previews" => previews} = decode(result)
      assert Enum.map(previews, & &1["id"]) == [public_preview.id]
    end

    test "list_previews returns members-only previews to members", %{
      member: member,
      project: project,
      public_preview: public_preview,
      private_preview: private_preview
    } do
      result = ListPreviews.call(conn_for(member), project_args(project))

      assert %{"previews" => previews} = decode(result)
      assert Enum.map(previews, & &1["id"]) == [private_preview.id, public_preview.id]
    end

    test "get_preview does not return a members-only preview to non-members", %{
      non_member: non_member,
      private_preview: private_preview
    } do
      result = GetPreview.call(conn_for(non_member), %{"preview_id" => private_preview.id})

      assert %{"isError" => true, "content" => [%{"text" => message}]} = result
      assert message =~ "Preview not found"
    end

    test "get_latest_preview skips members-only previews for non-members", %{
      non_member: non_member,
      project: project,
      public_preview: public_preview
    } do
      args =
        Map.merge(project_args(project), %{"binary_id" => "550E8400-E29B-41D4-A716-446655440077", "build_version" => "1"})

      result = GetLatestPreview.call(conn_for(non_member), args)

      assert %{"preview" => %{"id" => id}} = decode(result)
      assert id == public_preview.id
    end
  end

  defp conn_for(user), do: %Plug.Conn{assigns: %{current_user: user}}

  defp project_args(project), do: %{"account_handle" => project.account.name, "project_handle" => project.name}

  defp decode(%{"content" => [%{"type" => "text", "text" => text}]}), do: JSON.decode!(text)
end
