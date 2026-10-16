defmodule Tuist.Gradle.BuildIdIndexTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.ClickHouse.SchemaClone
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.GradleFixtures
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

  test "gradle_builds has a bloom filter index on the build ID" do
    assert {:ok, %{rows: [["bloom_filter", "id", 1]]}} =
             ClickHouseRepo.query("""
             SELECT type, expr, granularity
             FROM system.data_skipping_indices
             WHERE database = currentDatabase() AND table = 'gradle_builds' AND name = 'idx_id'
             """)
  end

  test "project-scoped lookups by build ID consult the index and keep their results" do
    project = ProjectsFixtures.project_fixture()
    build_id = GradleFixtures.build_fixture(project_id: project.id)
    other_id = GradleFixtures.build_fixture(project_id: project.id)

    params = %{project_id: project.id, ids: [build_id, UUIDv7.generate()]}

    lookup = """
    SELECT toString(id)
    FROM gradle_builds
    WHERE project_id = {project_id:Int64} AND id IN {ids:Array(UUID)}
    """

    assert {:ok, %{rows: [[^build_id]]}} = ClickHouseRepo.query(lookup, params)

    {:ok, %{rows: plan}} = ClickHouseRepo.query("EXPLAIN indexes = 1 " <> lookup, params)
    assert Enum.any?(plan, fn [line] -> String.contains?(line, "idx_id") end)

    assert {:ok, %{id: ^other_id}} = Gradle.get_build(other_id, project_id: project.id)
  end

  test "per-partition materialization statements are accepted by ClickHouse" do
    GradleFixtures.build_fixture(project_id: ProjectsFixtures.project_fixture().id)
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")
    partition_ids = SchemaClone.partition_ids(IngestRepo, database, "gradle_builds")

    assert partition_ids != []

    for statement <- SchemaClone.materialize_index_statements(database, "gradle_builds", "idx_id", partition_ids) do
      assert {:ok, _} = IngestRepo.query(statement)
    end
  end
end
