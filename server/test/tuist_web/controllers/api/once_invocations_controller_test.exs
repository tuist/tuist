defmodule TuistWeb.API.OnceInvocationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Once
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/projects/:account_handle/:project_handle/once/invocations" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :once)

      %{
        conn: Authentication.put_current_user(conn, user),
        user: user,
        project: project
      }
    end

    test "accepts a batch of invocations and persists them", %{conn: conn, user: user, project: project} do
      started_at_ms = System.system_time(:millisecond) - 5_000
      finished_at_ms = started_at_ms + 1_500

      body = %{
        events: [
          %{
            invocation_id: "01JT-hello-world-abc",
            command: "exec",
            argv: ["bash", "scripts/build.sh"],
            cwd: ".",
            action_digest: "cafebabecafebabecafebabecafebabe/64",
            cache: "miss",
            status: "success",
            exit_code: 0,
            started_at_ms: started_at_ms,
            finished_at_ms: finished_at_ms,
            git_branch: "main",
            git_commit_sha: "deadbeef1234",
            is_ci: false,
            os: "darwin",
            arch: "arm64",
            once_version: "0.55.0",
            workspace: "/repos/mise",
            provider_name: "tuist"
          }
        ]
      }

      path = "/api/projects/#{user.account.name}/#{project.name}/once/invocations"

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(path, JSON.encode!(body))
        |> json_response(202)

      assert response["accepted"] == 1
      assert response["rejected"] == 0

      [invocation] = Once.list_invocations(project.id)
      assert invocation.invocation_id == "01JT-hello-world-abc"
      assert invocation.status == "success"
      assert invocation.cache == "miss"
      assert invocation.duration_ms == 1_500
    end

    test "rejects events for a non-Once project", %{conn: conn, user: user} do
      xcode_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :xcode)

      started_at_ms = System.system_time(:millisecond) - 2_000
      finished_at_ms = started_at_ms + 100

      body = %{
        events: [
          %{
            invocation_id: "01JT-nope",
            status: "success",
            exit_code: 0,
            started_at_ms: started_at_ms,
            finished_at_ms: finished_at_ms
          }
        ]
      }

      path = "/api/projects/#{user.account.name}/#{xcode_project.name}/once/invocations"

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(path, JSON.encode!(body))
        |> json_response(409)

      assert response["error"] == "project_build_system_mismatch"
    end

    test "returns bad_request when the events key is missing", %{conn: conn, user: user, project: project} do
      path = "/api/projects/#{user.account.name}/#{project.name}/once/invocations"

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(path, JSON.encode!(%{}))
        |> json_response(400)

      assert response["error"] == "invalid_payload"
    end

    test "counts malformed events as rejected without failing the batch", %{conn: conn, user: user, project: project} do
      started_at_ms = System.system_time(:millisecond) - 5_000
      finished_at_ms = started_at_ms + 1_500

      body = %{
        events: [
          %{
            invocation_id: "01JT-ok",
            status: "success",
            exit_code: 0,
            started_at_ms: started_at_ms,
            finished_at_ms: finished_at_ms
          },
          %{
            invocation_id: "01JT-bad",
            status: "invalid",
            exit_code: 0,
            started_at_ms: started_at_ms,
            finished_at_ms: finished_at_ms
          }
        ]
      }

      path = "/api/projects/#{user.account.name}/#{project.name}/once/invocations"

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(path, JSON.encode!(body))
        |> json_response(202)

      assert response["accepted"] == 1
      assert response["rejected"] == 1
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/once/invocations" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :once)

      %{conn: Authentication.put_current_user(conn, user), user: user, project: project}
    end

    test "returns invocations for a project", %{conn: conn, user: user, project: project} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Once.create_invocations([
        %{
          project_id: project.id,
          invocation_id: "01JT-listing",
          command: "exec",
          argv: ["true"],
          cache: "hit",
          status: "success",
          exit_code: 0,
          duration_ms: 12,
          started_at: DateTime.add(now, -10, :second),
          finished_at: now
        }
      ])

      path = "/api/projects/#{user.account.name}/#{project.name}/once/invocations"

      response = conn |> get(path) |> json_response(200)

      assert [invocation] = response["invocations"]
      assert invocation["invocation_id"] == "01JT-listing"
      assert invocation["cache"] == "hit"
    end
  end
end
