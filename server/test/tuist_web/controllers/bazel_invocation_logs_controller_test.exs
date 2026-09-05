defmodule TuistWeb.BazelInvocationLogsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Bazel
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "download/2" do
    test "downloads every invocation log in Build Event Protocol order", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)

      create_invocation(project, "invocation-1")
      create_invocation_log(project, "invocation-1", 20, "second\n")
      create_invocation_log(project, "invocation-1", 10, "first\n")

      conn =
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/invocations/invocation-1/logs/download"
        )

      assert response(conn, 200) == "first\nsecond\n"
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="bazel-invocation.log")]
    end

    test "downloads logs from the legacy invocation route", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)

      create_invocation(project, "legacy-invocation")
      create_invocation_log(project, "legacy-invocation", 10, "legacy log\n")

      conn =
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/invocations/legacy-invocation/logs/download"
        )

      assert response(conn, 200) == "legacy log\n"
    end

    test "downloads test logs beyond one keyset batch", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)

      create_invocation(project, "invocation-1")

      Bazel.create_invocation_logs(
        Enum.map(1..1_005, fn sequence_number ->
          %{
            invocation_id: "invocation-1",
            sequence_number: sequence_number,
            stream: "stdout",
            message: "log #{sequence_number}\n",
            project_id: project.id,
            observed_at: ~N[2026-09-04 12:00:00]
          }
        end)
      )

      conn =
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/invocations/invocation-1/logs/download"
        )

      body = response(conn, 200)
      assert body =~ "log 1\n"
      assert body =~ "log 1005\n"
      assert body |> String.split("\n", trim: true) |> length() == 1_005
    end

    test "returns not found when the invocation has no logs", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)

      create_invocation(project, "missing")

      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/invocations/missing/logs/download"
        )
      end
    end

    test "does not expose another project's invocation logs", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)

      create_invocation(other_project, "invocation-1")
      create_invocation_log(other_project, "invocation-1", 10, "private\n")

      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/invocations/invocation-1/logs/download"
        )
      end
    end

    test "returns not found when the user cannot read the project", %{conn: conn} do
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: owner.account.id, build_system: :bazel)
      conn = log_in_user(conn, other_user)

      create_invocation(project, "invocation-1")
      create_invocation_log(project, "invocation-1", 10, "private\n")

      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{owner.account.name}/#{project.name}/builds/invocations/invocation-1/logs/download"
        )
      end
    end
  end

  defp create_invocation_log(project, invocation_id, sequence_number, message) do
    Bazel.create_invocation_logs([
      %{
        invocation_id: invocation_id,
        sequence_number: sequence_number,
        stream: "stdout",
        message: message,
        project_id: project.id,
        observed_at: ~N[2026-09-04 12:00:00]
      }
    ])
  end

  defp create_invocation(project, invocation_id) do
    finished_at = ~N[2026-09-04 12:00:01]

    Bazel.create_invocations([
      %{
        invocation_id: invocation_id,
        command: "test",
        status: "success",
        exit_code: 0,
        started_at: NaiveDateTime.add(finished_at, -60, :second),
        finished_at: finished_at,
        duration_ms: 60_000,
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end
end
