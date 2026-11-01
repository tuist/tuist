defmodule Tuist.BuildEntities.CargoTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Identity
  alias Tuist.BuildEntities.Observation
  alias Tuist.Cargo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    FunWithFlags.enable(:build_entities, for_actor: project)

    conn =
      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, project: project}
  end

  test "HTTP reports materialize crates and retry-safe rustc history without parent timing or cache inference",
       %{
         conn: conn,
         user: user,
         project: project
       } do
    root = "/api/projects/#{user.account.name}/#{project.name}/cargo"
    payload = report()

    payload = %{
      payload
      | compilations: [
          compilation(),
          compilation(status: "failure", duration_ms: 90, start_offset_ms: 20)
        ]
    }

    for _ <- 1..2 do
      assert %{"id" => id} = conn |> post(root <> "/builds", payload) |> json_response(:created)
      assert id == payload.id
    end

    Observation.Buffer.flush()
    inventory = conn |> get(root <> "/crates") |> json_response(200)
    assert [%{"id" => id, "identity" => identity}] = inventory["crates"]
    assert identity == %{"source" => "src/lib.rs", "name" => "widgets", "kind" => "lib"}
    assert id == Identity.id(project.id, :cargo, "crate", identity)

    detail = conn |> get(root <> "/crates/#{id}") |> json_response(200)
    total = detail["analytics"]["total"]
    assert total["observations"] == 2
    assert total["failures"] == 1
    assert total["duration_samples"] == 2
    assert total["avg_duration_ms"] == 45
    assert is_nil(total["hit_rate"])

    history = conn |> get(root <> "/crates/#{id}/compilations") |> json_response(200)
    assert [failed, succeeded] = history["compilations"]
    assert {failed["duration_ms"], failed["status"]} == {90, "failure"}
    assert {succeeded["duration_ms"], succeeded["status"]} == {0, "success"}
    assert failed["id"] != succeeded["id"]

    assert Enum.all?(
             history["compilations"],
             &(&1["parent_id"] == payload.id and &1["cache_status"] == "none")
           )

    assert failed["observed_at"]
           |> DateTime.from_iso8601()
           |> elem(1)
           |> DateTime.diff(
             payload.started_at,
             :millisecond
           ) == 20

    contexts = BuildEntities.parent_contexts(project.id, :cargo, "crate", [payload.id])
    assert contexts[payload.id].label == "cargo build"
    assert contexts[payload.id].ran_by_name == user.account.name
    assert BuildEntities.parent_contexts(project.id + 1, :cargo, "crate", [payload.id]) == %{}

    another = %{payload | id: UUIDv7.generate(), compilations: [compilation()]}
    assert conn |> post(root <> "/builds", another) |> json_response(:created)
    Observation.Buffer.flush()
    assert {[_crate], _} = BuildEntities.list(project.id, :cargo, "crate")
    assert {rows, %{total_count: 3}} = BuildEntities.history(project.id, :cargo, "crate", id)
    assert length(rows) == 3
    assert {:error, :not_found} = BuildEntities.get(project.id + 1, :cargo, "crate", id)
    assert {:error, :not_found} = BuildEntities.get(project.id, :mix, "module", id)
  end

  test "native replay and multiple kinds or roots preserve only recorded identity", %{
    project: project,
    user: user
  } do
    payload =
      Map.merge(report(), %{
        project_id: project.id,
        account_id: user.account.id,
        compilations: [
          compilation(),
          compilation(duration_ms: 100, start_offset_ms: 20),
          compilation(kind: "test"),
          compilation(source: "other/src/lib.rs")
        ]
      })

    for _ <- 1..2, do: assert({:ok, _} = Cargo.create_build(payload))
    Observation.Buffer.flush()
    assert {crates, %{total_count: 3}} = BuildEntities.list(project.id, :cargo, "crate")
    assert length(crates) == 3

    id =
      Identity.id(project.id, :cargo, "crate", %{
        "source" => "src/lib.rs",
        "name" => "widgets",
        "kind" => "lib"
      })

    assert {rows, %{total_count: 2}} = BuildEntities.history(project.id, :cargo, "crate", id)
    assert Enum.sort(Enum.map(rows, & &1.duration_ms)) == [0, 100]
    assert Enum.all?(rows, &(&1.git_branch == "main" and &1.is_ci == true))
  end

  test "missing identity stays accepted in native reports but unindexed", %{
    project: project,
    user: user
  } do
    payload =
      Map.merge(report(), %{
        project_id: project.id,
        account_id: user.account.id,
        compilations: [
          compilation(source: ""),
          compilation(name: ""),
          compilation(name: "unknown"),
          compilation(kind: "")
        ]
      })

    assert {:ok, id} = Cargo.create_build(payload)
    assert {:ok, build} = Cargo.get_build(id, project.id)
    assert length(Cargo.compilations(build)) == 4
    assert {[], _} = BuildEntities.list(project.id, :cargo, "crate")
  end

  test "flag-off and kill-switch preserve native ingestion while hiding crate resources", %{
    conn: conn,
    project: project,
    user: user
  } do
    root = "/api/projects/#{user.account.name}/#{project.name}/cargo"
    FunWithFlags.disable(:build_entities, for_actor: project)
    payload = report()
    assert conn |> post(root <> "/builds", payload) |> json_response(:created)
    assert {:ok, build} = Cargo.get_build(payload.id, project.id)
    assert [_] = Cargo.compilations(build)
    assert {[], _} = BuildEntities.list(project.id, :cargo, "crate")

    FunWithFlags.enable(:build_entities, for_actor: project)
    stub(FunWithFlags, :enabled?, fn :build_entities_kill_switch -> true end)
    payload = report()
    assert conn |> post(root <> "/builds", payload) |> json_response(:created)
    assert {:ok, build} = Cargo.get_build(payload.id, project.id)
    assert [_] = Cargo.compilations(build)
    assert {[], _} = BuildEntities.list(project.id, :cargo, "crate")
    reject(BuildEntities, :list, 4)
    reject(BuildEntities, :get, 4)

    for path <- [
          "/crates",
          "/crates/#{UUIDv7.generate()}",
          "/crates/#{UUIDv7.generate()}/compilations"
        ] do
      assert conn |> get(root <> path) |> json_response(404)
    end
  end

  test "cache-only and legacy nextest reports cannot fabricate crate activity", %{
    project: project,
    user: user
  } do
    payload = Map.merge(report(), %{project_id: project.id, account_id: user.account.id})
    assert {:ok, _} = Cargo.create_build(%{payload | command: "nextest"})

    assert {:ok, _} =
             Cargo.create_build(
               Map.merge(payload, %{
                 id: UUIDv7.generate(),
                 compilations: [],
                 cache: %{version: 1, hits: 10}
               })
             )

    assert {[], _} = BuildEntities.list(project.id, :cargo, "crate")
  end

  defp report do
    %{
      id: UUIDv7.generate(),
      command: "build",
      status: "failure",
      duration_ms: 9999,
      started_at: DateTime.add(DateTime.utc_now(), -300, :second),
      git_branch: "main",
      git_commit_sha: "abc123",
      is_ci: true,
      compilations: [compilation()]
    }
  end

  defp compilation(attrs \\ []) do
    Map.merge(
      %{
        name: "widgets",
        source: "src/lib.rs",
        kind: "lib",
        dependencies: [],
        start_offset_ms: 10,
        duration_ms: 0,
        status: "success"
      },
      Map.new(attrs)
    )
  end
end
