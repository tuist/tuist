# Run with MIX_ENV=test against fresh, explicitly isolated localhost databases.
defmodule BuildEntitiesOnceBenchmark do
  @moduledoc false
  alias Ecto.Adapters.Postgres
  alias Tuist.Accounts.Account
  alias Tuist.BuildEntities
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.CreateBuildEntityTables
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Run
  alias Tuist.Projects.Project
  alias Tuist.Repo

  # Keep actual-query telemetry, dataset construction and recovery checks in execution order.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def run do
    if Mix.env() != :test, do: raise("MIX_ENV=test is required for synchronous, measured observation writes")
    Logger.configure(level: :warning)
    pg_config = Application.fetch_env!(:tuist, Repo)
    ch_config = Application.fetch_env!(:tuist, IngestRepo)
    assert_private_port!(ch_config)
    assert_private_port!(Application.fetch_env!(:tuist, ClickHouseRepo))

    for config <- [pg_config, ch_config] do
      if !(config[:hostname] in ["localhost", "127.0.0.1"] and
             Regex.match?(~r/^build_entities_bench_[a-z0-9_]+$/, config[:database] || "")),
         do: raise("Use explicitly isolated build_entities_bench_* localhost databases")
    end

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    case Postgres.storage_up(pg_config) do
      :ok -> :ok
      {:error, reason} -> raise("Refusing an existing/unavailable PostgreSQL benchmark database: #{inspect(reason)}")
    end

    {:ok, _} = Repo.start_link(Keyword.merge(pg_config, pool: DBConnection.ConnectionPool, pool_size: 8))
    Ecto.Migrator.run(Repo, Application.app_dir(:tuist, "priv/repo/migrations"), :up, all: true, log: false)
    {:ok, _} = IngestRepo.start_link(Keyword.put(ch_config, :database, "default"))
    IngestRepo.query!("CREATE DATABASE #{ch_config[:database]}")
    Supervisor.stop(IngestRepo)

    for repo <- [IngestRepo, ClickHouseRepo] do
      config = Application.fetch_env!(:tuist, repo)
      assert_private_port!(config)
      if config[:hostname] not in ["localhost", "127.0.0.1"], do: raise("Benchmark queries/writes are localhost-only")
      {:ok, _} = repo.start_link(Keyword.merge(config, pool: DBConnection.ConnectionPool, pool_size: 8))
    end

    Code.require_file("../ingest_repo/migrations/20261009130000_create_build_entity_tables.exs", __DIR__)
    CreateBuildEntityTables.up()
    account = Repo.insert!(%Account{name: "bench-once", billing_email: "bench@example.invalid"})
    project = Repo.insert!(%Project{name: "bench-once", account_id: account.id, token: "synthetic", build_system: :once})
    runs = integer("BUILD_ENTITY_ONCE_RUNS", 10_000)
    actions = integer("BUILD_ENTITY_ONCE_ACTIONS", 500)
    recent = integer("BUILD_ENTITY_ONCE_RECENT", 200)
    hot = integer("BUILD_ENTITY_ONCE_HOT", 5_000)
    if recent > runs, do: raise("Recent run count exceeds total")

    {seed_us, _} =
      :timer.tc(fn ->
        Repo.query!(
          """
          INSERT INTO once_runs (id, run_id, project_id, started_at, finalized_at, finalization,
                                command_display, inserted_at, updated_at)
          SELECT md5('run-' || i)::uuid, 'run-' || i, $1, now() - interval '4 days',
                 CASE WHEN i <= $3 THEN now() - interval '15 minutes' ELSE now() - interval '3 days' END,
                 CASE WHEN i % 2 = 0 THEN 'lost' ELSE 'finalized' END, 'once build //bench:app', now(), now()
          FROM generate_series(0, $2) i
          """,
          [project.id, runs, recent]
        )

        Repo.query!(
          """
          INSERT INTO once_actions (id, once_run_id, run_id, project_id, target_execution_id,
                                    capability, action_index, identifier, display_name, result,
                                    duration_ms, started_at, finished_at, inserted_at, updated_at)
          SELECT md5('action-' || r.run_id || '-' || j)::uuid, r.id, r.run_id, r.project_id, 'exec-' || j,
                 'compile', 0, 'action-' || j, 'compile bench', 'succeeded', 1200,
                 now() - interval '30 minutes', now() - interval '29 minutes', now(), now()
          FROM once_runs r CROSS JOIN LATERAL generate_series(1, CASE WHEN r.run_id = 'run-0' THEN $1::integer ELSE $2::integer END) j
          """,
          [hot, actions],
          timeout: 300_000
        )

        Repo.query!("""
        INSERT INTO once_target_instances (id, once_run_id, target_instance_id, target_id, inserted_at)
        SELECT md5('instance-' || a.id)::uuid, a.once_run_id, 'instance-' || a.target_execution_id,
               '//bench:' || a.target_execution_id, now()
        FROM once_actions a JOIN once_runs r ON r.id = a.once_run_id WHERE r.finalized_at >= now() - interval '2 hours'
        """)

        Repo.query!("""
        INSERT INTO once_target_executions (id, once_run_id, target_execution_id, target_instance_id, inserted_at)
        SELECT md5('execution-' || a.id)::uuid, a.once_run_id, a.target_execution_id,
               'instance-' || a.target_execution_id, now()
        FROM once_actions a JOIN once_runs r ON r.id = a.once_run_id WHERE r.finalized_at >= now() - interval '2 hours'
        """)

        for table <- ~w(once_runs once_actions once_target_instances once_target_executions),
            do: Repo.query!("ANALYZE #{table}")
      end)

    run = Repo.get_by!(Run, run_id: "run-0")

    :telemetry.attach(
      "once-benchmark",
      [:tuist, :repo, :query],
      fn _, measurements, metadata, _ ->
        Process.put(:benchmark_sql, {metadata.query, metadata.params})
        Process.put(:benchmark_queries, Process.get(:benchmark_queries, 0) + 1)

        Process.put(
          :benchmark_sql_us,
          Process.get(:benchmark_sql_us, 0) + System.convert_time_unit(measurements.total_time, :native, :microsecond)
        )
      end,
      nil
    )

    slots = OnceEvents.list_action_slots(run)
    if !(length(slots) == hot and Enum.all?(slots, &is_binary(&1.target_id))), do: raise("Mapping fixture mismatch")
    {sql, params} = Process.get(:benchmark_sql)
    %{rows: [[slot_plan]]} = Repo.query!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " <> sql, params)
    parent_ids = for i <- 1..100, do: "run-#{i}"
    contexts = BuildEntities.parent_contexts(project.id, :once, "action", parent_ids)
    if map_size(contexts) != 100, do: raise("Parent fixture mismatch")
    {parent_sql, parent_params} = Process.get(:benchmark_sql)
    %{rows: [[parent_plan]]} = Repo.query!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " <> parent_sql, parent_params)
    {recovery_sql, recovery_params} = capture_recovery_sql()
    %{rows: [[recovery_plan]]} = Repo.query!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " <> recovery_sql, recovery_params)
    iterations = integer("BUILD_ENTITY_ONCE_ITERATIONS", 20)

    measurements =
      for {name, fun} <- [
            {"mapped-slots", fn -> OnceEvents.list_action_slots(run) end},
            {"parent-contexts", fn -> BuildEntities.parent_contexts(project.id, :once, "action", parent_ids) end}
          ] do
        serial = for _ <- 1..iterations, do: timed(fun)

        concurrent =
          1..(iterations * 4)
          |> Task.async_stream(fn _ -> timed(fun) end, max_concurrency: 4, timeout: 60_000)
          |> Enum.map(fn {:ok, value} -> value end)

        %{operation: name, serial: stats(serial), concurrent: stats(concurrent)}
      end

    Process.put(:benchmark_queries, 0)
    Process.put(:benchmark_sql_us, 0)
    {sweep_us, {:ok, recovered}} = :timer.tc(fn -> OnceEvents.publish_recent_build_entities() end)
    if recovered != recent + 1, do: raise("Recovery keyset fixture mismatch")
    expected = recent * actions + hot

    %{rows: [[^expected]]} =
      ClickHouseRepo.query!(
        "SELECT count() FROM build_entity_observations FINAL SETTINGS do_not_merge_across_partitions_select_final=0"
      )

    result = %{
      database: pg_config[:database],
      runs: runs + 1,
      actions: runs * actions + hot,
      mappings: expected,
      seed_ms: seed_us / 1000,
      measurements: measurements,
      slot_plan: slot_plan,
      parent_plan: parent_plan,
      recovery_plan: recovery_plan,
      clickhouse_port: IngestRepo.config()[:port],
      sweep_ms: sweep_us / 1000,
      recovered_runs: recovered,
      sweep_postgres_queries: Process.get(:benchmark_queries),
      sweep_sql_ms: Process.get(:benchmark_sql_us) / 1000
    }

    output = System.get_env("BUILD_ENTITY_ONCE_OUTPUT", "/tmp/build-entities-once-volume.json")
    File.write!(output, JSON.encode!(result))
    IO.puts(JSON.encode!(Map.drop(result, [:slot_plan, :parent_plan, :recovery_plan])))

    if sweep_us > 60_000_000 or Enum.any?(measurements, &(&1.concurrent.p95_ms > 1000)),
      do: raise("Once volume latency gate failed")

    IO.puts("Results: #{output}; isolated databases retained")
  end

  # Capture the actual first-page query without inventing a copy of its predicates.
  defp capture_recovery_sql do
    :telemetry.attach(
      "once-benchmark-recovery",
      [:tuist, :repo, :query],
      fn _, _, metadata, _ ->
        if is_nil(Process.get(:benchmark_recovery_sql)) and String.contains?(metadata.query, "ORDER BY") and
             String.contains?(metadata.query, "finalized_at") do
          Process.put(:benchmark_recovery_sql, {metadata.query, metadata.params})
        end
      end,
      nil
    )

    # The first sweep warms the measured repeat and proves duplicate-insensitive recovery.
    {:ok, _} = OnceEvents.publish_recent_build_entities()
    :telemetry.detach("once-benchmark-recovery")
    Process.get(:benchmark_recovery_sql) || raise("Recovery query telemetry missing")
  end

  defp assert_private_port!(config) do
    expected = System.fetch_env!("BUILD_ENTITY_BENCH_EXPECTED_PORT")
    if expected == "8123", do: raise("Do not benchmark the shared ClickHouse port")

    if to_string(config[:port]) != expected,
      do: raise("Benchmark port mismatch: expected #{expected}, got #{config[:port]}")
  end

  defp integer(name, default), do: name |> System.get_env(Integer.to_string(default)) |> String.to_integer()
  defp timed(fun), do: elem(:timer.tc(fun), 0) / 1000

  defp stats(samples) do
    sorted = Enum.sort(samples)

    %{
      samples: length(sorted),
      p50_ms: Enum.at(sorted, ceil(length(sorted) * 0.5) - 1),
      p95_ms: Enum.at(sorted, ceil(length(sorted) * 0.95) - 1),
      max_ms: List.last(sorted)
    }
  end
end

BuildEntitiesOnceBenchmark.run()
