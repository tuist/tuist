defmodule BuildEntityNativeParentsBenchmark do
  @moduledoc """
  Volume proof for `Tuist.BuildEntities.parent_contexts/4` against the five
  ClickHouse parent families: Gradle builds, Mix builds, Xcode builds
  (`build_runs`), Xcode generate/cache commands (`command_events`) and Bazel
  invocations. Once runs live in Postgres and are not covered here.

  Requiring this file defines the module and runs nothing. Two entry points:

    * `run/1` assumes `Tuist.IngestRepo` and `Tuist.ClickHouseRepo` are
      already started on an isolated, localhost `build_entities_bench_*`
      database, which is what `build_entities.exs` does. Pass its `run_id`
      (the `log_comment` the repos were started with) so server statistics
      can be read back from `system.query_log`.
    * `standalone/0` does that setup itself from the same environment
      variables as `build_entities.exs`, against a scratch ClickHouse such as
      the one `run_build_entities.sh` starts:

          MIX_ENV=dev mix do deps.loadpaths --no-deps-check + run --no-start -e \\
            'Code.require_file("priv/benchmarks/build_entity_native_parents.exs"); BuildEntityNativeParentsBenchmark.standalone()'

  The tables carry only the columns the lookup and its fixtures touch, with
  the production types, engine family, partition key, sort key, TTL,
  projections and the skip indexes on those columns (as of migration
  `20261014120100`). `verify_schema/1` compares them with a migrated
  reference database. Replicated and Shared engines are replaced by their
  plain equivalents.

  Each project gets `rows` parents per family (default 1,000,000) spread over
  85 days of `inserted_at`, the newest first. Parent IDs are versioned UUIDs
  derived from MD5 of `family:project:index`, computed identically here and in
  SQL. Every tenth parent then gets a newer version that blanks or NULLs the
  fields `parent_contexts/4` reports, so a stale version winning shows up as
  a correctness failure, not just a timing. Actors are always absent, so no
  Postgres lookup is involved.

  Every call asks for 100 parent IDs:

    * `recent-page`: the 100 newest parents, the common history page.
    * `middle-page`: 100 consecutive parents from the middle of the range.
    * `scattered`: one parent per percentile of the whole range, so every
      partition and many granules are touched.
    * `other-project`: 100 parents of another project, which must not match.
  """
  alias Tuist.BuildEntities
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo

  @project 1
  @lookups 100
  @span_seconds 85 * 86_400
  @chunk 100_000
  @seed_settings "SETTINGS max_threads = 2, max_insert_threads = 2, max_memory_usage = 1073741824, max_block_size = 100000"

  # `columns` and `version` mirror `latest_parent_rows/6` in
  # `Tuist.BuildEntities`; the logged query is checked against them.
  @families [
    %{
      family: "gradle",
      system: :gradle,
      kind: "task",
      table: "gradle_builds",
      key: "id",
      key_type: "UUID",
      columns: "account_id, root_project_name, custom_tags",
      version: "inserted_at",
      ddl: """
      CREATE TABLE gradle_builds (
        `id` UUID,
        `project_id` Int64,
        `account_id` Int64,
        `duration_ms` UInt64,
        `is_ci` Bool DEFAULT 0,
        `status` Enum8('success' = 0, 'failure' = 1, 'cancelled' = 2),
        `git_branch` String DEFAULT '',
        `root_project_name` String DEFAULT '',
        `inserted_at` DateTime DEFAULT now(),
        `custom_tags` Array(String) DEFAULT [],
        INDEX idx_id id TYPE bloom_filter GRANULARITY 1
      )
      ENGINE = MergeTree
      PARTITION BY toYYYYMM(inserted_at)
      ORDER BY (project_id, inserted_at)
      TTL inserted_at + toIntervalDay(90)
      """,
      seed: [
        id: "toUUID(parent)",
        project_id: "project",
        account_id: "0",
        duration_ms: "1000 + n % 60000",
        is_ci: "n % 2 = 0",
        status: "'success'",
        git_branch: "'main'",
        root_project_name: "if(correction, '', concat('app-', toString(n % 50)))",
        inserted_at: "toDateTime(version_s, 'UTC')",
        custom_tags: "if(correction, CAST([], 'Array(String)'), ['bench'])"
      ]
    },
    %{
      family: "mix",
      system: :mix,
      kind: "module",
      table: "mix_builds",
      key: "id",
      key_type: "UUID",
      columns: "account_id",
      version: "inserted_at",
      ddl: """
      CREATE TABLE mix_builds (
        `id` UUID,
        `project_id` Int64,
        `account_id` Int64,
        `duration_ms` UInt64 DEFAULT 0,
        `status` Enum8('success' = 0, 'failure' = 1),
        `is_ci` Bool DEFAULT 0,
        `inserted_at` DateTime DEFAULT now(),
        INDEX idx_id id TYPE bloom_filter GRANULARITY 1
      )
      ENGINE = MergeTree
      PARTITION BY toYYYYMM(inserted_at)
      ORDER BY (project_id, inserted_at, id)
      TTL inserted_at + toIntervalDay(90)
      """,
      seed: [
        id: "toUUID(parent)",
        project_id: "project",
        account_id: "0",
        duration_ms: "1000 + n % 60000",
        status: "'success'",
        is_ci: "n % 2 = 0",
        inserted_at: "toDateTime(version_s, 'UTC')"
      ]
    },
    %{
      family: "xcode-build",
      system: :xcode,
      kind: "cache_action",
      table: "build_runs",
      key: "id",
      key_type: "UUID",
      columns: "account_id, scheme",
      version: "updated_at",
      ddl: """
      CREATE TABLE build_runs (
        `id` UUID,
        `duration` Int32,
        `project_id` Int64,
        `account_id` Int64,
        `is_ci` Bool DEFAULT false,
        `scheme` String DEFAULT '',
        `status` LowCardinality(String) DEFAULT '',
        `inserted_at` DateTime64(6),
        `updated_at` DateTime64(6) DEFAULT inserted_at,
        PROJECTION proj_by_id (SELECT * ORDER BY id),
        PROJECTION proj_artifact_retention_by_project_inserted_at (
          SELECT id, project_id, inserted_at ORDER BY project_id, inserted_at
        )
      )
      ENGINE = ReplacingMergeTree(updated_at)
      PARTITION BY toYYYYMM(inserted_at)
      ORDER BY (project_id, id)
      SETTINGS deduplicate_merge_projection_mode = 'rebuild'
      """,
      seed: [
        id: "toUUID(parent)",
        duration: "toInt32(1000 + n % 60000)",
        project_id: "project",
        account_id: "0",
        is_ci: "n % 2 = 0",
        scheme: "if(correction, '', 'App')",
        status: "'success'",
        inserted_at: "toDateTime64(at_s, 6, 'UTC')",
        updated_at: "toDateTime64(version_s, 6, 'UTC')"
      ]
    },
    %{
      family: "xcode-command",
      system: :xcode,
      kind: "module",
      table: "command_events",
      key: "id",
      key_type: "UUID",
      columns: "user_id, name, command_arguments",
      version: "updated_at",
      ddl: """
      CREATE TABLE command_events (
        `id` UUID,
        `legacy_id` UInt64,
        `name` String,
        `command_arguments` Nullable(String),
        `duration` Int32,
        `project_id` Int64,
        `created_at` DateTime64(6),
        `updated_at` DateTime64(6),
        `is_ci` Bool DEFAULT false,
        `user_id` Nullable(Int32),
        `ran_at` DateTime64(6),
        INDEX idx_name name TYPE bloom_filter GRANULARITY 4,
        INDEX idx_id id TYPE bloom_filter GRANULARITY 4,
        INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 128,
        INDEX idx_user_id user_id TYPE minmax GRANULARITY 32,
        PROJECTION proj_by_id (SELECT * ORDER BY id)
      )
      ENGINE = MergeTree
      PARTITION BY toYYYYMM(ran_at)
      ORDER BY (project_id, name, ran_at)
      """,
      seed: [
        id: "toUUID(parent)",
        legacy_id: "0",
        name: "command_name",
        command_arguments: "if(correction, NULL, concat('tuist ', command_name, ' App'))",
        duration: "toInt32(1000 + n % 60000)",
        project_id: "project",
        created_at: "toDateTime64(at_s, 6, 'UTC')",
        updated_at: "toDateTime64(version_s, 6, 'UTC')",
        is_ci: "n % 2 = 0",
        user_id: "CAST(NULL, 'Nullable(Int32)')",
        ran_at: "toDateTime64(at_s, 6, 'UTC')"
      ]
    },
    %{
      family: "bazel",
      system: :bazel,
      kind: "cache_action",
      table: "bazel_invocations",
      key: "invocation_id",
      key_type: "String",
      columns: "command, target_patterns",
      version: "inserted_at",
      ddl: """
      CREATE TABLE bazel_invocations (
        `id` UUID,
        `invocation_id` String,
        `command` LowCardinality(String),
        `status` Enum8('success' = 0, 'failure' = 1),
        `exit_code` Int32,
        `started_at` DateTime,
        `finished_at` DateTime,
        `duration_ms` UInt64,
        `project_id` Int64,
        `account_handle` String,
        `project_handle` String,
        `cache_endpoint` LowCardinality(String),
        `inserted_at` DateTime DEFAULT now(),
        `target_patterns` Array(String) DEFAULT [],
        `is_ci` Bool DEFAULT 0
      )
      ENGINE = ReplacingMergeTree(inserted_at)
      PARTITION BY toYYYYMM(inserted_at)
      ORDER BY (project_id, invocation_id)
      TTL inserted_at + toIntervalDay(90)
      """,
      seed: [
        id: "toUUID(parent)",
        invocation_id: "parent",
        command: "'build'",
        status: "'success'",
        exit_code: "0",
        started_at: "toDateTime(at_s, 'UTC')",
        finished_at: "toDateTime(at_s, 'UTC')",
        duration_ms: "1000 + n % 60000",
        project_id: "project",
        account_handle: "'bench'",
        project_handle: "'bench'",
        cache_endpoint: "''",
        inserted_at: "toDateTime(version_s, 'UTC')",
        target_patterns: "if(correction, CAST([], 'Array(String)'), ['//app:all'])",
        is_ci: "n % 2 = 0"
      ]
    }
  ]

  def families, do: @families

  def standalone do
    Logger.configure(level: :warning)
    database = System.fetch_env!("BUILD_ENTITY_BENCH_DATABASE")

    if !Regex.match?(~r/^build_entities_bench_[a-z0-9_]+$/, database),
      do: raise("Use an isolated build_entities_bench_* database")

    config = Application.fetch_env!(:tuist, IngestRepo)
    assert_private_port!(config)
    assert_private_port!(Application.fetch_env!(:tuist, ClickHouseRepo))
    if config[:hostname] not in ["localhost", "127.0.0.1"], do: raise("Benchmark writes are localhost-only")
    run_id = "build-entity-native-parents-#{System.system_time(:microsecond)}"
    reuse? = System.get_env("BUILD_ENTITY_BENCH_REUSE") == "1"
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = IngestRepo.start_link(Keyword.put(config, :database, "default"))
    # A new run never appends to or destroys an existing dataset.
    if !reuse?, do: IngestRepo.query!("CREATE DATABASE #{database}")
    Supervisor.stop(IngestRepo)

    for repo <- [IngestRepo, ClickHouseRepo] do
      cfg = Application.fetch_env!(:tuist, repo)
      assert_private_port!(cfg)

      {:ok, _} =
        repo.start_link(
          Keyword.merge(cfg, database: database, pool_size: 8, settings: [log_queries: 1, log_comment: run_id])
        )
    end

    run(
      run_id: run_id,
      seed: !reuse?,
      reference: System.get_env("BUILD_ENTITY_BENCH_SCHEMA_REFERENCE"),
      rows: env_integer("BUILD_ENTITY_BENCH_NATIVE_ROWS", 1_000_000),
      projects: env_integer("BUILD_ENTITY_BENCH_NATIVE_PROJECTS", 2),
      iterations: env_integer("BUILD_ENTITY_BENCH_ITERATIONS", 20),
      concurrency: env_integer("BUILD_ENTITY_BENCH_CONCURRENCY", 4),
      budget_ms: env_integer("BUILD_ENTITY_BENCH_P95_MS", 2000),
      output: System.get_env("BUILD_ENTITY_BENCH_NATIVE_OUTPUT", "/tmp/build-entity-native-parents.json")
    )
  end

  @doc """
  Options: `:run_id` (required, the repos' `log_comment`), `:seed` (default
  `true`), `:reference` (a migrated database to verify the schema against),
  `:rows` per project and family, `:projects` (at least 2), `:iterations`,
  `:concurrency`, `:budget_ms` (p95 gate) and `:output`.
  """
  # Keep fixture verification, timed scenarios and server-profile gates adjacent.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def run(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    rows = Keyword.get(opts, :rows, 1_000_000)
    projects = Keyword.get(opts, :projects, 2)
    iterations = Keyword.get(opts, :iterations, 20)
    concurrency = Keyword.get(opts, :concurrency, 4)
    budget = Keyword.get(opts, :budget_ms, 2000)
    output = Keyword.get(opts, :output, "/tmp/build-entity-native-parents.json")

    for repo <- [IngestRepo, ClickHouseRepo] do
      assert_private_port!(repo.config())

      if repo.config()[:hostname] not in ["localhost", "127.0.0.1"],
        do: raise("Benchmark queries/writes are localhost-only")
    end

    if rows < @lookups * 10, do: raise("Use at least #{@lookups * 10} rows")
    if projects < 2, do: raise("The other-project case needs at least 2 projects")
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")

    if !Regex.match?(~r/^build_entities_bench_[a-z0-9_]+$/, database),
      do: raise("Use an isolated build_entities_bench_* database, not #{database}")

    anchor = System.os_time(:second)

    if Keyword.get(opts, :seed, true) do
      for family <- @families do
        IngestRepo.query!(family.ddl)
        for project <- 1..projects, do: seed(family, project, rows, anchor)
      end
    end

    reference = Keyword.get(opts, :reference)
    if reference, do: verify_schema(reference)
    for family <- @families, do: verify_counts(family, projects, rows)
    wait_for_merges(database)

    measurements =
      for family <- @families, {scenario, ids, expected} <- scenarios(family, rows) do
        check = fn -> check!(family, scenario, ids, expected) end
        check.()
        started = System.os_time(:microsecond)
        serial = for _ <- 1..iterations, do: timed(check)

        concurrent =
          1..(iterations * concurrency)
          |> Task.async_stream(fn _ -> timed(check) end, max_concurrency: concurrency, timeout: 120_000)
          |> Enum.map(fn {:ok, ms} -> ms end)

        finished = System.os_time(:microsecond)
        row = %{family: family.family, scenario: scenario, serial: stats(serial), concurrent: stats(concurrent)}
        IO.puts(JSON.encode!(row))
        Map.put(row, :window, {started, finished})
      end

    # Allow the server's normal query-log flush.
    Process.sleep(10_000)

    measurements = Enum.map(measurements, &with_server_stats(&1, run_id))
    plans = Map.new(@families, &{&1.family, explain(&1)})
    parts = parts(database)

    result = %{
      database: database,
      clickhouse_port: IngestRepo.config()[:port],
      run_id: run_id,
      rows_per_project: rows,
      projects: projects,
      corrected_percent: 10,
      lookups_per_call: @lookups,
      concurrency: concurrency,
      parts: parts,
      plans: plans,
      measurements: Enum.map(measurements, &Map.delete(&1, :window))
    }

    File.write!(output, JSON.encode!(result))

    if Enum.any?(measurements, &(&1.server.queries == 0)),
      do: raise("No query statistics captured; start the repos with log_comment: run_id and query_log enabled")

    failures = Enum.filter(measurements, &(&1.serial.p95_ms > budget or &1.concurrent.p95_ms > budget))
    if failures != [], do: raise("Latency gate failed: #{JSON.encode!(Enum.map(failures, &Map.delete(&1, :window)))}")
    IO.puts("Results: #{output}; isolated dataset retained in #{database}")
    result
  end

  @doc """
  The parent ID of parent `index` of `project` in `family`, matching the SQL
  the fixtures are seeded with.
  """
  def parent_id(family, project, index) do
    hash = Base.encode16(:crypto.hash(:md5, "#{family}:#{project}:#{index}"), case: :lower)
    <<a::binary-8, b::binary-4, _::binary-1, c::binary-3, _::binary-1, d::binary-3, e::binary-12>> = hash
    "#{a}-#{b}-4#{c}-8#{d}-#{e}"
  end

  @doc """
  Raises unless each benchmark table has the reference table's partition and
  sort keys, its types for every benchmark column, and its definition of every
  benchmark skip index.
  """
  def verify_schema(reference) do
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")

    for %{table: table} <- @families do
      [ours, theirs] = Enum.map([database, reference], &table_shape(&1, table))
      if ours.keys != theirs.keys, do: raise("#{table}: keys #{inspect(ours.keys)} != #{inspect(theirs.keys)}")

      for {name, type} <- ours.columns,
          Map.get(theirs.columns, name) != type,
          do: raise("#{table}.#{name}: #{type} != #{inspect(Map.get(theirs.columns, name))}")

      for {name, definition} <- ours.indexes,
          Map.get(theirs.indexes, name) != definition,
          do: raise("#{table} index #{name}: #{inspect(definition)} != #{inspect(Map.get(theirs.indexes, name))}")
    end

    :ok
  end

  defp table_shape(database, table) do
    params = %{database: database, table: table}

    %{rows: [keys]} =
      IngestRepo.query!(
        "SELECT partition_key, sorting_key FROM system.tables WHERE database = {database:String} AND name = {table:String}",
        params
      )

    %{rows: columns} =
      IngestRepo.query!(
        "SELECT name, type FROM system.columns WHERE database = {database:String} AND table = {table:String}",
        params
      )

    %{rows: indexes} =
      IngestRepo.query!(
        """
        SELECT name, expr, type_full, granularity FROM system.data_skipping_indices
        WHERE database = {database:String} AND table = {table:String}
        """,
        params
      )

    %{
      keys: keys,
      columns: Map.new(columns, fn [name, type] -> {name, type} end),
      indexes: Map.new(indexes, fn [name | definition] -> {name, definition} end)
    }
  end

  defp seed(family, project, rows, anchor) do
    {columns, expressions} = Enum.unzip(family.seed)

    sql = """
    INSERT INTO #{family.table} (#{Enum.join(columns, ", ")})
    SELECT #{Enum.join(expressions, ", ")}
    FROM (
      SELECT
        number + {offset:UInt64} AS n,
        {project:Int64} AS project,
        {correction:Bool} AS correction,
        lower(hex(MD5(concat({family:String}, ':', toString(project), ':', toString(n))))) AS digest,
        concat(substring(digest, 1, 8), '-', substring(digest, 9, 4), '-4', substring(digest, 14, 3), '-8',
          substring(digest, 18, 3), '-', substring(digest, 21, 12)) AS parent,
        toUInt32({anchor:UInt32} - intDiv(n * #{@span_seconds}, {rows:UInt64})) AS at_s,
        at_s + if(correction, 86400, 0) AS version_s,
        multiIf(n % 4 = 0, 'generate', n % 4 = 1, 'cache', n % 4 = 2, 'build', 'test') AS command_name
      FROM numbers({count:UInt64})
      WHERE NOT correction OR n % 10 = 0
    )
    #{@seed_settings}
    """

    {elapsed, _} =
      :timer.tc(fn ->
        for correction <- [false, true], offset <- 0..(rows - 1)//@chunk do
          IngestRepo.query!(
            sql,
            %{
              offset: offset,
              count: min(@chunk, rows - offset),
              rows: rows,
              project: project,
              correction: correction,
              family: family.family,
              anchor: anchor
            },
            timeout: 300_000
          )
        end
      end)

    IO.puts("Seed #{family.table} project #{project}: #{rows} parents in #{Float.round(elapsed / 1_000_000, 2)}s")
  end

  defp verify_counts(family, projects, rows) do
    %{rows: counts} =
      IngestRepo.query!(
        "SELECT project_id, uniqExact(#{family.key}) FROM #{family.table} GROUP BY project_id ORDER BY project_id",
        %{},
        settings: [max_threads: 2, max_memory_usage: 1_073_741_824],
        timeout: 300_000
      )

    expected = for project <- 1..projects, do: [project, rows]
    if counts != expected, do: raise("#{family.table} fixture mismatch: #{inspect(counts)}")
  end

  # Measures the merged steady state rather than the part count right after
  # seeding; reported so an unmerged run is visible.
  defp wait_for_merges(database, attempts \\ 120) do
    %{rows: [[merges]]} =
      IngestRepo.query!("SELECT count() FROM system.merges WHERE database = {database:String}", %{database: database})

    if merges > 0 and attempts > 0 do
      Process.sleep(1_000)
      wait_for_merges(database, attempts - 1)
    end
  end

  defp parts(database) do
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT table, count(), uniqExact(partition_id), sum(rows), sum(secondary_indices_compressed_bytes)
        FROM system.parts WHERE database = {database:String} AND active
        GROUP BY table ORDER BY table
        """,
        %{database: database}
      )

    Map.new(rows, fn [table, parts, partitions, row_count, index_bytes] ->
      {table, %{parts: parts, partitions: partitions, rows: row_count, skip_index_bytes: index_bytes}}
    end)
  end

  defp scenarios(family, rows) do
    step = div(rows, @lookups)

    present =
      for {name, indexes} <- [
            {"recent-page", 0..(@lookups - 1)},
            {"middle-page", div(rows, 2)..(div(rows, 2) + @lookups - 1)},
            {"scattered", for(i <- 0..(@lookups - 1), do: i * step + rem(i, 10))}
          ] do
        ids = Enum.map(indexes, &parent_id(family.family, @project, &1))
        {name, ids, Map.new(Enum.zip(ids, indexes))}
      end

    other = for i <- 0..(@lookups - 1), do: parent_id(family.family, @project + 1, i)
    present ++ [{"other-project", other, %{}}]
  end

  defp check!(family, scenario, ids, expected) do
    contexts = BuildEntities.parent_contexts(@project, family.system, family.kind, ids)

    if Enum.sort(Map.keys(contexts)) != Enum.sort(Map.keys(expected)),
      do: raise("#{family.family}/#{scenario}: #{map_size(contexts)} of #{map_size(expected)} parents resolved")

    for {id, index} <- expected do
      context = Map.fetch!(contexts, id)
      corrected = rem(index, 10) == 0
      actual = observed(family.family, context)
      wanted = wanted(family.family, index, corrected)

      if actual != wanted,
        do: raise("#{family.family}/#{scenario} parent #{index}: expected #{inspect(wanted)}, got #{inspect(actual)}")

      if context.ran_by_name != nil, do: raise("#{family.family}/#{scenario}: unexpected actor")
    end
  end

  defp observed("gradle", context), do: {context.label, context.tags}
  defp observed("mix", context), do: context.label
  defp observed("xcode-build", context), do: context.label
  defp observed("xcode-command", context), do: {context.label, context.command_arguments}
  defp observed("bazel", context), do: {context.label, context.target_patterns}

  defp wanted("gradle", _index, true), do: {nil, []}
  defp wanted("gradle", index, false), do: {"app-#{rem(index, 50)}", ["bench"]}
  defp wanted("mix", _index, _corrected), do: "mix compile"
  defp wanted("xcode-build", _index, corrected), do: if(corrected, do: nil, else: "App")

  defp wanted("xcode-command", index, corrected) do
    name = Enum.at(["generate", "cache", "build", "test"], rem(index, 4))
    {name, if(corrected, do: nil, else: "tuist #{name} App")}
  end

  defp wanted("bazel", _index, corrected), do: {"build", if(corrected, do: [], else: ["//app:all"])}

  defp with_server_stats(%{window: {started, finished}} = measurement, run_id) do
    family = Enum.find(@families, &(&1.family == measurement.family))

    %{rows: rows} =
      ClickHouseRepo.query!(
        """
        SELECT query_duration_ms, read_rows, read_bytes, memory_usage,
          ProfileEvents['SelectedParts'], ProfileEvents['SelectedMarks'], ProfileEvents['SelectedRanges'],
          projections, query
        FROM system.query_log
        WHERE log_comment = {comment:String} AND type = 'QueryFinish' AND query_kind = 'Select'
          AND toUnixTimestamp64Micro(event_time_microseconds) BETWEEN {started:Int64} AND {finished:Int64}
          AND position(query, {from:String}) > 0 AND position(query, 'argMax(tuple(') > 0
        """,
        %{comment: run_id, started: started, finished: finished, from: "FROM #{family.table}"},
        settings: [max_result_rows: 100_000]
      )

    expected_shape = "argMax(tuple(#{family.columns}), #{family.version})"

    if rows != [] and not Enum.all?(rows, &String.contains?(List.last(&1), expected_shape)),
      do: raise("#{family.table}: the logged lookup no longer matches #{expected_shape}; update this benchmark")

    column = fn index -> Enum.map(rows, &Enum.at(&1, index)) end

    server = %{
      queries: length(rows),
      p95_ms: percentile(Enum.sort(column.(0)), 0.95),
      max_read_rows: Enum.max(column.(1), fn -> 0 end),
      max_read_bytes: Enum.max(column.(2), fn -> 0 end),
      max_memory_bytes: Enum.max(column.(3), fn -> 0 end),
      max_selected_parts: Enum.max(column.(4), fn -> 0 end),
      max_selected_marks: Enum.max(column.(5), fn -> 0 end),
      max_selected_ranges: Enum.max(column.(6), fn -> 0 end),
      projections: 7 |> column.() |> List.flatten() |> Enum.uniq()
    }

    Map.put(measurement, :server, server)
  end

  # Mirrors the SQL of `latest_parent_rows/6`, which `with_server_stats/2`
  # checks against the logged query, for the recent page of the first project.
  defp explain(family) do
    count = family.columns |> String.split(",") |> length()
    fields = Enum.map_join(1..count, ", ", &"latest.#{&1}")
    ids = Enum.map(0..(@lookups - 1), &parent_id(family.family, @project, &1))

    sql = """
    SELECT parent, #{fields}
    FROM (
      SELECT toString(#{family.key}) AS parent, argMax(tuple(#{family.columns}), #{family.version}) AS latest
      FROM #{family.table}
      WHERE project_id = {project_id:Int64} AND #{family.key} IN {ids:Array(#{family.key_type})}
      GROUP BY #{family.key}
    )
    """

    params = %{project_id: @project, ids: ids}

    result =
      case ClickHouseRepo.query("EXPLAIN indexes = 1, projections = 1 " <> sql, params) do
        {:ok, result} -> result
        {:error, _} -> ClickHouseRepo.query!("EXPLAIN indexes = 1 " <> sql, params)
      end

    Enum.map(result.rows, &hd/1)
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

  defp percentile([], _q), do: nil
  defp percentile(sorted, q), do: Enum.at(sorted, max(ceil(length(sorted) * q) - 1, 0))

  defp assert_private_port!(config) do
    expected = System.fetch_env!("BUILD_ENTITY_BENCH_EXPECTED_PORT")
    if expected == "8123", do: raise("Do not benchmark the shared ClickHouse port")

    if to_string(config[:port]) != expected,
      do: raise("Benchmark port mismatch: expected #{expected}, got #{config[:port]}")
  end

  defp env_integer(name, default), do: name |> System.get_env(Integer.to_string(default)) |> String.to_integer()
end
