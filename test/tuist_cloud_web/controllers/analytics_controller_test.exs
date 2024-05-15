defmodule TuistCloudWeb.AnalyticsControllerTest do
  alias TuistCloud.CommandEvents
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Accounts
  alias TuistCloudWeb.Authentication
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")
    %{user: user}
  end

  describe "POST /api/analytics" do
    test "returns newly created command event", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{
              cacheable_targets: ["target1", "target2"],
              local_cache_target_hits: ["target1"],
              remote_cache_target_hits: ["target2"]
            },
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id
             }

      command_event = CommandEvents.get_command_event_by_id(response["id"])
      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
      assert command_event.cacheable_targets == "target1;target2"
    end

    test "returns newly created command event when cacheable analytics are missing", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id
             }

      command_event = CommandEvents.get_command_event_by_id(response["id"])
      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
    end

    test "returns newly created command event when CI and authenticated as a project", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{
              cacheable_targets: ["target1", "target2"],
              local_cache_target_hits: ["target1"],
              remote_cache_target_hits: ["target2"]
            },
            is_ci: true,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => response["id"],
               "name" => "generate",
               "project_id" => project.id
             }

      command_event = CommandEvents.get_command_event_by_id(response["id"])
      assert command_event.is_ci == true
    end
  end
end
