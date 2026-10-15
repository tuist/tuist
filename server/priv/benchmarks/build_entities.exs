defmodule BuildEntitiesBenchmark.SeedEntity do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "bench_entities" do
    field :system, :string
    field :kind, :string
    field :ordinal, Ch, type: "UInt64"
    field :entity_id, Ecto.UUID
    field :identity, :string
  end
end

defmodule BuildEntitiesBenchmark do
  @moduledoc false
  alias BuildEntitiesBenchmark.SeedEntity
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Identity
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.CreateBuildEntityTables

  @project 1
  @resources [
    {:gradle, "task"},
    {:xcode, "module"},
    {:xcode, "cache_action"},
    {:bazel, "cache_action"},
    {:once, "action"},
    {:mix, "file"},
    {:mix, "module"}
  ]

  # Keep the table-driven workload and its sequential fixture/gate checks together.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def run do
    Logger.configure(level: :warning)
    database = System.fetch_env!("BUILD_ENTITY_BENCH_DATABASE")

    if !Regex.match?(~r/^build_entities_bench_[a-z0-9_]+$/, database),
      do: raise("Use an isolated build_entities_bench_* database")

    config = Application.fetch_env!(:tuist, IngestRepo)
    assert_private_port!(config)
    assert_private_port!(Application.fetch_env!(:tuist, ClickHouseRepo))
    if config[:hostname] not in ["localhost", "127.0.0.1"], do: raise("Benchmark writes are localhost-only")
    run_id = "build-entities-bench-#{System.system_time(:microsecond)}"
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = IngestRepo.start_link(Keyword.put(config, :database, "default"))
    reuse? = System.get_env("BUILD_ENTITY_BENCH_REUSE") == "1"
    # A new run never appends to or destroys an existing dataset.
    if !reuse?, do: IngestRepo.query!("CREATE DATABASE #{database}")
    Supervisor.stop(IngestRepo)
    settings = [log_queries: 1, log_comment: run_id]

    for repo <- [IngestRepo, ClickHouseRepo] do
      cfg = Application.fetch_env!(:tuist, repo)
      assert_private_port!(cfg)
      if cfg[:hostname] not in ["localhost", "127.0.0.1"], do: raise("Benchmark queries/writes are localhost-only")
      {:ok, _} = repo.start_link(Keyword.merge(cfg, database: database, pool_size: 8, settings: settings))
    end

    if !reuse? do
      Code.require_file("../ingest_repo/migrations/20261009130000_create_build_entity_tables.exs", __DIR__)
      CreateBuildEntityTables.up()

      IngestRepo.query!(
        "CREATE TABLE bench_entities (system String, kind String, ordinal UInt64, entity_id UUID, identity String) ENGINE = Memory"
      )
    end

    entities = env_integer("BUILD_ENTITY_BENCH_ENTITIES", 10_000)
    repeats = env_integer("BUILD_ENTITY_BENCH_OBSERVATIONS", 100)
    hot = env_integer("BUILD_ENTITY_BENCH_HOT", 100_000)
    iterations = env_integer("BUILD_ENTITY_BENCH_ITERATIONS", 20)
    concurrency = env_integer("BUILD_ENTITY_BENCH_CONCURRENCY", 4)

    selected = System.get_env("BUILD_ENTITY_BENCH_KINDS")

    resources =
      Enum.filter(@resources, fn {system, kind} ->
        is_nil(selected) or "#{system}/#{kind}" in String.split(selected, ",")
      end)

    if resources == [], do: raise("Select at least one supported kind")

    if Enum.any?([entities, repeats, hot, iterations, concurrency], &(&1 < 1)),
      do: raise("Use positive workload parameters")

    all =
      for {system, kind} <- resources do
        identities = for i <- 0..(entities - 1), do: identity(system, kind, i)
        ids = Enum.map(identities, &Identity.id(@project, system, kind, &1))
        encoded = Enum.map(identities, &Identity.encode(system, kind, &1))

        if !reuse? do
          IngestRepo.insert_all(
            SeedEntity,
            for {{id, value}, i} <- Enum.with_index(Enum.zip(ids, encoded)) do
              %{system: Atom.to_string(system), kind: kind, ordinal: i, entity_id: id, identity: value}
            end
          )

          seed(system, kind, entities * repeats, 0, entities)
          seed(system, kind, hot, entities * repeats, 1)
          # Ten percent of the hot cohort is retried, then corrected with NULL timing.
          seed(system, kind, div(hot, 10), entities * repeats, 1, true)
        end

        {system, kind, hd(ids)}
      end

    for {system, kind, _id} <- all do
      {:ok, %{rows: [[entity_count, observation_count]]}} =
        ClickHouseRepo.query(
          """
          SELECT uniqExact(entity_id), count() FROM build_entity_observations FINAL
          WHERE system = {system:String} AND kind = {kind:String}
          SETTINGS do_not_merge_across_partitions_select_final=0, optimize_move_to_prewhere_if_final=0
          """,
          %{system: Atom.to_string(system), kind: kind},
          settings: [max_memory_usage: 536_870_912, max_threads: 2]
        )

      if !(entity_count == entities and observation_count == entities * repeats + hot),
        do:
          raise(
            "Fixture cardinality mismatch: #{system}/#{kind} #{entity_count} entities, #{observation_count} observations"
          )
    end

    now = DateTime.utc_now()
    opts = [start_datetime: DateTime.add(now, -30, :day), end_datetime: DateTime.add(now, 1, :hour)]
    output = System.get_env("BUILD_ENTITY_BENCH_OUTPUT", "/tmp/build-entities-volume.json")
    File.write!(output <> ".jsonl", "")

    measurements =
      Enum.flat_map(all, fn {system, kind, id} ->
        {_, cursor} = BuildEntities.history(@project, system, kind, id, opts)

        {_, retained} =
          BuildEntities.history(
            @project,
            system,
            kind,
            id,
            Keyword.put(opts, :start_datetime, DateTime.add(now, -89, :day))
          )

        if retained.total_count != repeats + hot, do: raise("Hot entity fixture count mismatch")

        jobs = [
          {"inventory", fn -> BuildEntities.list(@project, system, kind, opts) end},
          {"inventory-filtered",
           fn -> BuildEntities.list(@project, system, kind, opts ++ [environment: "ci", branch: "main"]) end},
          {"inventory-filtered-search",
           fn ->
             BuildEntities.list(@project, system, kind, opts ++ [environment: "ci", branch: "main", search: "999"])
           end},
          {"inventory-filtered-recent",
           fn ->
             BuildEntities.list(
               @project,
               system,
               kind,
               Keyword.put(opts, :start_datetime, DateTime.add(now, -1, :day)) ++ [environment: "ci", branch: "main"]
             )
           end},
          {"inventory-filtered-full-retention",
           fn ->
             BuildEntities.list(
               @project,
               system,
               kind,
               Keyword.put(opts, :start_datetime, DateTime.add(now, -89, :day)) ++ [environment: "ci", branch: "main"]
             )
           end},
          {"inventory-search-name",
           fn -> BuildEntities.list(@project, system, kind, opts ++ [search: "999", sort_by: "name"]) end},
          {"inventory-deep-page", fn -> BuildEntities.list(@project, system, kind, opts ++ [page: 100]) end},
          {"detail", fn -> BuildEntities.get(@project, system, kind, id) end},
          {"history", fn -> BuildEntities.history(@project, system, kind, id, opts) end},
          {"history-cursor", fn -> BuildEntities.history(@project, system, kind, id, opts ++ [after: cursor.after]) end},
          {"history-filtered",
           fn ->
             BuildEntities.history(
               @project,
               system,
               kind,
               id,
               opts ++
                 [
                   environment: "ci",
                   branch: "main",
                   search: "bench-run",
                   filters: [%{field: "cache_status", op: "is", value: "miss"}]
                 ]
             )
           end},
          {"history-duration-page",
           fn ->
             BuildEntities.history(
               @project,
               system,
               kind,
               id,
               opts ++ [sort_by: "duration_ms", sort_order: "desc", page: 100]
             )
           end},
          {"analytics", fn -> BuildEntities.analytics(@project, system, kind, id, opts) end},
          {"analytics-filtered",
           fn -> BuildEntities.analytics(@project, system, kind, id, opts ++ [environment: "ci", branch: "main"]) end},
          {"scatter", fn -> BuildEntities.duration_scatter(@project, system, kind, id, opts) end},
          {"overview-fanout",
           fn ->
             {:ok, _} = BuildEntities.get(@project, system, kind, id)

             [
               fn -> BuildEntities.history(@project, system, kind, id, opts) end,
               fn -> BuildEntities.analytics(@project, system, kind, id, opts) end
             ]
             |> Task.async_stream(fn fun -> fun.() end, max_concurrency: 2, timeout: 120_000)
             |> Enum.each(fn {:ok, _} -> :ok end)
           end}
        ]

        operations = System.get_env("BUILD_ENTITY_BENCH_OPERATIONS")

        for {name, fun} <- jobs, is_nil(operations) or name in String.split(operations, ",") do
          fun.()
          serial = for _ <- 1..iterations, do: timed(fun)

          concurrent =
            1..(iterations * concurrency)
            |> Task.async_stream(fn _ -> timed(fun) end, max_concurrency: concurrency, timeout: 120_000)
            |> Enum.map(fn {:ok, ms} -> ms end)

          row = %{system: system, kind: kind, operation: name, serial: stats(serial), concurrent: stats(concurrent)}
          IO.puts(JSON.encode!(row))
          File.write!(output <> ".jsonl", JSON.encode!(row) <> "\n", [:append])
          row
        end
      end)

    native_parents =
      if System.get_env("BUILD_ENTITY_BENCH_NATIVE_PARENTS") == "1" do
        Code.require_file("build_entity_native_parents.exs", __DIR__)

        BuildEntityNativeParentsBenchmark.run(
          run_id: run_id,
          seed: !reuse?,
          rows: env_integer("BUILD_ENTITY_BENCH_NATIVE_ROWS", 1_000_000),
          iterations: iterations,
          concurrency: concurrency,
          reference: System.get_env("BUILD_ENTITY_BENCH_SCHEMA_REFERENCE"),
          output: output <> ".native-parents.json"
        )
      end

    # Allow the server's normal query-log flush; never flush or reset shared caches.
    Process.sleep(10_000)

    {:ok, %{rows: query_stats}} =
      ClickHouseRepo.query(
        """
        SELECT query_duration_ms, read_rows, read_bytes, memory_usage, query
        FROM system.query_log
        WHERE log_comment = {comment:String} AND type = 'QueryFinish' AND query_kind = 'Select'
          AND position(query, 'build_entity') > 0
        ORDER BY event_time_microseconds
        """,
        %{comment: run_id},
        settings: [max_result_rows: 100_000]
      )

    %{rows: [[version]]} = ClickHouseRepo.query!("SELECT version()")

    result = %{
      clickhouse_version: version,
      clickhouse_port: IngestRepo.config()[:port],
      database: database,
      run_id: run_id,
      entities_per_kind: entities,
      observations_per_entity: repeats,
      hot_observations_per_kind: hot,
      replay_percent: 10,
      concurrency: concurrency,
      native_parents: native_parents,
      measurements: measurements,
      query_statistics:
        Enum.map(query_stats, fn [ms, rows, bytes, memory, sql] ->
          %{ms: ms, read_rows: rows, read_bytes: bytes, memory_bytes: memory, sql: sql}
        end)
    }

    File.write!(output, JSON.encode!(result))
    budget = env_integer("BUILD_ENTITY_BENCH_P95_MS", 2000)
    failures = Enum.filter(measurements, &(&1.serial.p95_ms > budget or &1.concurrent.p95_ms > budget))
    if failures != [], do: raise("Latency gate failed: #{JSON.encode!(failures)}")
    if query_stats == [], do: raise("No query statistics captured; enable query_log on the benchmark server")
    IO.puts("Results: #{output}; isolated dataset retained in #{database}")
  end

  defp timed(fun) do
    {microseconds, _} = :timer.tc(fun)
    microseconds / 1_000
  end

  defp stats(samples) do
    sorted = Enum.sort(samples)

    %{
      min_ms: hd(sorted),
      p50_ms: percentile(sorted, 0.5),
      p95_ms: percentile(sorted, 0.95),
      p99_ms: percentile(sorted, 0.99),
      max_ms: List.last(sorted),
      samples: length(sorted)
    }
  end

  defp percentile(sorted, q), do: Enum.at(sorted, max(ceil(length(sorted) * q) - 1, 0))

  defp assert_private_port!(config) do
    expected = System.fetch_env!("BUILD_ENTITY_BENCH_EXPECTED_PORT")
    if expected == "8123", do: raise("Do not benchmark the shared ClickHouse port")

    if to_string(config[:port]) != expected,
      do: raise("Benchmark port mismatch: expected #{expected}, got #{config[:port]}")
  end

  defp env_integer(name, default), do: name |> System.get_env(Integer.to_string(default)) |> String.to_integer()

  defp seed(system, kind, rows, offset, entities, correction \\ false) do
    sql = """
    INSERT INTO build_entity_observations
    WITH toDateTime64({stamp:String}, 6, 'UTC') AS stamp,
      if({system:String} = 'xcode' AND {kind:String} = 'module', 29, 85) * 86400 AS span,
      stamp - toIntervalSecond(intDiv(modulo(number + {offset:UInt64}, 1000) * span, 1000)) AS observed
    SELECT 1, {system:String}, {kind:String},
      dictionary.entity_id,
      observed,
      reinterpretAsUUID(MD5(concat({system:String}, {kind:String}, toString(number + {offset:UInt64})))),
      concat('Entity ', toString(modulo(number + {offset:UInt64}, {entities:UInt64}))),
      dictionary.identity,
      concat('bench-run-', toString(modulo(number, 1000))), toString(number),
      if({system:String} = 'xcode' OR {system:String} = 'bazel', 'unknown', if(modulo(number, 20) = 0, 'failure', 'success')),
      multiIf(modulo(number, 3) = 0, 'miss', modulo(number, 3) = 1, 'hit_remote', 'none'),
      if({correction:Bool} OR modulo(number, 5) = 0 OR ({system:String} = 'xcode' AND {kind:String} = 'module'), NULL, modulo(number, 5000)),
      if(modulo(number, 3) = 0, 'main', 'feature/bench'), '0123456789abcdef',
      if(modulo(number, 10) = 0, NULL, modulo(number, 2) = 0), if({correction:Bool}, stamp, observed)
    FROM numbers({rows:UInt64}) AS source_rows
    INNER JOIN (
      SELECT ordinal, entity_id, identity FROM bench_entities
      WHERE system = {system:String} AND kind = {kind:String} AND ordinal < {entities:UInt64}
    ) AS dictionary ON dictionary.ordinal = modulo(number + {offset:UInt64}, {entities:UInt64})
    SETTINGS max_threads=2, max_insert_threads=2, max_memory_usage=536870912, max_block_size=100000
    """

    stamp = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

    {elapsed, _} =
      :timer.tc(fn ->
        for start <- 0 |> Stream.iterate(&(&1 + 10_000)) |> Stream.take_while(&(&1 < rows)) do
          IngestRepo.query!(
            sql,
            %{
              system: Atom.to_string(system),
              kind: kind,
              stamp: stamp,
              entities: entities,
              rows: min(10_000, rows - start),
              offset: offset + start,
              correction: correction
            },
            timeout: 180_000
          )
        end
      end)

    IO.puts("Seed #{system}/#{kind}: #{rows} rows in #{Float.round(elapsed / 1_000_000, 2)}s")
  end

  defp identity(:gradle, "task", i),
    do: %{"root_project_name" => "bench", "build_path" => ":", "task_path" => ":app:task#{i}", "task_type" => "Compile"}

  defp identity(:xcode, "module", i), do: %{"project" => "bench", "target" => "Module#{i}"}
  defp identity(:xcode, "cache_action", i), do: %{"type" => "swift", "key" => "key-#{i}"}

  defp identity(:bazel, "cache_action", i),
    do: %{"action_digest_hash" => "digest-#{i}", "action_mnemonic" => "Compile", "target_label" => "//app:target#{i}"}

  defp identity(:once, "action", i),
    do: %{"target_id" => "//app:target#{i}", "capability" => "build", "action_index" => "0"}

  defp identity(:mix, "file", i), do: %{"path" => "lib/file_#{i}.ex"}
  defp identity(:mix, "module", i), do: %{"module" => "Module#{i}"}
end

BuildEntitiesBenchmark.run()
