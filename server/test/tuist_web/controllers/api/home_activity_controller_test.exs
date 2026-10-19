defmodule TuistWeb.API.HomeActivityControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.HomeActivity
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :private)
    %{conn: Authentication.put_current_user(conn, user), user: user, project: project}
  end

  for {kind, route, target} <- [
        {:build_failures, "build-failures", "builds/build-runs"},
        {:test_failures, "test-failures", "tests/test-runs"},
        {:flaky_tests, "flaky-tests", "tests/test-cases"}
      ] do
    test "#{route} is project-scoped, links to details, and cannot be publicly cached", %{conn: conn, project: project} do
      kind = unquote(kind)
      route = unquote(route)
      target = unquote(target)
      item = %{id: UUIDv7.generate(), title: "Sample activity", subtitle: "main", occurred_at: 1_700_000_000}
      project_id = project.id
      expect(HomeActivity, kind, fn %{id: ^project_id} -> {:ok, [item]} end)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/home/#{route}")

      assert %{"items" => [result]} = json_response(conn, :ok)
      assert result["id"] == item.id
      assert result["occurred_at"] == item.occurred_at
      assert result["url"] == "/#{project.account.name}/#{project.name}/#{target}/#{item.id}"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "#{route} denies a different account before reading activity", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)
      reject(HomeActivity, unquote(kind), 1)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/home/#{unquote(route)}")

      assert json_response(conn, :forbidden)["message"]
    end
  end

  test "empty results are distinct from unsupported activity", %{conn: conn, project: project} do
    expect(HomeActivity, :build_failures, fn _ -> {:ok, []} end)
    empty = get(conn, "/api/projects/#{project.account.name}/#{project.name}/home/build-failures")
    assert json_response(empty, :ok) == %{"items" => []}

    expect(HomeActivity, :test_failures, fn _ -> {:error, :unsupported} end)
    unavailable = get(conn, "/api/projects/#{project.account.name}/#{project.name}/home/test-failures")
    assert json_response(unavailable, :unprocessable_entity)["message"] =~ "not available"
    assert get_resp_header(unavailable, "cache-control") == ["private, no-store"]
  end

  for {system, target} <- [{:bazel, "builds/invocations"}, {:once, "once/runs"}, {:gradle, "builds/build-runs"}] do
    test "#{system} failures use native dashboard destinations", %{conn: conn, user: user} do
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: unquote(system))
      id = UUIDv7.generate()

      expect(HomeActivity, :build_failures, fn _ ->
        {:ok, [%{id: id, title: "Build", subtitle: "main", occurred_at: 1_700_000_000}]}
      end)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/home/build-failures")

      assert %{"items" => [%{"url" => url}]} = json_response(conn, :ok)
      assert url == "/#{project.account.name}/#{project.name}/#{unquote(target)}/#{id}"
    end
  end
end
