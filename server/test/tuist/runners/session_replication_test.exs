defmodule Tuist.Runners.SessionReplicationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.ConcurrencySession
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.SessionReplication
  alias Tuist.Runners.Workers.ReplicateRunnerSessionsWorker

  test "releases the slot when the runner's own job completed, not when the claimed job did" do
    account = account_fixture()
    claimed_job_id = System.unique_integer([:positive])
    executed_job_id = System.unique_integer([:positive])

    # The claimed job was handed to a different runner and finishes
    # hours later; this Pod ran a sibling and freed the slot when that
    # one ended.
    completion_fixture(account, executed_job_id, datetime("2026-07-10T10:40:00Z"))
    completion_fixture(account, claimed_job_id, datetime("2026-07-10T15:00:00Z"))

    session =
      session_fixture(account,
        workflow_job_id: claimed_job_id,
        executed_workflow_job_id: executed_job_id,
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        started_at: datetime("2026-07-10T10:10:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    assert replicated(session).released_at == ~U[2026-07-10 10:40:00.000000Z]
  end

  test "releases the slot at the job's end rather than the Pod's teardown" do
    account = account_fixture()

    session =
      session_fixture(account,
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        started_at: datetime("2026-07-10T10:10:00Z"),
        job_ended_at: datetime("2026-07-10T10:50:00Z"),
        ended_at: datetime("2026-07-10T11:30:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    replica = replicated(session)
    assert replica.released_at == ~U[2026-07-10 10:50:00.000000Z]
    assert replica.platform == "macos"
    assert replica.vcpus == 6
  end

  test "never holds the slot past the Pod stop" do
    account = account_fixture()
    workflow_job_id = System.unique_integer([:positive])

    # A Pod that stopped without ever running the job it claimed: that
    # job's own completion lands much later, elsewhere.
    completion_fixture(account, workflow_job_id, datetime("2026-07-10T13:30:00Z"))

    session =
      session_fixture(account,
        workflow_job_id: workflow_job_id,
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        started_at: datetime("2026-07-10T10:10:00Z"),
        ended_at: datetime("2026-07-10T10:40:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    assert replicated(session).released_at == ~U[2026-07-10 10:40:00.000000Z]
  end

  test "bounds a session whose close was never reported by the runner session ceiling" do
    account = account_fixture()

    session =
      session_fixture(account,
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        started_at: datetime("2026-07-10T10:10:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    assert replicated(session).released_at == ~U[2026-07-10 16:10:00.000000Z]
  end

  test "uses fleet platform and default resources for legacy rows" do
    account = account_fixture()
    default = Catalog.default_shape(:linux)

    session =
      session_fixture(account,
        fleet_name: "linux-amd64",
        started_at: datetime("2026-07-10T10:10:00Z"),
        job_ended_at: datetime("2026-07-10T10:40:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    replica = replicated(session)
    assert replica.platform == "linux"
    assert replica.vcpus == default.vcpus
    assert replica.memory_gb == default.memory_gb
  end

  test "uses the fleet's configured shape for legacy history" do
    account = account_fixture()
    shape = Enum.find(Catalog.shapes(:linux), &(!&1.default?))
    fleet_name = Catalog.pool_name(Map.put(shape, :platform, :linux))

    session =
      session_fixture(account,
        fleet_name: fleet_name,
        started_at: datetime("2026-07-10T10:10:00Z"),
        job_ended_at: datetime("2026-07-10T10:40:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    replica = replicated(session)
    assert replica.vcpus == shape.vcpus
    assert replica.memory_gb == shape.memory_gb
  end

  test "skips a session whose fleet resolves to no known platform" do
    account = account_fixture()

    session =
      session_fixture(account,
        fleet_name: "retired-pool",
        started_at: datetime("2026-07-10T10:10:00Z"),
        job_ended_at: datetime("2026-07-10T10:40:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    assert replicated(session) == nil
  end

  test "re-ingests a session whose release moved after it was first copied" do
    account = account_fixture()

    session =
      session_fixture(account,
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        started_at: datetime("2026-07-10T10:10:00Z")
      )

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())
    assert replicated(session).released_at == ~U[2026-07-10 16:10:00.000000Z]

    session
    |> Ecto.Changeset.change(%{
      job_ended_at: datetime("2026-07-10T10:40:00Z"),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
    |> Repo.update!()

    {:ok, _, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    assert replicated(session).released_at == ~U[2026-07-10 10:40:00.000000Z]
  end

  # The replica's own high-water mark is the resume point, so an empty
  # one has to walk history rather than only tailing new rows.
  test "copies sessions that predate anything already in the replica" do
    account = account_fixture()

    session =
      session_fixture(account,
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        started_at: datetime("2024-01-01T10:10:00Z"),
        job_ended_at: datetime("2024-01-01T10:40:00Z")
      )

    {:ok, count, _} = SessionReplication.replicate_batch(SessionReplication.start_cursor())

    assert count >= 1
    assert replicated(session).released_at == ~U[2024-01-01 10:40:00.000000Z]
  end

  # A drain only continues while batches come back full. Re-deriving the
  # resume point per batch would re-select the same first rows every
  # time once the overlap window held a full batch, and nothing newer
  # would ever replicate.
  @tag timeout: 120_000
  test "drains past a full batch that fits inside the overlap window" do
    account = account_fixture()
    updated_at = DateTime.truncate(DateTime.utc_now(), :second)
    started_at = datetime("2026-07-10T10:10:00Z")
    count = SessionReplication.batch_size() + 1

    rows =
      Enum.map(1..count, fn index ->
        %{
          account_id: account.id,
          workflow_job_id: System.unique_integer([:positive]),
          fleet_name: "linux-pool",
          pod_name: "pod-overlap-#{index}",
          runner_name: "",
          platform: :linux,
          vcpus: 4,
          memory_gb: 16,
          started_at: started_at,
          job_ended_at: datetime("2026-07-10T10:40:00Z"),
          ended_at: nil,
          inserted_at: updated_at,
          updated_at: updated_at
        }
      end)

    Enum.each(Enum.chunk_every(rows, 2_000), &Repo.insert_all(RunnerSession, &1))

    :ok = perform_job(ReplicateRunnerSessionsWorker, %{})

    assert replicated_count(account) == count
  end

  # The latest ingest read the fresher Postgres row, so it has to win
  # the version comparison the reader resolves.
  defp replicated(%RunnerSession{id: id}) do
    IngestRepo.one(
      from(s in ConcurrencySession,
        where: s.id == ^id,
        order_by: [desc: s.ingested_at],
        limit: 1
      )
    )
  end

  defp replicated_count(account) do
    IngestRepo.one(
      from(s in ConcurrencySession,
        where: s.account_id == ^account.id,
        select: fragment("uniqExact(?)", s.id)
      )
    )
  end

  defp session_fixture(account, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "linux-pool",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: DateTime.utc_now(),
      ended_at: nil,
      job_ended_at: nil,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
  end

  defp completion_fixture(account, workflow_job_id, %DateTime{} = completed_at) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(%JobCompletion{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      conclusion: "success",
      completed_at: DateTime.truncate(completed_at, :second),
      inserted_at: now,
      updated_at: now
    })
  end

  defp datetime(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    %{datetime | microsecond: {0, 6}}
  end
end
