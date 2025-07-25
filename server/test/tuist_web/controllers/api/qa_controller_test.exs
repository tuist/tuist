defmodule TuistWeb.API.QAControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.QA
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

    %{user: user, project: project, app_build: app_build, qa_run: qa_run}
  end

  describe "POST /api/qa/runs/:run_id/steps" do
    test "creates a QA run step successfully", %{
      conn: conn,
      user: user,
      qa_run: qa_run
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/qa/runs/#{qa_run.id}/steps", %{
          "summary" => "Successfully logged in to the app"
        })

      # Then
      response = json_response(conn, :created)

      assert response["qa_run_id"] == qa_run.id
      assert response["summary"] == "Successfully logged in to the app"
      assert response["id"]
      assert response["inserted_at"]
    end

    test "returns not found when QA run does not exist", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/qa/runs/#{non_existent_run_id}/steps", %{
          "summary" => "Test step"
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
        |> post(~p"/api/qa/runs/#{other_qa_run.id}/steps", %{
          "summary" => "Test step"
        })

      # Then
      response = json_response(conn, :forbidden)
      assert response["error"] == "Forbidden"
    end

    test "returns bad request when summary is missing", %{
      conn: conn,
      user: user,
      qa_run: qa_run
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/qa/runs/#{qa_run.id}/steps", %{})

      # Then
      response = json_response(conn, :bad_request)
      assert response["error"] == "Missing required parameter: summary"
    end

    test "returns unprocessable entity when validation fails", %{
      conn: conn,
      user: user,
      qa_run: qa_run
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_step_create]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/qa/runs/#{qa_run.id}/steps", %{
          "summary" => ""
        })

      # Then
      response = json_response(conn, :unprocessable_entity)
      assert response["error"] == "Validation failed"
      assert response["details"]
    end
  end

  describe "PATCH /api/qa/runs/:run_id" do
    test "updates QA run status to completed successfully", %{
      conn: conn,
      user: user,
      qa_run: qa_run
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/qa/runs/#{qa_run.id}", %{
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
      qa_run: qa_run
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/qa/runs/#{qa_run.id}", %{
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
      user: user
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{account: user.account, scopes: [:project_qa_run_update]})

      non_existent_run_id = Ecto.UUID.generate()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/qa/runs/#{non_existent_run_id}", %{
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
        |> patch(~p"/api/qa/runs/#{other_qa_run.id}", %{
          "status" => "completed"
        })

      # Then
      response = json_response(conn, :forbidden)
      assert response["error"] == "Forbidden"
    end

    test "returns bad request when status is not 'completed' or 'failed'", %{
      conn: conn,
      user: user,
      qa_run: qa_run
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/qa/runs/#{qa_run.id}", %{
          "status" => "invalid_status"
        })

      # Then
      response = json_response(conn, :bad_request)
      assert response["error"] == "Invalid status. Only 'completed' and 'failed' are allowed."
    end

    test "returns bad request when status is missing", %{
      conn: conn,
      user: user,
      qa_run: qa_run
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/qa/runs/#{qa_run.id}", %{})

      # Then
      response = json_response(conn, :bad_request)
      assert response["error"] == "Missing required parameter: status"
    end

    test "returns unprocessable entity when validation fails", %{
      conn: conn,
      user: user,
      qa_run: qa_run
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
        |> patch(~p"/api/qa/runs/#{qa_run.id}", %{
          "status" => "completed"
        })

      # Then
      response = json_response(conn, :unprocessable_entity)
      assert response["error"] == "Validation failed"
      assert response["details"]
    end
  end
end
