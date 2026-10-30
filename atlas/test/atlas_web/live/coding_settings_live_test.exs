defmodule AtlasWeb.CodingSettingsLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.CodingRepositories
  alias Atlas.Integrations.GitHubAPI

  test "settings choose source and default, retain a failed draft, and clear both", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    stub(Atlas.Connections, :access_token, fn _, "github" -> {:ok, "grant"} end)
    stub(GitHubAPI, :accessible_installations, fn _ -> {:ok, [%{id: "42", name: "Acme"}]} end)
    stub(GitHubAPI, :accessible_repositories, fn _, "42" -> {:ok, [%{full_name: "acme/code"}]} end)
    {:ok, view, _} = live(conn, ~p"/settings/coding")
    render_async(view)
    assert has_element?(view, "#coding-installation option[value='42']")
    params = %{installation_id: "42", default_repository: "_none"}
    view |> form("#coding-settings-form", coding: params) |> render_change()
    render_async(view)
    assert has_element?(view, "#coding-default-repository option[value='acme/code']")
    params = %{params | default_repository: "acme/code"}
    view |> form("#coding-settings-form", coding: params) |> render_change()
    view |> form("#coding-settings-form", coding: params) |> render_submit()
    render_async(view)
    assert CodingRepositories.settings(user)["default_repository"] == "acme/code"
    stub(GitHubAPI, :accessible_repositories, fn _, _ -> {:error, :github_catalog_unavailable} end)
    view |> form("#coding-settings-form", coding: params) |> render_submit()
    render_async(view)
    assert has_element?(view, "#coding-default-repository option[value='acme/code'][selected]")
    assert CodingRepositories.settings(user)["default_repository"] == "acme/code"
    cleared = %{installation_id: "_none", default_repository: "_none"}
    view |> form("#coding-settings-form", coding: cleared) |> render_change()
    render_async(view)
    view |> form("#coding-settings-form", coding: cleared) |> render_submit()
    render_async(view)
    assert CodingRepositories.settings(user) == %{"installation_id" => nil, "default_repository" => nil}
  end
end
