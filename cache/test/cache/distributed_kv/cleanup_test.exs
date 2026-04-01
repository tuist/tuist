defmodule Cache.DistributedKV.CleanupTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Project
  alias Cache.DistributedKV.Repo
  alias Cache.DistributedKV.State
  alias Cache.KeyValueRepo
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup_all do
    ensure_distributed_repo_storage!()

    case start_supervised(Repo) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, &Ecto.Migrator.run(&1, :up, all: true))

    :ok
  end

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok = Sandbox.checkout(KeyValueRepo)
    Sandbox.mode(Repo, {:shared, self()})
    Sandbox.mode(KeyValueRepo, {:shared, self()})
    Repo.delete_all(Entry)
    Repo.delete_all(Project)
    KeyValueRepo.delete_all(State)
    stub(Config, :distributed_kv_cleanup_lease_ms, fn -> 60_000 end)
    :ok
  end

  describe "begin_project_cleanup/2" do
    test "concurrent cleanup requests reject overlapping workers" do
      parent = self()

      task_fun = fn ->
        Sandbox.allow(Repo, parent, self())
        send(parent, {:ready, self()})

        receive do
          :go -> Cleanup.begin_project_cleanup("acme", "ios")
        end
      end

      task_1 = Task.async(task_fun)
      task_2 = Task.async(task_fun)

      ready_pids =
        for _ <- 1..2 do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(ready_pids, &send(&1, :go))

      results = [Task.await(task_1), Task.await(task_2)]

      assert Enum.count(results, &match?({:ok, %DateTime{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :cleanup_already_in_progress})) == 1

      assert 1 == Repo.aggregate(Project, :count)
    end

    test "uses shared database time for lease acquisition" do
      cleanup_cutoff = ~U[2026-03-12 12:00:00.123456Z]

      expect(Repo, :insert_all, fn Project, %Ecto.Query{} = insert_query, opts ->
        {insert_sql, _params} = SQL.to_sql(:all, Repo, insert_query)
        {conflict_sql, _params} = SQL.to_sql(:update_all, Repo, opts[:on_conflict])

        assert insert_sql =~ "clock_timestamp()"
        assert conflict_sql =~ "clock_timestamp()"
        assert opts[:conflict_target] == [:account_handle, :project_handle]
        assert opts[:returning] == [:active_cleanup_cutoff_at]

        {1, [%{active_cleanup_cutoff_at: cleanup_cutoff}]}
      end)

      assert {:ok, ^cleanup_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
    end

    test "expired cleanup leases get a fresh cutoff" do
      stale_cutoff = DateTime.add(DateTime.utc_now(), -120, :second)
      stale_lease = DateTime.add(DateTime.utc_now(), -60, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: stale_cutoff,
        cleanup_lease_expires_at: stale_lease,
        updated_at: stale_cutoff
      })

      assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
      assert DateTime.after?(fresh_cutoff, stale_cutoff)

      assert %Project{active_cleanup_cutoff_at: persisted_cutoff, cleanup_lease_expires_at: persisted_lease} =
               Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")

      assert persisted_cutoff == fresh_cutoff
      assert DateTime.after?(persisted_lease, fresh_cutoff)
    end

    test "can acquire cleanup when active state was cleared by failed cleanup" do
      cutoff = DateTime.add(DateTime.utc_now(), -60, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: nil,
        cleanup_lease_expires_at: nil,
        updated_at: cutoff
      })

      assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
      assert DateTime.after?(fresh_cutoff, cutoff)
    end
  end

  describe "renew_project_cleanup_lease/3" do
    test "extends the active lease for the same cleanup" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -5, :second)
      initial_lease = DateTime.add(now, 10, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: initial_lease,
        updated_at: cutoff
      })

      assert :ok = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)

      renewed = Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")
      assert DateTime.after?(renewed.cleanup_lease_expires_at, initial_lease)
      assert DateTime.after?(renewed.updated_at, cutoff)
    end

    test "reports when the lease is no longer active" do
      cutoff = DateTime.utc_now()

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(cutoff, -1, :second),
        updated_at: cutoff
      })

      assert {:error, :cleanup_lease_lost} = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
    end

    test "uses shared database time for lease checks" do
      cutoff = ~U[2026-03-12 12:00:00.123456Z]

      expect(Repo, :update_all, fn %Ecto.Query{} = query, updates ->
        update_query = from(project in query, update: ^updates)
        {sql, _params} = SQL.to_sql(:update_all, Repo, update_query)

        assert sql =~ "clock_timestamp()"
        {1, nil}
      end)

      assert :ok = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
    end
  end

  describe "publish_project_cleanup/3" do
    test "returns published state from the same update statement" do
      cutoff = ~U[2026-03-12 12:00:00.123456Z]

      published = %{
        published_cleanup_generation: 3,
        published_cleanup_cutoff_at: ~U[2026-03-12 12:00:00Z],
        cleanup_event_id: 42
      }

      expect(Repo, :update_all, fn %Ecto.Query{} = query, [] ->
        {sql, _params} = SQL.to_sql(:update_all, Repo, query)

        assert sql =~ "RETURNING"
        assert sql =~ "nextval('cleanup_event_id_seq')"
        assert sql =~ "date_trunc('second'"

        {1, [published]}
      end)

      reject(Repo, :one!, 1)
      reject(Repo, :one!, 2)

      assert {:ok, ^published} = Cleanup.publish_project_cleanup("acme", "ios", cutoff)
    end

    test "publishes cleanup and clears active state" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -5, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff
      })

      assert {:ok, published} = Cleanup.publish_project_cleanup("acme", "ios", cutoff)
      assert published.published_cleanup_generation == 1
      assert DateTime.truncate(published.published_cleanup_cutoff_at, :second) == DateTime.truncate(cutoff, :second)
      assert published.cleanup_event_id > 0

      project = Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")
      assert is_nil(project.active_cleanup_cutoff_at)
      assert is_nil(project.cleanup_lease_expires_at)
      assert project.published_cleanup_generation == 1
      assert project.cleanup_event_id == published.cleanup_event_id
    end

    test "increments generation on repeated cleanups" do
      now = DateTime.utc_now()
      cutoff1 = DateTime.add(now, -10, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff1,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff1
      })

      assert {:ok, published1} = Cleanup.publish_project_cleanup("acme", "ios", cutoff1)
      assert published1.published_cleanup_generation == 1

      cutoff2 = DateTime.add(now, -5, :second)

      Repo.update_all(
        from(p in Project,
          where: p.account_handle == "acme" and p.project_handle == "ios"
        ),
        set: [
          active_cleanup_cutoff_at: cutoff2,
          cleanup_lease_expires_at: DateTime.add(now, 120, :second)
        ]
      )

      assert {:ok, published2} = Cleanup.publish_project_cleanup("acme", "ios", cutoff2)
      assert published2.published_cleanup_generation == 2
      assert published2.cleanup_event_id > published1.cleanup_event_id
    end

    test "fails when the active cleanup is not current" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -5, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff
      })

      wrong_cutoff = DateTime.add(cutoff, -10, :second)
      assert {:error, :cleanup_not_active} = Cleanup.publish_project_cleanup("acme", "ios", wrong_cutoff)
    end
  end

  describe "expire_project_cleanup_lease/3" do
    test "clears active state without leaving a published barrier behind" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -5, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff
      })

      assert :ok = Cleanup.expire_project_cleanup_lease("acme", "ios", cutoff)

      expired = Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")
      assert is_nil(expired.active_cleanup_cutoff_at)
      assert is_nil(expired.cleanup_lease_expires_at)
      assert is_nil(expired.published_cleanup_cutoff_at)
      assert is_nil(expired.published_cleanup_generation)
    end

    test "allows re-acquiring the lease after expiry" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -5, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff
      })

      assert :ok = Cleanup.expire_project_cleanup_lease("acme", "ios", cutoff)
      assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
      assert DateTime.after?(fresh_cutoff, cutoff)
    end
  end

  describe "effective_project_barriers/1" do
    test "returns active barrier when lease is alive" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -5, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff
      })

      barriers =
        Cleanup.effective_project_barriers([
          %{account_handle: "acme", project_handle: "ios"}
        ])

      assert Map.has_key?(barriers, {"acme", "ios"})
      assert barriers[{"acme", "ios"}] == DateTime.truncate(cutoff, :second)
    end

    test "returns published barrier when no active cleanup exists" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -60, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: nil,
        cleanup_lease_expires_at: nil,
        published_cleanup_cutoff_at: cutoff,
        published_cleanup_generation: 1,
        cleanup_event_id: 1,
        cleanup_published_at: now,
        updated_at: now
      })

      barriers =
        Cleanup.effective_project_barriers([
          %{account_handle: "acme", project_handle: "ios"}
        ])

      assert barriers[{"acme", "ios"}] == DateTime.truncate(cutoff, :second)
    end

    test "returns no barrier when active lease has expired and no published cleanup" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -120, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, -60, :second),
        updated_at: cutoff
      })

      barriers =
        Cleanup.effective_project_barriers([
          %{account_handle: "acme", project_handle: "ios"}
        ])

      assert barriers == %{}
    end
  end

  describe "list_published_cleanups_after_event_id/2" do
    test "returns events after the given watermark" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -60, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        active_cleanup_cutoff_at: cutoff,
        cleanup_lease_expires_at: DateTime.add(now, 60, :second),
        updated_at: cutoff
      })

      {:ok, published} = Cleanup.publish_project_cleanup("acme", "ios", cutoff)

      {events, next_watermark} = Cleanup.list_published_cleanups_after_event_id(nil, 100)

      assert length(events) == 1
      assert hd(events).account_handle == "acme"
      assert hd(events).published_cleanup_generation == 1
      assert next_watermark == published.cleanup_event_id

      {events2, _} = Cleanup.list_published_cleanups_after_event_id(next_watermark, 100)
      assert events2 == []
    end
  end

  describe "published_cleanup_barriers_for_projects/1" do
    test "truncates published cleanup barriers to second precision" do
      cutoff = ~U[2026-03-12 12:00:00.900000Z]

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        published_cleanup_cutoff_at: cutoff,
        published_cleanup_generation: 1,
        cleanup_event_id: 1,
        cleanup_published_at: cutoff,
        updated_at: cutoff
      })

      assert Cleanup.published_cleanup_barriers_for_projects([{"acme", "ios"}]) == %{
               {"acme", "ios"} => ~U[2026-03-12 12:00:00Z]
             }
    end
  end

  describe "gc_shared_entries/1" do
    test "deletes rows older than the published cleanup cutoff" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -30, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        published_cleanup_cutoff_at: cutoff,
        published_cleanup_generation: 1,
        cleanup_event_id: 1,
        cleanup_published_at: now,
        updated_at: now
      })

      Repo.insert!(%Entry{
        key: "keyvalue:acme:ios:old",
        account_handle: "acme",
        project_handle: "ios",
        cas_id: "old",
        json_payload: "{}",
        source_node: "node-a",
        source_updated_at: DateTime.add(cutoff, -10, :second),
        last_accessed_at: DateTime.add(cutoff, -10, :second),
        updated_at: DateTime.add(cutoff, -10, :second)
      })

      Repo.insert!(%Entry{
        key: "keyvalue:acme:ios:new",
        account_handle: "acme",
        project_handle: "ios",
        cas_id: "new",
        json_payload: "{}",
        source_node: "node-a",
        source_updated_at: DateTime.add(cutoff, 10, :second),
        last_accessed_at: DateTime.add(cutoff, 10, :second),
        updated_at: DateTime.add(cutoff, 10, :second)
      })

      assert 1 == Cleanup.gc_shared_entries(1000)

      assert is_nil(Repo.get(Entry, "keyvalue:acme:ios:old"))
      assert Repo.get(Entry, "keyvalue:acme:ios:new")
    end

    test "does not delete rows newer than cutoff" do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -30, :second)

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        published_cleanup_cutoff_at: cutoff,
        published_cleanup_generation: 1,
        cleanup_event_id: 1,
        cleanup_published_at: now,
        updated_at: now
      })

      Repo.insert!(%Entry{
        key: "keyvalue:acme:ios:new",
        account_handle: "acme",
        project_handle: "ios",
        cas_id: "new",
        json_payload: "{}",
        source_node: "node-a",
        source_updated_at: DateTime.add(cutoff, 10, :second),
        last_accessed_at: DateTime.add(cutoff, 10, :second),
        updated_at: DateTime.add(cutoff, 10, :second)
      })

      assert 0 == Cleanup.gc_shared_entries(1000)
      assert Repo.get(Entry, "keyvalue:acme:ios:new")
    end

    test "does not delete same-second rows newer than the published cleanup barrier" do
      now = DateTime.utc_now()
      cutoff = ~U[2026-03-12 12:00:00.000000Z]

      Repo.insert!(%Project{
        account_handle: "acme",
        project_handle: "ios",
        published_cleanup_cutoff_at: cutoff,
        published_cleanup_generation: 1,
        cleanup_event_id: 1,
        cleanup_published_at: now,
        updated_at: now
      })

      Repo.insert!(%Entry{
        key: "keyvalue:acme:ios:same-second",
        account_handle: "acme",
        project_handle: "ios",
        cas_id: "same-second",
        json_payload: "{}",
        source_node: "node-a",
        source_updated_at: ~U[2026-03-12 12:00:00.050000Z],
        last_accessed_at: ~U[2026-03-12 12:00:00.050000Z],
        updated_at: ~U[2026-03-12 12:00:00.050000Z]
      })

      assert 0 == Cleanup.gc_shared_entries(1000)
      assert Repo.get(Entry, "keyvalue:acme:ios:same-second")
    end
  end

  describe "local state management" do
    test "discovery watermark round-trips through local state" do
      assert is_nil(Cleanup.get_local_discovery_watermark())

      :ok = Cleanup.put_local_discovery_watermark(42)
      assert 42 == Cleanup.get_local_discovery_watermark()

      :ok = Cleanup.put_local_discovery_watermark(99)
      assert 99 == Cleanup.get_local_discovery_watermark()
    end

    test "applied generation round-trips through local state" do
      assert 0 == Cleanup.local_applied_generation("acme", "ios")

      :ok = Cleanup.put_local_applied_generation("acme", "ios", 3)
      assert 3 == Cleanup.local_applied_generation("acme", "ios")

      :ok = Cleanup.put_local_applied_generation("acme", "ios", 5)
      assert 5 == Cleanup.local_applied_generation("acme", "ios")
    end
  end

  defp ensure_distributed_repo_storage! do
    case Repo.__adapter__().storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "failed to create distributed KV test database: #{inspect(reason)}"
    end
  end
end
