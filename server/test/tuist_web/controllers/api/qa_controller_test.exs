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
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preload: [:account])
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
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps", %{
          "summary" => "Successfully logged in to the app",
          "description" => "User successfully entered credentials and accessed the main screen",
          "issues" => []
        })

      # Then
      response = json_response(conn, :created)

      assert response["qa_run_id"] == qa_run.id
      assert response["summary"] == "Successfully logged in to the app"
      assert response["id"]
      assert response["inserted_at"]
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
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      # Create some screenshots without step_id
      {:ok, screenshot1} = QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "screen1", title: "Screen 1"})
      {:ok, screenshot2} = QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "screen2", title: "Screen 2"})

      # Verify screenshots have no step_id initially
      assert is_nil(screenshot1.qa_run_step_id)
      assert is_nil(screenshot2.qa_run_step_id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/steps", %{
          "summary" => "Test step with screenshots",
          "description" => "Test step description",
          "issues" => []
        })

      # Then
      response = json_response(conn, :created)
      step_id = response["id"]

      # Verify screenshots are now associated with the step
      updated_screenshot1 = Tuist.Repo.get!(QA.Screenshot, screenshot1.id)
      updated_screenshot2 = Tuist.Repo.get!(QA.Screenshot, screenshot2.id)

      assert updated_screenshot1.qa_run_step_id == step_id
      assert updated_screenshot2.qa_run_step_id == step_id
    end

    test "returns not found when QA run does not exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}/steps", %{
          "summary" => "Test step",
          "description" => "Test step description",
          "issues" => []
        })

      # Then
      response = json_response(conn, :not_found)
      assert response["error"] == "QA run not found"
    end

    test "returns forbidden when user doesn't have permission to access the project", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])

      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: other_user.account,
          scopes: [:project_qa_run_step_create]
        })

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
        |> post(~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}/steps", %{
          "summary" => "Test step",
          "description" => "Test step description",
          "issues" => []
        })

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/qa/runs/:run_id/screenshots/upload" do
    test "returns upload URL successfully", %{
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
          scopes: [:project_qa_screenshot_create]
        })

      expect(Storage, :generate_upload_url, fn storage_key, _options ->
        "https://s3.example.com/#{storage_key}?presigned-params"
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/screenshots/upload", %{
          "file_name" => "login_screen",
          "title" => "Login Screen"
        })

      # Then
      response = json_response(conn, :ok)

      assert response["url"]
      assert response["expires_at"]
      assert String.contains?(response["url"], "qa/screenshots/#{qa_run.id}/login_screen.png")
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
          scopes: [:project_qa_screenshot_create]
        })

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}/screenshots/upload",
          %{
            "file_name" => "test_screenshot",
            "title" => "Test Screenshot"
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
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}/screenshots/upload",
          %{
            "file_name" => "test_screenshot",
            "title" => "Test Screenshot"
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
          scopes: [:project_qa_screenshot_create]
        })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/screenshots", %{
          "file_name" => "error_dialog",
          "title" => "Error Dialog"
        })

      # Then
      response = json_response(conn, :created)

      assert response["id"]
      assert response["qa_run_id"] == qa_run.id
      assert response["file_name"] == "error_dialog"
      assert response["title"] == "Error Dialog"
      assert response["inserted_at"]
      assert is_nil(response["qa_run_step_id"])
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
          scopes: [:project_qa_screenshot_create]
        })

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}/screenshots", %{
          "file_name" => "test_screenshot",
          "title" => "Test Screenshot"
        })

      # Then
      response = json_response(conn, :not_found)
      assert response["error"] == "QA run not found"
    end

    test "returns bad request when screenshot already exists with same name", %{
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
          scopes: [:project_qa_screenshot_create]
        })

      # Create first screenshot
      {:ok, _} = QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "duplicate_name", title: "Duplicate Name"})

      # When trying to create second screenshot with same name
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}/screenshots", %{
          "file_name" => "duplicate_name",
          "title" => "Another Duplicate Name"
        })

      # Then
      response = json_response(conn, :bad_request)
      assert String.contains?(response["message"], "has already been taken")
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
          %{
            "file_name" => "test_screenshot",
            "title" => "Test Screenshot"
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
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}", %{
          "status" => "completed",
          "summary" => "QA test completed successfully"
        })

      # Then
      response = json_response(conn, :ok)

      assert response["id"] == qa_run.id
      assert response["status"] == "completed"
      assert response["summary"] == "QA test completed successfully"
      assert response["updated_at"]
    end

    test "updates QA run status to completed without summary", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

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
      assert response["summary"] == nil
      assert response["updated_at"]
    end

    test "returns not found when QA run does not exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}", %{
          "status" => "completed"
        })

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
        |> patch(~p"/api/projects/#{other_project.account.name}/#{other_project.name}/qa/runs/#{other_qa_run.id}", %{
          "status" => "completed"
        })

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end

    test "returns bad request when status is missing", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}", %{})

      # Then
      response = json_response(conn, :bad_request)
      assert response["error"] == "Missing required parameter: status"
    end

    test "returns unprocessable entity when validation fails", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      # Mock the QA.update_qa_run to return a validation error
      expect(QA, :update_qa_run, fn _, _ ->
        {:error, %Ecto.Changeset{valid?: false, errors: [status: {"is invalid", []}]}}
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{qa_run.id}", %{
          "status" => "completed"
        })

      # Then
      response = json_response(conn, :unprocessable_entity)
      assert response["error"] == "Validation failed"
      assert response["details"]
    end
  end
end
