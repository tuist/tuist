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
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:qa_step_create]})

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

    test "creates a QA run step and updates screenshots with step ID", %{
      conn: conn,
      user: user,
      qa_run: qa_run,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:qa_step_create]})

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
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:qa_step_create]})

      non_existent_run_id = Ecto.UUID.generate()

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
          scopes: [:qa_screenshot_create]
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
      assert String.contains?(response["upload_url"], "qa/screenshots/#{qa_run.id}")
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
          scopes: [:qa_screenshot_create]
        })

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{non_existent_run_id}/screenshots",
          %{
            "step_id" => Ecto.UUID.generate()
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
          scopes: [:qa_step_update]
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
          scopes: [:qa_step_update]
        })

      non_existent_step_id = Ecto.UUID.generate()

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
          scopes: [:qa_run_update]
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

    test "updates QA run status to completed without summary", %{
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
          scopes: [:qa_run_update]
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
          scopes: [:qa_run_update]
        })

      non_existent_run_id = Ecto.UUID.generate()

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
end
