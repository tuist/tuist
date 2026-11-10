defmodule Tuist.Mix.BuildIdIndexTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Mix
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # Skip-index metadata (`system.data_skipping_indices`, `system.parts`) and
  # mutations are not supported inside the ClickHouse transaction DataCase
  # wraps every test in, so these run on an unsandboxed connection. Rows stay
  # committed and are isolated by the fresh project each test creates.
  setup do
    Mimic.stub(Tuist.Tasks, :run_async, fn fun -> fun.() end)
    repo = Sandbox.start_owner!(Tuist.Repo, shared: true)
    ingest_repo = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)

    on_exit(fn ->
      Sandbox.stop_owner(ingest_repo)
      Sandbox.stop_owner(repo)
    end)
  end

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{project: ProjectsFixtures.project_fixture(account_id: user.account.id), account: user.account}
  end

  test "mix_builds has a bloom filter index on the build ID" do
    assert {:ok, %{rows: [["bloom_filter", "id", 1]]}} =
             ClickHouseRepo.query("""
             SELECT type, expr, granularity
             FROM system.data_skipping_indices
             WHERE database = currentDatabase() AND table = 'mix_builds' AND name = 'idx_id'
             """)
  end

  test "project-scoped lookups by build ID consult the index and keep their results", %{
    project: project,
    account: account
  } do
    build_id = build(project, account)
    other_id = build(project, account)

    params = %{project_id: project.id, ids: [build_id, UUIDv7.generate()]}

    lookup = """
    SELECT toString(id)
    FROM mix_builds
    WHERE project_id = {project_id:Int64} AND id IN {ids:Array(UUID)}
    """

    assert {:ok, %{rows: [[^build_id]]}} = ClickHouseRepo.query(lookup, params)

    {:ok, %{rows: plan}} = ClickHouseRepo.query("EXPLAIN indexes = 1 " <> lookup, params)
    assert Enum.any?(plan, fn [line] -> String.contains?(line, "idx_id") end)

    assert {:ok, %{id: ^other_id}} = Mix.get_build(other_id, project.id)
  end

  test "per-partition materialization statements are accepted by ClickHouse", %{project: project, account: account} do
    build(project, account)
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")
    partition_ids = IndexMaterialization.partition_ids(IngestRepo, database, "mix_builds")

    assert partition_ids != []

    for statement <- IndexMaterialization.materialize_index_statements(database, "mix_builds", "idx_id", partition_ids) do
      assert {:ok, _} = IngestRepo.query(statement)
    end
  end

  defp build(project, account) do
    {:ok, id} =
      Mix.create_build(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration_ms: 10,
        status: "success"
      })

    id
  end
end
