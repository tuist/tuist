defmodule TuistWeb.API.NetworkTrustedReportsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Builds
  alias Tuist.ClickHouseRepo
  alias Tuist.MCP.Events.Publisher
  alias Tuist.Mix.Build
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunByCommit
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Plugs.ReportPublishingPlug

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Tuist.Environment, :network_trusted_build_publishing_enabled?, fn -> true end)
    %{user: user}
  end

  defp project(user, system) do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: system)
    {:ok, project} = Projects.update_project(project, %{network_trusted_builds: true})
    project
  end

  defp publish(conn, project, suffix, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-tuist-actor-id", "developer-123")
    |> post("/api/projects/#{project.account.name}/#{project.name}#{suffix}", body)
  end

  test "both Xcode creation routes publish completed data with a fresh ID and no automation", %{conn: conn, user: user} do
    project = project(user, :xcode)
    reject(Tuist.VCS, :enqueue_vcs_pull_request_comment, 1)
    reject(Publisher, :publish, 3)

    for suffix <- ["/builds", "/xcode/builds"] do
      client_id = UUIDv7.generate()

      response =
        conn
        |> publish(project, suffix, %{id: client_id, status: "failure", is_ci: false, duration: 42})
        |> json_response(200)

      refute response["id"] == client_id
      Builds.Build.Buffer.flush()
      {:ok, build} = Builds.get_build(response["id"], project_id: project.id)
      assert build.account_id == 0
      assert build.actor_account_id == 0
      assert build.claimed_actor_id == "developer-123"
      assert build.submission_auth == "network_trusted"
      assert build.status == "failure"
      assert build.duration == 42
    end
  end

  test "Mix builds publish without a user, supplied IDs, or connection notifications", %{conn: conn, user: user} do
    project = project(user, :mix)
    reject(Projects, :notify_connected, 2)
    client_id = UUIDv7.generate()

    response =
      conn |> publish(project, "/mix/builds", %{id: client_id, duration_ms: 42, status: "success"}) |> json_response(201)

    refute response["id"] == client_id
    [build] = ClickHouseRepo.all(from(b in Build, where: b.id == ^response["id"]))
    assert build.account_id == 0
    assert build.claimed_actor_id == "developer-123"
    assert build.submission_auth == "network_trusted"
  end

  test "test reports and their child rows retain unverified actors for each build system", %{conn: conn, user: user} do
    reject(Tuist.VCS, :enqueue_vcs_pull_request_comment, 1)
    reject(Publisher, :publish, 3)

    for system <- [:xcode, :mix, :gradle, :bazel] do
      project = project(user, system)
      client_id = UUIDv7.generate()

      body = %{
        id: client_id,
        build_system: Atom.to_string(system),
        duration: 42,
        is_ci: false,
        status: "failure",
        test_modules: [
          %{
            name: "Module",
            status: "failure",
            duration: 42,
            test_cases: [%{name: "reports a failure", status: "failure", duration: 42}]
          }
        ]
      }

      response = conn |> publish(project, "/tests", body) |> json_response(200)
      refute response["id"] == client_id
      {:ok, test} = Tests.get_test(response["id"], preload: [:test_case_runs])
      assert test.account_id == 0
      assert test.actor_account_id == 0
      assert test.claimed_actor_id == "developer-123"
      assert test.submission_auth == "network_trusted"
      [run] = test.test_case_runs
      assert run.actor_account_id == 0
      assert run.claimed_actor_id == "developer-123"
      assert run.submission_auth == "network_trusted"
    end
  end

  test "Bazel authorization grants publishing only and checks every fresh session", %{conn: conn, user: user} do
    project = project(user, :bazel)
    assert conn |> publish(project, "/bazel/publishing", %{}) |> json_response(200) == %{"network_trusted" => true}
    {:ok, project} = Projects.update_project(project, %{network_trusted_builds: false})
    assert conn |> publish(project, "/bazel/publishing", %{}) |> json_response(403)
    assert conn |> get("/api/cache/access") |> json_response(401)
  end

  test "every reporting route fails closed on supplied invalid credentials", %{conn: conn, user: user} do
    for {system, suffix} <- [xcode: "/builds", mix: "/mix/builds", bazel: "/bazel/publishing", gradle: "/tests"] do
      project = project(user, system)

      assert conn
             |> put_req_header("authorization", "Bearer revoked")
             |> publish(project, suffix, %{})
             |> json_response(401)

      duplicate = %{
        conn
        | req_headers: [{"authorization", "Bearer one"}, {"authorization", "Bearer two"} | conn.req_headers]
      }

      assert duplicate |> publish(project, suffix, %{}) |> json_response(401)
    end
  end

  test "policies deny disabled deployment, project, and wrong project types before schema validation", %{
    conn: conn,
    user: user
  } do
    project = project(user, :mix)
    assert conn |> publish(project, "/builds", %{}) |> json_response(403)
    assert conn |> publish(project, "/tests", %{build_system: "xcode"}) |> json_response(403)
    assert conn |> publish(project, "/tests", %{build_system: %{bad: "type"}}) |> json_response(403)
    {:ok, project} = Projects.update_project(project, %{network_trusted_builds: false})
    assert conn |> publish(project, "/mix/builds", %{}) |> json_response(403)
    {:ok, project} = Projects.update_project(project, %{network_trusted_builds: true})
    stub(Tuist.Environment, :network_trusted_build_publishing_enabled?, fn -> false end)
    assert conn |> publish(project, "/mix/builds", %{}) |> json_response(401)
  end

  test "processing, artifact, shard, history, and report references are refused", %{conn: conn, user: user} do
    project = project(user, :xcode)

    for attrs <- [%{status: "processing"}, %{generation_id: UUIDv7.generate()}, %{xcode_cache_upload_enabled: true}] do
      assert conn |> publish(project, "/builds", attrs) |> json_response(400)
    end

    for key <- [
          :shard_plan_id,
          :build_run_id,
          :gradle_build_id,
          :xcode_coverage_storage_key,
          :git_history,
          :coverage,
          :stress_new_tests
        ] do
      assert conn |> publish(project, "/tests", Map.put(%{}, key, "reference")) |> json_response(400)
    end
  end

  test "nested child data and report collections are bounded before validation", %{conn: conn, user: user} do
    project = project(user, :xcode)
    assert conn |> publish(project, "/builds", %{files: List.duplicate(%{}, 20_001)}) |> json_response(413)

    assert conn
           |> publish(project, "/tests", %{test_modules: [%{test_cases: List.duplicate(%{repetitions: []}, 100_001)}]})
           |> json_response(413)
  end

  test "unknown nested keys, artifacts, and selective-execution claims are rejected without creating atoms", %{
    conn: conn,
    user: user
  } do
    project = project(user, :xcode)
    key = "unknown_report_key_#{System.unique_integer([:positive])}"
    body = %{test_modules: [%{name: "Module", test_cases: [%{key => %{key => "value"}, :name => "test"}]}]}
    assert conn |> publish(project, "/tests", body) |> json_response(400)
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end

    for body <- [
          %{only_test_identifiers: ["existing-test"]},
          %{git_remote_url_origin: "https://example.invalid"},
          %{test_modules: [%{name: "Module", test_cases: [%{name: "test", attachments: [%{storage_key: "existing"}]}]}]}
        ] do
      assert conn |> publish(project, "/tests", body) |> json_response(400)
    end
  end

  test "unsigned tests cannot replace canonical case metadata or become cross-run and automation evidence", %{
    conn: conn,
    user: user
  } do
    project = project(user, :xcode)

    attrs = %{
      id: UUIDv7.generate(),
      ran_at: NaiveDateTime.utc_now(),
      project_id: project.id,
      account_id: user.account.id,
      actor_account_id: user.account.id,
      submission_auth: "token",
      build_system: "xcode",
      is_ci: true,
      scheme: "App",
      duration: 10,
      status: "success",
      git_branch: "main",
      git_commit_sha: String.duplicate("a", 40),
      test_modules: [
        %{
          name: "Module",
          status: "success",
          duration: 10,
          test_cases: [%{name: "known", duration: 10, status: "success"}]
        }
      ]
    }

    {:ok, _} = Tests.create_test(attrs)
    TestCase.Buffer.flush()
    [before] = ClickHouseRepo.all(from(c in TestCase, where: c.project_id == ^project.id))

    payload =
      attrs
      |> Map.drop([:project_id, :account_id, :actor_account_id, :submission_auth])
      |> Map.merge(%{
        ran_at: NaiveDateTime.to_iso8601(attrs.ran_at) <> "Z",
        git_commit_sha: String.duplicate("b", 40),
        status: "failure",
        duration: 99_999,
        test_modules: [
          %{
            name: "Module",
            status: "failure",
            duration: 99_999,
            test_cases: [
              %{name: "known", duration: 99_999, status: "failure"},
              %{name: "claimed-only", duration: 1, status: "success"}
            ]
          }
        ]
      })

    response = conn |> publish(project, "/tests", payload) |> json_response(200)
    {:ok, unsigned} = Tests.get_test(response["id"], preload: [:test_case_runs])
    assert Enum.find(unsigned.test_case_runs, &(&1.name == "known")).test_case_id == before.id
    assert Enum.find(unsigned.test_case_runs, &(&1.name == "claimed-only")).test_case_id == nil
    TestCase.Buffer.flush()
    assert ClickHouseRepo.all(from(c in TestCase, where: c.project_id == ^project.id)) == [before]

    {:ok, verified} =
      Tests.create_test(Map.merge(attrs, %{id: UUIDv7.generate(), git_commit_sha: String.duplicate("b", 40)}))

    {:ok, verified} = Tests.get_test(verified.id, preload: [:test_case_runs])
    refute verified.is_flaky
    assert Enum.all?(verified.test_case_runs, &(not &1.is_flaky))
    TestCaseRun.Buffer.flush()
    assert ClickHouseRepo.aggregate(from(r in TestCaseRunByCommit, where: r.project_id == ^project.id), :count) == 2

    count =
      ClickHouseRepo.one(
        from(r in {"test_case_run_daily_stats_per_case", TestCaseRun},
          where: r.project_id == ^project.id,
          select: fragment("countMerge(run_count)")
        )
      )

    assert count == 2
  end

  test "report-only policy never authenticates a subject", %{conn: conn, user: user} do
    project = project(user, :bazel)
    conn = publish(conn, project, "/bazel/publishing", %{})
    assert ReportPublishingPlug.network_publisher?(conn)
    refute TuistWeb.Authentication.authenticated?(conn)
  end
end
