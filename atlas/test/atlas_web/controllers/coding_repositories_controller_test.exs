defmodule AtlasWeb.CodingRepositoriesControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.OrbitFixtures

  alias Atlas.CodingRepositories
  alias Atlas.Integrations.GitHubAPI
  alias Atlas.MCP.Tools.ListCodingRepositories
  alias Atlas.MCP.Tools.UpdateCodingRepositorySettings

  test "bearer API and MCP share personal preferences without exposing credentials", %{conn: conn} do
    user = user_fixture()

    stub(Atlas.Connections, :access_token, fn caller, "github" ->
      if caller.id == user.id, do: {:ok, "private-grant"}, else: {:error, :not_connected}
    end)

    stub(GitHubAPI, :accessible_installations, fn "private-grant" -> {:ok, [%{id: "42", name: "Acme"}]} end)
    stub(GitHubAPI, :accessible_repositories, fn "private-grant", "42" -> {:ok, [%{full_name: "acme/code"}]} end)
    path = "/api/me/coding-repositories"
    assert conn |> get(path) |> json_response(401)
    browser = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    assert browser |> get(path) |> json_response(401)
    api = bearer(user)
    params = %{"installation_id" => "42", "default_repository" => "acme/code"}
    response = put(api, path <> "/settings", params)
    assert json_response(response, 200) == params
    assert get_resp_header(response, "cache-control") == ["no-store"]
    catalog = get(api, path) |> json_response(200)
    assert catalog["repositories"] == [%{"full_name" => "acme/code"}]
    refute JSON.encode!(catalog) =~ "private-grant"
    mcp = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    assert {:ok, result} = ListCodingRepositories.execute(mcp, %{})
    assert JSON.decode!(JSON.encode!(result)) == catalog
    assert {:ok, _} = UpdateCodingRepositorySettings.execute(mcp, %{params | "default_repository" => nil})
    assert CodingRepositories.settings(user)["default_repository"] == nil
    assert put(api, path <> "/settings", Map.put(params, "user_id", user.id)) |> json_response(422)

    for assigns <- [%{audit_interface: "slack"}, %{mcp_claims: %{"slack_agent" => true}}] do
      shared = %{assigns: Map.merge(mcp.assigns, assigns)}
      assert {:error, _} = ListCodingRepositories.execute(shared, %{})
      assert {:error, _} = UpdateCodingRepositorySettings.execute(shared, params)
    end

    assert get(bearer(user_fixture()), path) |> json_response(409)
  end
end
