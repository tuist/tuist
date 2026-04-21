defmodule TuistWeb.API.Automations.AlertsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Automations
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  defp setup_project(%{conn: conn}) do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = Authentication.put_current_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  defp api_path(project, suffix \\ ""),
    do: "/api/projects/#{project.account.name}/#{project.name}/automations/alerts#{suffix}"

  describe "GET /api/projects/:account_handle/:project_handle/automations/alerts" do
    setup :setup_project

    test "lists alerts for a project", %{conn: conn, project: project} do
      a1 = AutomationsFixtures.automation_alert_fixture(project: project, name: "First")
      a2 = AutomationsFixtures.automation_alert_fixture(project: project, name: "Second")
      _other = AutomationsFixtures.automation_alert_fixture()

      response = conn |> get(api_path(project)) |> json_response(:ok)

      ids = Enum.map(response["alerts"], & &1["id"])
      assert MapSet.new(ids) == MapSet.new([a1.id, a2.id])
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/automations/alerts" do
    setup :setup_project

    test "creates an alert rule", %{conn: conn, project: project} do
      body = %{
        "name" => "Auto-quarantine",
        "monitor_type" => "flakiness_rate",
        "trigger_config" => %{"threshold" => 10, "window" => "30d"},
        "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}]
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(api_path(project), Jason.encode!(body))
        |> json_response(:created)

      assert response["name"] == "Auto-quarantine"
      assert response["monitor_type"] == "flakiness_rate"
      assert [%{"type" => "change_state", "state" => "muted"}] = response["trigger_actions"]
    end

    test "returns 422 when validation fails (e.g. blank name)", %{conn: conn, project: project} do
      body = %{
        "name" => "",
        "monitor_type" => "flakiness_rate",
        "trigger_config" => %{"threshold" => 10, "window" => "30d"},
        "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}]
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(api_path(project), Jason.encode!(body))
        |> json_response(:unprocessable_entity)

      assert response["message"] =~ "name"
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/automations/alerts/:id" do
    setup :setup_project

    test "returns the alert rule when it belongs to the project", %{conn: conn, project: project} do
      automation = AutomationsFixtures.automation_alert_fixture(project: project)
      response = conn |> get(api_path(project, "/#{automation.id}")) |> json_response(:ok)
      assert response["id"] == automation.id
    end

    test "returns 404 when the alert rule belongs to a different project", %{conn: conn, project: project} do
      other = AutomationsFixtures.automation_alert_fixture()
      conn = get(conn, api_path(project, "/#{other.id}"))
      assert json_response(conn, :not_found)
    end

    test "returns 404 when the alert rule does not exist", %{conn: conn, project: project} do
      conn = get(conn, api_path(project, "/#{Ecto.UUID.generate()}"))
      assert json_response(conn, :not_found)
    end
  end

  describe "PUT /api/projects/:account_handle/:project_handle/automations/alerts/:id" do
    setup :setup_project

    test "updates the alert rule", %{conn: conn, project: project} do
      automation = AutomationsFixtures.automation_alert_fixture(project: project, enabled: true)

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(api_path(project, "/#{automation.id}"), Jason.encode!(%{"enabled" => false}))
        |> json_response(:ok)

      refute response["enabled"]
    end

    test "returns 404 for an alert rule in another project", %{conn: conn, project: project} do
      other = AutomationsFixtures.automation_alert_fixture()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(api_path(project, "/#{other.id}"), Jason.encode!(%{"enabled" => false}))

      assert json_response(conn, :not_found)
    end
  end

  describe "DELETE /api/projects/:account_handle/:project_handle/automations/alerts/:id" do
    setup :setup_project

    test "deletes the alert rule", %{conn: conn, project: project} do
      automation = AutomationsFixtures.automation_alert_fixture(project: project)

      conn = delete(conn, api_path(project, "/#{automation.id}"))
      assert response(conn, :no_content)
      assert {:error, :not_found} = Automations.get_alert(automation.id)
    end

    test "returns 404 for an alert rule in another project", %{conn: conn, project: project} do
      other = AutomationsFixtures.automation_alert_fixture()
      conn = delete(conn, api_path(project, "/#{other.id}"))
      assert json_response(conn, :not_found)
      assert {:ok, _} = Automations.get_alert(other.id)
    end
  end
end
