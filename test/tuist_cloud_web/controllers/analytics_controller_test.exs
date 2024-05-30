defmodule TuistCloudWeb.AnalyticsControllerTest do
  alias TuistCloud.Storage
  alias TuistCloud.CommandEventsFixtures
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
    test "returns forbidden when not CI and authenticated as a project", %{conn: conn, user: user} do
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
            params: %{},
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "tuist is not authorized to create command_event"
             }
    end

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

      command_event = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
      assert command_event.cacheable_targets == ["target1", "target2"]
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

      command_event = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => command_event.id,
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
    end

    test "returns newly created command event with status failure and error message", %{
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
            client_id: "client-id",
            status: "failure",
            error_message: "An error occurred"
          }
        )

      # Then
      response = json_response(conn, :ok)

      command_event = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.status == :failure
      assert command_event.error_message == "An error occurred"
      assert command_event.user_id == user.id
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

      command_event = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "id" => response["id"],
               "name" => "generate",
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.is_ci == true
    end
  end

  describe "POST /api/runs/:run_id/start" do
    test "starts multipart upload", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      Storage
      |> expect(:multipart_start, fn ^object_key ->
        upload_id
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/start",
          type: "result_bundle"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end
  end

  describe "POST /api/runs/:run_id/generate-url" do
    test "generates URL for a part of the multipart upload", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"
      part_number = "3"
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      Storage
      |> expect(:multipart_generate_url, fn ^object_key,
                                            ^upload_id,
                                            ^part_number,
                                            [expires_in: _] ->
        upload_url
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/generate-url",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_part: %{part_number: part_number, upload_id: upload_id}
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["url"] == "https://url.com"
    end
  end

  describe "POST /api/runs/:run_id/complete" do
    test "completes a multipart upload", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "1234"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      Storage
      |> expect(:multipart_complete_upload, fn ^object_key,
                                               ^upload_id,
                                               [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/complete",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_parts: %{
            parts: parts,
            upload_id: upload_id
          }
        )

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end
  end
end
