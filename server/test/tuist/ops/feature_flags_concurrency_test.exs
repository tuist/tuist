defmodule Tuist.Ops.FeatureFlagsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias FunWithFlags.Gate
  alias FunWithFlags.Store.Persistent.Ecto, as: Persistence
  alias FunWithFlags.Store.Persistent.Ecto.Record
  alias Tuist.Ops.FeatureFlagChange
  alias Tuist.Ops.FeatureFlags
  alias Tuist.Repo

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    records = from(r in Record, where: r.flag_name == "qa_billing_enabled")
    previous = Repo.all(records)
    Repo.delete_all(records)
    change_id = Ecto.UUID.generate()

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.delete_all(records)
        Enum.each(previous, &Repo.insert!/1)
        Repo.delete_all(from(c in FeatureFlagChange, where: c.change_id == ^change_id))
        FunWithFlags.Store.reload(:qa_billing_enabled)
      after
        Sandbox.checkin(Repo)
      end
    end)

    %{change_id: change_id}
  end

  test "a concurrent legacy percentage update cannot create conflicting gates or be overwritten by a stale Atlas request",
       %{change_id: change_id} do
    parent = self()
    {:ok, before} = FeatureFlags.get("qa_billing_enabled")

    legacy =
      database_task(fn ->
        receive do
          :start -> Persistence.put(:qa_billing_enabled, Gate.new(:percentage_of_actors, 0.75))
        end
      end)

    handler = {__MODULE__, make_ref()}
    paused = :atomics.new(1, [])

    :ok =
      :telemetry.attach(
        handler,
        [:tuist, :repo, :query],
        &__MODULE__.pause_percentage_read/4,
        {legacy.pid, parent, paused}
      )

    try do
      send(legacy.pid, :start)
      assert_receive :legacy_percentage_read, 5_000

      atlas =
        database_task(fn ->
          %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:atlas_started, backend_pid})

          FeatureFlags.update(
            "qa_billing_enabled",
            %{
              "operation" => "enable",
              "scope" => "percentage",
              "percentage" => 12.5,
              "expected_revision" => before.revision,
              "reason" => "Measured rollout",
              "change_id" => change_id,
              "actor" => %{"id" => Ecto.UUID.generate(), "email" => "operator@example.test"},
              "interface" => "mcp"
            },
            %{"namespace" => "atlas-production", "name" => "atlas"}
          )
        end)

      try do
        assert_receive {:atlas_started, backend_pid}, 5_000
        assert wait_until_blocked(backend_pid, 500)
        send(legacy.pid, :commit)
        assert {:ok, _flag} = Task.await(legacy, 5_000)
        assert {:error, :stale_revision} = Task.await(atlas, 5_000)
        assert {:ok, %{gates: [%Gate{type: :percentage_of_actors, for: 0.75}]}} = Persistence.get(:qa_billing_enabled)
        refute Repo.get_by(FeatureFlagChange, change_id: change_id)
      after
        Task.shutdown(atlas, :brutal_kill)
      end
    after
      :telemetry.detach(handler)
      send(legacy.pid, :commit)
      Task.shutdown(legacy, :brutal_kill)
    end
  end

  def pause_percentage_read(_event, _measurements, %{query: query}, {legacy, parent, paused}) do
    if self() == legacy and String.starts_with?(query, "SELECT") and String.contains?(query, "\"feature_flags\"") and
         :atomics.compare_exchange(paused, 1, 0, 1) == :ok do
      send(parent, :legacy_percentage_read)

      receive do
        :commit -> :ok
      after
        10_000 -> raise "legacy percentage writer was not released"
      end
    end
  end

  defp database_task(function) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        function.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_until_blocked(_backend_pid, 0), do: false

  defp wait_until_blocked(backend_pid, attempts) do
    case Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid]).rows do
      [[true]] ->
        true

      [[false]] ->
        Process.sleep(10)
        wait_until_blocked(backend_pid, attempts - 1)
    end
  end
end
