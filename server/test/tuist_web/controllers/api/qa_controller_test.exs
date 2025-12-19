defmodule TuistWeb.API.QAControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.QA
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    preview = AppBuildsFixtures.preview_fixture(project: project)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    qa_run = QAFixtures.qa_run_fixture(app_build: app_build)

    %{
      user: user,
      project: project,
      app_build: app_build,
      qa_run: qa_run,
      account_handle: user.account.name,
      project_handle: project.name
    }
  end

  describe "POST /api/projects/:account_handle/:project_handle/qa/runs/:run_id/steps" do
    test "creates a QA run step successfully", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_step:create"]
        })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps",
          %{
            "action" => "Successfully logged in to the app",
            "result" => "User successfully entered credentials and accessed the main screen",
            "issues" => []
          }
        )

      # Then
      response = json_response(conn, :created)

      assert response["qa_run_id"] == qa_run.id
      assert response["action"] == "Successfully logged in to the app"
    end

    test "creates a QA run step with started_at timestamp", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_step:create"]
        })

      started_at = DateTime.add(DateTime.utc_now(), -5, :second)
      started_at_iso = DateTime.to_iso8601(started_at)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps",
          %{
            "action" => "Tap login button",
            "result" => "Login button successfully tapped",
            "issues" => [],
            "started_at" => started_at_iso
          }
        )

      # Then
      response = json_response(conn, :created)

      assert response["qa_run_id"] == qa_run.id
      assert response["action"] == "Tap login button"
      {:ok, saved_step} = QA.step(response["id"])
      assert DateTime.truncate(saved_step.started_at, :second) == DateTime.truncate(started_at, :second)
    end

    test "creates a QA run step and updates screenshots with step ID", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_step:create"]
        })

      # Create some screenshots without step_id
      {:ok, screenshot1} =
        QA.create_qa_screenshot(%{qa_run_id: qa_run.id})

      {:ok, screenshot2} =
        QA.create_qa_screenshot(%{qa_run_id: qa_run.id})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps",
          %{
            "action" => "Test step with screenshots",
            "result" => "Test step result",
            "issues" => []
          }
        )

      # Then
      response = json_response(conn, :created)

      updated_screenshot1 = Tuist.Repo.get!(QA.Screenshot, screenshot1.id)
      updated_screenshot2 = Tuist.Repo.get!(QA.Screenshot, screenshot2.id)

      assert updated_screenshot1.qa_step_id == response["id"]
      assert updated_screenshot2.qa_step_id == response["id"]
    end

    test "returns not found when QA run does not exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_step:create"]
        })

      non_existent_run_id = UUIDv7.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}/steps",
          %{
            "action" => "Test step",
            "result" => "Test step result",
            "issues" => []
          }
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["error"] == "QA run not found"
    end

    test "returns forbidden when user doesn't have permission to access the project", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])

      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      other_preview = AppBuildsFixtures.preview_fixture(project: other_project)
      other_app_build = AppBuildsFixtures.app_build_fixture(preview: other_preview)
      other_qa_run = QAFixtures.qa_run_fixture(app_build: other_app_build)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}/steps",
          %{
            "action" => "Test step",
            "result" => "Test step result",
            "issues" => []
          }
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/qa/runs/:run_id/screenshots" do
    test "creates screenshot record successfully", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_screenshot:create"]
        })

      # Given a QA step
      qa_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)

      expect(Storage, :generate_upload_url, fn storage_key, _actor, _options ->
        "https://s3.example.com/#{storage_key}?presigned-params"
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/screenshots",
          %{
            "step_id" => qa_step.id
          }
        )

      # Then
      response = json_response(conn, :created)

      assert response["qa_run_id"] == qa_run.id
      assert response["qa_step_id"] == qa_step.id
      assert response["id"]
      assert String.contains?(response["upload_url"], "qa/#{qa_run.id}/screenshots/")
      assert response["expires_at"]
    end

    test "returns not found when QA run does not exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_screenshot:create"]
        })

      non_existent_run_id = UUIDv7.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}/screenshots",
          %{
            "step_id" => UUIDv7.generate()
          }
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["error"] == "QA run not found"
    end

    test "returns forbidden when user doesn't have permission", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      other_preview = AppBuildsFixtures.preview_fixture(project: other_project)
      other_app_build = AppBuildsFixtures.app_build_fixture(preview: other_preview)
      other_qa_run = QAFixtures.qa_run_fixture(app_build: other_app_build)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}/screenshots",
          %{}
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "PATCH /api/projects/:account_handle/:project_handle/qa/runs/:run_id/steps/:step_id" do
    test "updates a QA step successfully", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      {:ok, qa_step} =
        QA.create_qa_step(%{
          qa_run_id: qa_run.id,
          action: "Test login functionality",
          issues: []
        })

      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_step:update"]
        })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps/#{qa_step.id}",
          %{
            "result" => "Login successful",
            "issues" => ["Minor UI alignment issue"]
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert Map.take(response, ["id", "result", "issues"]) == %{
               "id" => qa_step.id,
               "result" => "Login successful",
               "issues" => ["Minor UI alignment issue"]
             }
    end

    test "returns not found when step does not exist", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_step:update"]
        })

      non_existent_step_id = UUIDv7.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps/#{non_existent_step_id}",
          %{
            "result" => "Updated result"
          }
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["error"] == "QA step not found"
    end

    test "returns forbidden when user doesn't have permission", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      other_preview = AppBuildsFixtures.preview_fixture(project: other_project)
      other_app_build = AppBuildsFixtures.app_build_fixture(preview: other_preview)
      other_qa_run = QAFixtures.qa_run_fixture(app_build: other_app_build)

      {:ok, qa_step} =
        QA.create_qa_step(%{
          qa_run_id: other_qa_run.id,
          action: "Unauthorized test",
          issues: []
        })

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}/steps/#{qa_step.id}",
          %{
            "result" => "Updated result"
          }
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "PATCH /api/projects/:account_handle/:project_handle/qa/runs/:run_id" do
    test "updates QA run status to completed successfully", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_run:update"]
        })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}", %{
          "status" => "completed"
        })

      # Then
      response = json_response(conn, :ok)

      assert response["id"] == qa_run.id
      assert response["status"] == "completed"
      assert response["updated_at"]
    end

    test "updates QA run status to failed and sets finished_at", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_run:update"]
        })

      # Mock datetime to verify finished_at is set
      expected_now = DateTime.truncate(DateTime.utc_now(), :second)
      stub(DateTime, :utc_now, fn -> expected_now end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}", %{
          "status" => "failed"
        })

      # Then
      response = json_response(conn, :ok)

      assert response["id"] == qa_run.id
      assert response["status"] == "failed"
      assert response["updated_at"]

      {:ok, updated_run} = QA.qa_run(qa_run.id)
      assert updated_run.finished_at == expected_now
    end

    test "returns not found when QA run does not exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:qa_run:update"]
        })

      non_existent_run_id = UUIDv7.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}",
          %{
            "status" => "completed"
          }
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["error"] == "QA run not found"
    end

    test "returns forbidden when user doesn't have permission to access the project", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      other_preview = AppBuildsFixtures.preview_fixture(project: other_project)
      other_app_build = AppBuildsFixtures.app_build_fixture(preview: other_preview)
      other_qa_run = QAFixtures.qa_run_fixture(app_build: other_app_build)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}",
          %{
            "status" => "completed"
          }
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/qa/runs/:run_id/recordings/upload/start" do
    test "starts multipart upload for recording", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: [:qa_recording_upload]
        })

      expected_upload_id = "test-upload-id-123"

      expected_storage_key =
        "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/qa/#{qa_run.id}/recording.mp4"

      expect(Storage, :multipart_start, fn storage_key, _account ->
        assert storage_key == expected_storage_key
        expected_upload_id
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/recordings/upload/start",
          %{}
        )

      # Then
      response = json_response(conn, :ok)

      assert response["upload_id"] == expected_upload_id
      assert response["storage_key"] == expected_storage_key
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/qa/runs/:run_id/recordings/upload/generate-url" do
    test "generates presigned URL for recording upload part", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: [:qa_recording_upload]
        })

      upload_id = "test-upload-id-123"

      storage_key =
        "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/qa/#{qa_run.id}/recording.mp4"

      part_number = 1
      content_length = 5_000_000
      expected_url = "https://s3.example.com/presigned-upload-url"

      expect(Storage, :multipart_generate_url, fn ^storage_key, ^upload_id, ^part_number, _account, opts ->
        assert opts[:expires_in] == 120
        assert opts[:content_length] == content_length
        expected_url
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/recordings/upload/generate-url",
          %{
            "upload_id" => upload_id,
            "part_number" => part_number,
            "storage_key" => storage_key,
            "content_length" => content_length
          }
        )

      # Then
      response = json_response(conn, :ok)
      assert response["url"] == expected_url
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/qa/runs/:run_id/recordings/upload/complete" do
    test "completes multipart upload and creates recording", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: [:qa_recording_upload]
        })

      upload_id = "test-upload-id-123"
      storage_key = "test-storage-key"
      started_at = "2024-01-01T10:00:00Z"
      duration = 300

      parts = [
        %{"part_number" => 1, "etag" => "etag1"},
        %{"part_number" => 2, "etag" => "etag2"}
      ]

      expect(Storage, :multipart_complete_upload, fn ^storage_key, ^upload_id, parts_tuples, _account ->
        assert parts_tuples == [{1, "etag1"}, {2, "etag2"}]
        :ok
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/recordings/upload/complete",
          %{
            "upload_id" => upload_id,
            "storage_key" => storage_key,
            "parts" => parts,
            "started_at" => started_at,
            "duration" => duration
          }
        )

      # Then
      _response = json_response(conn, :ok)

      recordings = Tuist.Repo.all(QA.Recording)

      assert Enum.map(recordings, &Map.take(&1, [:qa_run_id, :duration])) == [
               %{qa_run_id: qa_run.id, duration: duration}
             ]
    end
  end
end
