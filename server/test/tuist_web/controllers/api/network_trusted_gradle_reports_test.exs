defmodule TuistWeb.API.NetworkTrustedGradleReportsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Gradle
  alias Tuist.Gradle.Build.Buffer
  alias Tuist.MCP.Events.Publisher
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn -> true end)
    %{user: user, project: project}
  end

  defp publish(conn, project, body \\ %{duration_ms: 1, status: "success", tasks: []}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/projects/#{project.account.name}/#{project.name}/gradle/builds", body)
  end

  test "publishes without inventing an authenticated subject or accepting a client build ID", %{
    conn: conn,
    project: project
  } do
    client_id = UUIDv7.generate()

    response =
      conn
      |> put_req_header("x-tuist-actor-id", "developer-123")
      |> publish(project, %{id: client_id, duration_ms: 1, status: "success", tasks: []})
      |> json_response(201)

    refute response["id"] == client_id
    Buffer.flush()
    {:ok, build} = Gradle.get_build(response["id"], project_id: project.id)
    assert build.account_id == 0
    assert build.actor_account_id == 0
    assert build.claimed_actor_id == "developer-123"
    assert build.submission_auth == "network_trusted"
  end

  test "duplicate credentials and stale authenticated assignments cannot downgrade", %{
    conn: conn,
    project: project,
    user: user
  } do
    duplicate = %{
      conn
      | req_headers: [{"authorization", "Bearer one"}, {"authorization", "Bearer two"} | conn.req_headers]
    }

    assert duplicate |> publish(project) |> json_response(401)

    assert conn
           |> TuistWeb.Authentication.put_current_user(user)
           |> put_req_header("authorization", "Bearer revoked")
           |> publish(project)
           |> json_response(401)

    duplicate_actor = %{conn | req_headers: [{"x-tuist-actor-id", "one"}, {"x-tuist-actor-id", "two"} | conn.req_headers]}
    response = duplicate_actor |> publish(project) |> json_response(201)
    Buffer.flush()
    {:ok, build} = Gradle.get_build(response["id"], project_id: project.id)
    assert build.claimed_actor_id == ""
  end

  test "a real shared project credential reports a claim without inventing a verified person", %{
    conn: conn,
    project: project
  } do
    response =
      conn
      |> put_req_header("authorization", "Bearer " <> project.token)
      |> put_req_header("x-tuist-actor-id", "developer-123")
      |> publish(project)
      |> json_response(201)

    Buffer.flush()
    {:ok, build} = Gradle.get_build(response["id"], project_id: project.id)
    assert build.account_id == project.account_id
    assert build.actor_account_id == 0
    assert build.submission_auth == "token"

    assert %{source: :reported, claimed_actor_id: "developer-123", verified_account_handle: nil} =
             Tuist.ReportActor.actor(build)
  end

  test "quota backend failure refuses publication", %{conn: conn, project: project} do
    expect(TuistWeb.RateLimit, :hit, fn _, opts ->
      assert opts[:fallback] == false
      {:error, :unavailable}
    end)

    assert conn |> publish(project) |> json_response(503)
  end

  test "a real user credential keeps failed-build automation and verified attribution", %{
    conn: conn,
    project: project,
    user: user
  } do
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")

    expect(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn attrs ->
      assert attrs.project_id == project.id
      :ok
    end)

    expect(Publisher, :publish, fn "build.failed", attrs, _ ->
      assert attrs["project_id"] == project.id
      :ok
    end)

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> publish(project, %{duration_ms: 1, status: "failure", tasks: []})
      |> json_response(201)

    Buffer.flush()
    {:ok, build} = Gradle.get_build(response["id"], project_id: project.id)
    assert build.actor_account_id == user.account.id
    assert build.submission_auth == "token"
  end

  test "anonymous failures cannot trigger bot comments or automatic agent events", %{conn: conn, project: project} do
    reject(Tuist.VCS, :enqueue_vcs_pull_request_comment, 1)
    reject(Publisher, :publish, 3)
    body = %{duration_ms: 1, status: "failure", tasks: [], git_ref: "refs/pull/123/head", git_branch: "untrusted"}
    assert conn |> publish(project, body) |> json_response(201)
  end

  test "the instance policy alone enables new projects and denies reports when disabled", %{conn: conn, project: project} do
    assert conn |> publish(project) |> json_response(201)
    refute :network_trusted_builds in Tuist.Projects.Project.__schema__(:fields)
    stub(Tuist.Environment, :network_trusted_report_publishing_enabled?, fn -> false end)
    assert conn |> publish(project) |> json_response(401)
  end

  test "build-system changes take effect even with a warmed project cache", %{conn: conn, project: project} do
    warmed =
      conn
      |> assign(:caching, true)
      |> TuistWeb.Plugs.LoaderPlug.assign_selected_project("#{project.account.name}/#{project.name}")

    assert warmed.assigns.selected_project.build_system == :gradle
    {:ok, _} = Tuist.Projects.update_project(project, %{build_system: :xcode})
    assert warmed |> publish(project) |> json_response(403)
  end

  test "missing and wrong-system projects have indistinguishable anonymous denials", %{
    conn: conn,
    project: project
  } do
    wrong_system = ProjectsFixtures.project_fixture(account_id: project.account_id, build_system: :xcode)
    expected = conn |> publish(wrong_system) |> json_response(403)

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post("/api/projects/#{project.account.name}/missing-project/gradle/builds", %{
             duration_ms: 1,
             status: "success",
             tasks: []
           })
           |> json_response(403) == expected

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post("/api/projects/missing-account/missing-project/gradle/builds", %{
             duration_ms: 1,
             status: "success",
             tasks: []
           })
           |> json_response(403) == expected

    assert conn |> publish(wrong_system) |> json_response(403) == expected
  end

  test "authenticated unknown projects retain their not-found response", %{conn: conn, user: user} do
    assert_error_sent 404, fn ->
      conn
      |> TuistWeb.Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")
      |> post("/api/projects/#{user.account.name}/missing-project/gradle/builds", %{
        duration_ms: 1,
        status: "success",
        tasks: []
      })
    end
  end

  test "daily denials return the remaining quota time, rounded up", %{conn: conn, project: project} do
    expect(TuistWeb.RateLimit, :hit, fn _, _ -> {:allow, 1} end)

    expect(TuistWeb.RateLimit, :hit, fn key, _ ->
      assert key == "network-builds:day:#{project.id}"
      {:deny, 3_600_001}
    end)

    response = publish(conn, project)
    assert json_response(response, 429)
    assert get_resp_header(response, "retry-after") == ["3601"]
  end

  test "invalid and malformed credentials cannot downgrade to network trust", %{conn: conn, project: project} do
    for header <- ["Bearer revoked-token", "Basic garbage", "Bearer", ""] do
      assert conn |> put_req_header("authorization", header) |> publish(project) |> json_response(401)
    end
  end

  test "does not make reads, cache or archive endpoints anonymous", %{conn: conn, project: project} do
    path = "/api/projects/#{project.account.name}/#{project.name}"
    assert conn |> get(path <> "/gradle/builds") |> json_response(401)

    for suffix <- ["/tests/shards", "/builds/upload/start", "/runs"] do
      assert conn |> put_req_header("content-type", "application/json") |> post(path <> suffix, %{}) |> json_response(401)
    end
  end

  test "authenticated users retain verified attribution and reject unauthorized projects", %{
    conn: conn,
    project: project,
    user: user
  } do
    conn = TuistWeb.Authentication.put_current_user(conn, user)
    response = conn |> put_req_header("x-tuist-actor-id", "someone-else") |> publish(project) |> json_response(201)
    Buffer.flush()
    {:ok, build} = Gradle.get_build(response["id"], project_id: project.id)
    assert build.account_id == user.account.id
    assert build.actor_account_id == user.account.id
    assert build.submission_auth == "token"
    assert build.actor_account.name == user.account.name
    other_user = AccountsFixtures.user_fixture(preload: [:account])
    assert conn |> TuistWeb.Authentication.put_current_user(other_user) |> publish(project) |> json_response(403)
  end

  test "rejects invalid identifiers and oversized arrays before insertion", %{conn: conn, project: project} do
    response =
      conn
      |> put_req_header("x-tuist-actor-id", String.duplicate("a", 129))
      |> publish(project)
      |> json_response(201)

    Buffer.flush()
    {:ok, build} = Gradle.get_build(response["id"], project_id: project.id)
    assert build.claimed_actor_id == ""

    tasks = List.duplicate(%{task_path: ":compile", outcome: "executed"}, 20_001)
    assert conn |> publish(project, %{duration_ms: 1, status: "success", tasks: tasks}) |> json_response(413)
  end

  test "successful anonymous publishing is rate limited by project, not actor identity", %{conn: conn, project: project} do
    expect(TuistWeb.RateLimit, :hit, fn key, _opts ->
      assert key == "network-builds:minute:#{project.id}"
      {:deny, 60_000}
    end)

    assert conn |> put_req_header("x-tuist-actor-id", "a-new-identity") |> publish(project) |> json_response(429)
  end
end
