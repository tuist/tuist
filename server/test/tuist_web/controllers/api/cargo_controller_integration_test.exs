defmodule TuistWeb.API.CargoControllerIntegrationTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import Ecto.Query
  import Phoenix.ConnTest

  alias Tuist.Cargo
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @endpoint TuistWeb.Endpoint

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    %{conn: conn, user: user, project: project}
  end

  defp report do
    %{
      id: Ecto.UUID.generate(),
      duration_ms: 123,
      status: "failure",
      command: "build",
      rust_version: "rustc 1.97.1",
      started_at: "2026-10-07T12:00:00Z",
      compilations: [
        %{
          name: "widgets",
          source: "src/lib.rs",
          kind: "lib",
          start_offset_ms: 10,
          duration_ms: 90,
          status: "failure",
          dependencies: ["serde"],
          diagnostics: [%{severity: "error", message: "type mismatch <script>", file: "src/lib.rs", line: 7}]
        }
      ]
    }
  end

  test "persists compiler observations and scopes every read to the project", %{conn: conn, user: user, project: project} do
    payload = report()
    Tuist.PubSub.subscribe("projects.#{project.id}")
    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/cargo/builds", payload)
    assert json_response(conn, :created) == %{"id" => payload.id}
    assert_receive {:show, %{user: %{id: id}}}
    assert id == user.id
    assert {:ok, build} = Cargo.get_build(payload.id, project.id)
    assert build.duration_ms == 123
    assert build.status == "failure"
    assert build.started_at == ~N[2026-10-07 12:00:00.000000]
    assert [compilation] = Cargo.compilations(build)
    assert compilation.name == "widgets"
    assert compilation.dependencies == ["serde"]
    assert [%{"severity" => "error", "line" => 7}] = JSON.decode!(compilation.diagnostics)
    assert {:error, :not_found} = Cargo.get_build(payload.id, project.id + 1)
    assert {[], _meta} = Cargo.list_builds(project.id + 1)
  end

  test "persists bounded cache measurements without inventing local or remote hits", %{
    conn: conn,
    user: user,
    project: project
  } do
    payload =
      Map.put(report(), :cache, %{
        version: 1,
        hits: 12,
        misses: 2,
        unconsulted: 3,
        downloaded_bytes: 4096,
        prefetched_actions: 4
      })

    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/cargo/builds", payload)
    assert json_response(conn, :created) == %{"id" => payload.id}
    assert {:ok, build} = Cargo.get_build(payload.id, project.id)
    assert metrics = CacheMetrics.read(build)
    assert metrics.hits == 12
    assert metrics.downloaded_bytes == 4096
    assert metrics.unconsulted == 3
    assert CacheMetrics.task_misses(metrics) == 5
    assert CacheMetrics.hit_rate(metrics) == 70.6
    refute Map.has_key?(metrics, :remote_hits)
    assert {:error, :not_found} = Cargo.get_build(payload.id, project.id + 1)
  end

  test "persists public task and CAS inspection under the authorized parent build", %{
    conn: conn,
    user: user,
    project: project
  } do
    action = "blake3:#{String.duplicate("a", 64)}:123"
    object = "sha256:#{String.duplicate("b", 64)}:456"

    details = %{
      version: 1,
      truncated: false,
      tasks: [%{key: action, name: "widgets", kind: "rust", status: "hit", cas_keys: [object], read_duration_ns: 1000}],
      cas_outputs: [%{key: object, operation: "download", status: "downloaded", size_bytes: 456, duration_ns: 2000}]
    }

    payload = Map.put(report(), :cache, %{version: 1, hits: 1, details: details})
    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/cargo/builds", payload)
    assert json_response(conn, :created) == %{"id" => payload.id}
    assert {:ok, build} = Cargo.get_build(payload.id, project.id)
    assert CacheMetrics.read(build).details == details
    assert {:error, :not_found} = Cargo.get_build(payload.id, project.id + 1)
  end

  test "rejects invalid cache metrics before buffering", %{conn: conn, user: user, project: project} do
    payload = Map.put(report(), :cache, %{version: 1, hits: -1})
    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/cargo/builds", payload)
    assert json_response(conn, :bad_request)
    assert {:error, :not_found} = Cargo.get_build(payload.id, project.id)
    assert {:error, :invalid_cache_metrics} = CacheMetrics.encode(%{version: 1, environment: "secret"})
    assert CacheMetrics.hit_rate(%{hits: 0, misses: 0}) == nil
  end

  test "rejects oversized or malformed observations without storing a build", %{conn: conn, user: user, project: project} do
    payload = put_in(report(), [:compilations, Access.at(0), :duration_ms], -1)
    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/cargo/builds", payload)
    assert json_response(conn, :bad_request)
    assert {:error, :not_found} = Cargo.get_build(payload.id, project.id)
  end

  test "plans binary-granularity shards without interpreting binary IDs as suite paths", %{
    conn: conn,
    user: user,
    project: project
  } do
    modules = ["widgets::test/parser", "widgets::test/smoke"]

    conn =
      post(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/shards", %{
        reference: "cargo-binaries",
        modules: modules,
        parallelizable_modules: modules,
        granularity: "module",
        shard_total: 2
      })

    result = json_response(conn, :ok)
    assert result["shard_count"] == 2
    assert result["shards"] |> Enum.flat_map(& &1["test_targets"]) |> Enum.sort() == Enum.sort(modules)
  end

  test "keeps per-test identities and retry attempts in the shared test ingestion", %{
    conn: conn,
    user: user,
    project: project
  } do
    payload = %{
      id: Ecto.UUID.generate(),
      build_system: "cargo",
      is_ci: false,
      duration: 200,
      status: "success",
      execution_mode: "parallel",
      scheme: "nextest",
      test_modules: [
        %{
          name: "widgets::integration/smoke",
          duration: 200,
          status: "success",
          test_suites: [%{name: "network", duration: 200, status: "success"}],
          test_cases: [
            %{
              name: "connects",
              test_suite_name: "network",
              duration: 200,
              status: "success",
              repetitions: [
                %{name: "Attempt 1", repetition_number: 1, duration: 100, status: "failure", source: "run"},
                %{name: "Attempt 2", repetition_number: 2, duration: 100, status: "success", source: "run"}
              ]
            }
          ]
        }
      ],
      enumerated_tests: [%{module: "widgets::integration/smoke", suite: "network", name: "connects", enabled: true}]
    }

    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/tests", payload)
    assert response = json_response(conn, :ok)
    assert response["id"] == payload.id
    assert [test] = ClickHouseRepo.all(from(t in TestCaseRun, where: t.test_run_id == ^payload.id))
    assert test.name == "connects"
    assert test.suite_name == "network"
    assert test.module_name == "widgets::integration/smoke"
    assert test.is_flaky
  end
end
