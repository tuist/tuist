defmodule TuistWeb.AnalyticsControllerTest do
  alias TuistTestSupport.Fixtures.PreviewsFixtures
  alias Tuist.VCS
  alias Tuist.Environment
  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias Tuist.Accounts
  alias TuistWeb.Authentication
  import Ecto.Query, only: [from: 2]
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")

    Environment
    |> stub(:github_app_configured?, fn -> true end)

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
      ran_at_string = "2025-02-28T15:51:12Z"

      {:ok, ran_at, _} =
        DateTime.from_iso8601(ran_at_string)

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
            ran_at: ran_at_string,
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

      assert command_event.ran_at == ran_at
      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
      assert command_event.cacheable_targets == ["target1", "target2"]
    end

    test "returns newly created command event when the date is missing", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      date = ~U[2025-02-28 15:51:12Z]

      DateTime
      |> stub(:utc_now, fn -> date end)

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
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      command_event = CommandEvents.get_command_event_by_id(response["id"])

      assert command_event.ran_at == date
    end

    test "returns newly created preview command event", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      preview = PreviewsFixtures.preview_fixture(project: project, display_name: "App")

      VCS
      |> expect(:post_vcs_pull_request_comment, fn _ ->
        :ok
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "share",
            subcommand: "",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            preview_id: preview.id,
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      command_event = CommandEvents.get_command_event_by_id(response["id"])

      assert response["name"] == "share"
      assert command_event.preview_id == preview.id
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

      VCS
      |> expect(:post_vcs_pull_request_comment, fn _ ->
        :ok
      end)

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

      VCS
      |> expect(:post_vcs_pull_request_comment, fn _ ->
        :ok
      end)

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

    test "returns newly created command event with xcode_graph", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      VCS
      |> expect(:post_vcs_pull_request_comment, fn _ ->
        :ok
      end)

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
            xcode_graph: %{
              name: "Graph",
              projects: [
                %{
                  name: "ProjectA",
                  path: ".",
                  targets: [
                    %{name: "TargetA", binary_cache_metadata: %{hash: "hash-a", hit: "local"}},
                    %{
                      name: "TargetATests",
                      selective_testing_metadata: %{hash: "hash-a-tests", hit: "miss"}
                    }
                  ]
                }
              ]
            }
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

      command_event = Repo.preload(command_event, xcode_graph: [xcode_projects: :xcode_targets])
      assert command_event.xcode_graph.name == "Graph"
      assert command_event.xcode_graph.xcode_projects |> Enum.map(& &1.name) == ["ProjectA"]
      xcode_project = command_event.xcode_graph.xcode_projects |> hd()
      xcode_targets = xcode_project.xcode_targets |> Enum.sort_by(& &1.name)
      assert xcode_targets |> Enum.map(& &1.name) == ["TargetA", "TargetATests"]
      assert xcode_targets |> Enum.map(& &1.binary_cache_hash) == ["hash-a", nil]
      assert xcode_targets |> Enum.map(& &1.binary_cache_hit) == [:local, nil]
      assert xcode_targets |> Enum.map(& &1.selective_testing_hash) == [nil, "hash-a-tests"]
      assert xcode_targets |> Enum.map(& &1.selective_testing_hit) == [nil, :miss]
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

    test "starts multipart upload for a result_bundle_object", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/some-id.json"

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
          type: "result_bundle_object",
          name: "some-id"
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
      part_number = 3
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      Storage
      |> expect(:multipart_generate_url, fn ^object_key,
                                            ^upload_id,
                                            ^part_number,
                                            [expires_in: _, content_length: 100] ->
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
          multipart_upload_part: %{
            part_number: part_number,
            upload_id: upload_id,
            content_length: 100
          }
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["url"] == "https://url.com"
    end
  end

  describe "POST /api/runs/:run_id/complete" do
    test "completes a multipart upload returns a raw error", %{conn: conn} do
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

  describe "PUT /api/runs/:run_id/complete_artifacts_uploads" do
    test "creates test action events", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)
        |> Repo.preload(project: :account)

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(
          name: "MainApp",
          path: "App",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target =
        XcodeFixtures.xcode_target_fixture(name: "AppTests", xcode_project_id: xcode_project.id)

      xcode_project_two =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework1",
          path: "Framework1",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_two =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework1Tests",
          xcode_project_id: xcode_project_two.id
        )

      xcode_project_three =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework2",
          path: "Framework2",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_three =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework2Tests",
          xcode_project_id: xcode_project_three.id
        )

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      Storage
      |> stub(:object_exists?, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      Storage
      |> stub(:get_object_as_string, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      FunWithFlags.enable(:flaky_test_detection, for_actor: project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}

      test_case_runs =
        from(
          t in TestCaseRun,
          where: t.command_event_id == ^command_event.id
        )
        |> Repo.all()
        |> Repo.preload(:test_case)
        |> Enum.map(& &1.test_case.identifier)
        |> Enum.sort()

      assert length(test_case_runs) == 5

      assert test_case_runs == [
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello",
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHelloFromFramework2",
               "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello",
               "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello",
               "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
             ]
    end

    test "runs with older CLI versions that send modules", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)
        |> Repo.preload(project: :account)

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(
          name: "MainApp",
          path: "App",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target =
        XcodeFixtures.xcode_target_fixture(name: "AppTests", xcode_project_id: xcode_project.id)

      xcode_project_two =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework1",
          path: "Framework1",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_two =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework1Tests",
          xcode_project_id: xcode_project_two.id
        )

      xcode_project_three =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework2",
          path: "Framework2",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_three =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework2Tests",
          xcode_project_id: xcode_project_three.id
        )

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      Storage
      |> stub(:object_exists?, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      Storage
      |> stub(:get_object_as_string, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      FunWithFlags.enable(:flaky_test_detection, for_actor: project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads",
          modules: [
            %{
              name: "AppTests",
              project_identifier: "App/MainApp.xcodeproj",
              hash: "app-module_hash"
            },
            %{
              name: "Framework1Tests",
              project_identifier: "Framework1/Framework1.xcodeproj",
              hash: "framework1-module_hash"
            },
            %{
              name: "Framework2Tests",
              project_identifier: "Framework2/Framework2.xcodeproj",
              hash: "framework2-module_hash"
            }
          ]
        )

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}

      test_case_runs =
        from(
          t in TestCaseRun,
          where: t.command_event_id == ^command_event.id
        )
        |> Repo.all()
        |> Repo.preload(:test_case)
        |> Enum.map(& &1.test_case.identifier)
        |> Enum.sort()

      assert length(test_case_runs) == 5

      assert test_case_runs == [
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHello",
               "test://com.apple.xcode/Framework1/Framework1Tests/Framework1Tests/testHelloFromFramework2",
               "test://com.apple.xcode/Framework2/Framework2Tests/Framework2Tests/testHello",
               "test://com.apple.xcode/Framework2/Framework2Tests/MyPublicClassTests/testHello",
               "test://com.apple.xcode/MainApp/AppTests/AppDelegateTests/testHello"
             ]
    end

    test "noops when test_summary is missing", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)
        |> Repo.preload(project: :account)

      Storage
      |> stub(:object_exists?, fn _ -> false end)

      conn =
        conn
        |> Authentication.put_current_project(project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}

      test_case_runs =
        from(
          t in TestCaseRun,
          where: t.command_event_id == ^command_event.id
        )
        |> Repo.all()

      assert Enum.empty?(test_case_runs) == true
    end
  end
end
