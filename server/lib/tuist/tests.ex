defmodule Tuist.Tests do
  @moduledoc """
    Module for interacting with test runs.

    ## ClickHouse and deduplication

    This module uses ClickHouse with ReplacingMergeTree tables to store test data.
    ClickHouse doesn't support in-place updates - to "update" a row (e.g., setting `is_flaky`),
    we insert a new row with the updated values. ClickHouse eventually deduplicates rows with
    the same primary key by keeping the most recent one (based on `inserted_at`).

    However, until ClickHouse runs its background merge process, duplicate rows may exist.
    To ensure we always get the latest version of each row, we use one of these strategies:

    - For single-row queries: `ORDER BY inserted_at DESC LIMIT 1`
    - For multi-row queries: `hints: ["FINAL"]` on the FROM clause, which tells ClickHouse
      to apply ReplacingMergeTree deduplication at query time (single scan, partition-scoped)
    - For point-in-time queries (e.g. state at a past datetime): `argMax(column, inserted_at)`
      with `GROUP BY id` to pick the latest value within the time range
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Automations
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.KeyValueStore
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Shards.ShardRun
  alias Tuist.Tests.CrashReport
  alias Tuist.Tests.FlakyTestCase
  alias Tuist.Tests.FlakyTestCaseRun
  alias Tuist.Tests.QuarantinedTestCase
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseBranchPresence
  alias Tuist.Tests.TestCaseCurrentState
  alias Tuist.Tests.TestCaseDurationDailyStatsPerCase
  alias Tuist.Tests.TestCaseEvent
  alias Tuist.Tests.TestCaseFailure
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunArgument
  alias Tuist.Tests.TestCaseRunAttachment
  alias Tuist.Tests.TestCaseRunByCommit
  alias Tuist.Tests.TestCaseRunByProject
  alias Tuist.Tests.TestCaseRunByShardId
  alias Tuist.Tests.TestCaseRunByTestRun
  alias Tuist.Tests.TestCaseRunDashboardCount
  alias Tuist.Tests.TestCaseRunFlakyCorrection
  alias Tuist.Tests.TestCaseRunRepetition
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.TestRunDestination
  alias Tuist.Tests.TestRunError
  alias Tuist.Tests.TestSuiteRun
  alias Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorker
  alias Tuist.Webhooks.Dispatcher

  require Logger
  require OpenTelemetry.Tracer

  # Number of days of run history used to decide whether a test case is "active"
  # (i.e. still part of the suite). Used by `list_test_cases/2` and by the Test
  # Cases / Flaky Tests analytics charts so they stay in sync.
  @active_window_days 14
  @short_cache_ttl to_timeout(second: 10)
  @unscoped_test_suite_runs_lookback_days 7
  # ClickHouse query parameters are encoded in the request address. Ten thousand
  # identifiers stay comfortably below its default one-mebibyte limit while
  # still covering the small explicit-state sets this path is designed for.
  @max_preloaded_test_case_states 10_000
  # Sortable duration fields the listing exposes, each backed by a matching
  # aggregate state on `test_case_duration_daily_stats_per_case`. They are
  # shown side by side rather than one at a time: the useful question about a
  # test case is usually the shape of its durations, not a single number, and
  # the median beside the p99 answers "slow always or slow sometimes" without
  # reloading the table. Reading all four costs one extra merge each over the
  # groups the scan already builds.
  @duration_fields [:duration_p50, :duration_p90, :duration_p99, :duration_avg]
  # Runs a test case needs inside the active window before its durations are
  # shown or ranked. Below it the listing has no opinion: the cells render
  # empty and the row sorts last in either direction, rather than letting one
  # recorded run place a test at the top of "slowest".
  @min_duration_samples 5
  # `test_case_duration_daily_stats_per_case` is sorted by `test_case_id` ahead
  # of `date` precisely so the listing's per-test-case grouping runs in sorted
  # order. Without this the grouping falls back to a hash aggregation that holds
  # a quantile state per test case for the length of the scan, which for a large
  # project is the whole active suite at once. The `:joined` path sets the same
  # flag as part of its own settings.
  @duration_join_settings [optimize_aggregation_in_order: 1]
  @test_case_state_probe_settings [
    max_threads: 1,
    max_memory_usage: 128 * 1024 * 1024,
    optimize_aggregation_in_order: 1
  ]
  # The `:joined` listing path joins `test_cases` FINAL against the current-state
  # aggregate. The right side is now a compact pre-merged table rather than the
  # raw-ledger aggregation, so it has more headroom, but the `FINAL` over a whole
  # project's `test_cases` on the left is unchanged and remains the dominant cost
  # here, and `FINAL` cannot spill. These settings therefore stay conservative
  # (512 MiB ceiling + grace-hash + external group-by so the join/aggregation can
  # spill instead of OOMing). Relaxing the ceiling or dropping the spill paths is
  # deferred to a follow-up gated on measuring the real per-project peak memory of
  # this query in production; doing it blind risks re-introducing the OOM this
  # change exists to remove.
  @test_case_state_join_settings [
    max_threads: 1,
    max_memory_usage: 512 * 1024 * 1024,
    max_bytes_before_external_group_by: 64 * 1024 * 1024,
    optimize_aggregation_in_order: 1,
    join_algorithm: "grace_hash",
    grace_hash_join_initial_buckets: 16
  ]
  @flaky_correction_lookup_settings [
    max_threads: 1,
    max_memory_usage: 128 * 1024 * 1024
  ]
  @flaky_correction_batch_size 2000
  @flaky_correction_sweep_limit 500

  @doc """
  Number of trailing days used across the product to decide whether a test case
  is still considered part of the suite.
  """
  def active_window_days, do: @active_window_days

  defp cached_count(key, fun) do
    if Environment.test?() do
      fun.()
    else
      KeyValueStore.get_or_update([:tests, key], [ttl: @short_cache_ttl], fun)
    end
  end

  # State-change events emitted by `update_test_case` use the `muted` /
  # `unmuted` names. Pre-rename rows have already been backfilled to these
  # names by `RenameLegacyQuarantineEvents`, so consumers can match on a
  # single canonical value.
  @mute_event_types ~w(muted unmuted)
  @skip_event_types ~w(skipped unskipped)
  @quarantine_event_types @mute_event_types ++ @skip_event_types
  @active_quarantine_event_types ~w(muted skipped)
  @active_quarantine_states ~w(muted skipped)

  @terminal_shard_failure_statuses ~w(failed_processing failure)

  @stale_run_window_hours 6

  @doc """
  All mute-related event type names (`muted`, `unmuted`).
  """
  def mute_event_types, do: @mute_event_types

  @doc """
  All quarantine-related event type names — covers both Mute (`muted`,
  `unmuted`) and Skip (`skipped`, `unskipped`) modes.
  """
  def quarantine_event_types, do: @quarantine_event_types

  @doc """
  Event types that mark a test as *currently* quarantined (`muted`,
  `skipped`). The matching `un*` events leave a test in the
  not-quarantined state.
  """
  def active_quarantine_event_types, do: @active_quarantine_event_types

  @doc """
  `TestCase.state` values that indicate a test is currently quarantined.
  Source of truth for the quarantined-tests list and analytics — both
  must use this constant so the count and the table cannot disagree.
  """
  def active_quarantine_states, do: @active_quarantine_states

  # Keys present on the `Test` struct that are NOT columns on the `test_runs`
  # ClickHouse table (Ecto metadata + association loaders). Used to scrub the
  # struct when re-inserting an updated row via `IngestRepo.insert_all/2`.
  @test_struct_non_field_keys [
    :__meta__,
    :ran_by_account,
    :build_run,
    :gradle_build,
    :test_case_runs,
    :shard_plan,
    :run_destinations
  ]

  def valid_ci_providers, do: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

  def total_test_run_count do
    Test
    |> from(hints: ["FINAL"], select: count())
    |> ClickHouseRepo.one() || 0
  end

  def total_test_case_run_count do
    ClickHouseRepo.one(from(d in TestCaseRunDashboardCount, select: fragment("countMerge(count)"))) || 0
  end

  def flaky_test_case_run_count do
    ClickHouseRepo.one(
      from(d in TestCaseRunDashboardCount,
        where: d.is_flaky == true,
        select: fragment("countMerge(count)")
      )
    ) || 0
  end

  def last_24h_test_run_count do
    cached_count(:last_24h_test_run_count, &last_24h_test_run_count_query/0)
  end

  defp last_24h_test_run_count_query do
    twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24, :hour)

    ClickHouseRepo.one(
      from(t in Test,
        where: t.inserted_at >= ^twenty_four_hours_ago,
        select: count()
      )
    ) ||
      0
  end

  def last_24h_test_case_run_count do
    cached_count(:last_24h_test_case_run_count, &last_24h_test_case_run_count_query/0)
  end

  defp last_24h_test_case_run_count_query do
    yesterday = Date.add(Date.utc_today(), -1)

    ClickHouseRepo.one(
      from(d in TestCaseRunDashboardCount,
        where: d.day >= ^yesterday,
        select: fragment("countMerge(count)")
      )
    ) || 0
  end

  def last_24h_flaky_test_case_run_count do
    cached_count(:last_24h_flaky_test_case_run_count, &last_24h_flaky_test_case_run_count_query/0)
  end

  defp last_24h_flaky_test_case_run_count_query do
    yesterday = Date.add(Date.utc_today(), -1)

    ClickHouseRepo.one(
      from(d in TestCaseRunDashboardCount,
        where: d.is_flaky == true and d.day >= ^yesterday,
        select: fragment("countMerge(count)")
      )
    ) || 0
  end

  def project_test_schemes(%Project{} = project) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    ClickHouseRepo.all(
      from(t in Test,
        where: t.project_id == ^project.id,
        where: t.scheme != "",
        where: t.ran_at > ^thirty_days_ago,
        order_by: [asc: t.scheme],
        distinct: true,
        select: t.scheme
      )
    )
  end

  def upload_crash_report(attrs) do
    %CrashReport{}
    |> CrashReport.create_changeset(attrs)
    |> IngestRepo.insert()
  end

  def get_test(id, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        preload = Keyword.get(opts, :preload, [])

        query =
          from(t in Test,
            where: t.id == ^uuid,
            order_by: [desc: t.inserted_at],
            limit: 1
          )

        case ClickHouseRepo.one(query) do
          nil ->
            {:error, :not_found}

          test ->
            ch_preload_keys = [
              :build_run,
              :gradle_build,
              :shard_plan,
              :run_destinations,
              :test_case_runs
            ]

            {ch_preloads, pg_preloads} =
              Enum.split_with(preload, fn
                key when is_atom(key) -> key in ch_preload_keys
                {key, _} -> key in ch_preload_keys
              end)

            test =
              test
              |> Repo.preload(pg_preloads)
              |> ClickHouseRepo.preload(ch_preloads)

            {:ok, test}
        end

      :error ->
        {:error, :not_found}
    end
  end

  def get_latest_test_by_build_run_id(build_run_id) do
    query =
      from(t in Test,
        where: t.build_run_id == ^build_run_id,
        order_by: [desc: t.ran_at, desc: t.inserted_at],
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test -> {:ok, test}
    end
  end

  def get_latest_test_by_gradle_build_id(gradle_build_id) do
    query =
      from(t in Test,
        where: t.gradle_build_id == ^gradle_build_id,
        order_by: [desc: t.ran_at, desc: t.inserted_at],
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test -> {:ok, test}
    end
  end

  def list_test_runs(attrs) do
    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(Test, attrs, for: Test)

    results = Repo.preload(results, :ran_by_account)

    {results, meta}
  end

  def latest_completed_test_runs(project_id, limit \\ 40) do
    from(t in Test,
      where: t.project_id == ^project_id,
      where: t.status in ["success", "failure", "skipped"],
      order_by: [desc: t.ran_at],
      limit: ^limit,
      select: %{
        id: t.id,
        duration: t.duration,
        status: t.status,
        ran_at: t.ran_at
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  def list_sharded_test_runs(attrs) do
    base_query = from(t in Test, where: not is_nil(t.shard_plan_id))

    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: Test)

    results = ClickHouseRepo.preload(results, [:shard_plan])

    {results, meta}
  end

  def get_test_run_failures_count(test_run_id) do
    query =
      from(tcr in TestCaseRunByTestRun,
        hints: ["FINAL"],
        where: tcr.test_run_id == ^test_run_id and tcr.status == "failure",
        select: count(tcr.id)
      )

    ClickHouseRepo.one(query) || 0
  end

  def list_test_suite_runs(attrs) do
    base_query =
      if scoped_test_suite_run_attrs?(attrs) do
        TestSuiteRun
      else
        seven_days_ago = DateTime.add(DateTime.utc_now(), -@unscoped_test_suite_runs_lookback_days, :day)
        from(tsr in TestSuiteRun, where: tsr.inserted_at >= ^seven_days_ago)
      end

    Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestSuiteRun)
  end

  def list_test_module_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestModuleRun, attrs, for: TestModuleRun)
  end

  defp scoped_test_suite_run_attrs?(attrs) do
    attrs
    |> flop_filters()
    |> Enum.any?(fn
      %{field: field} when field in [:test_run_id, :test_module_run_id, :shard_id] -> true
      _ -> false
    end)
  end

  defp flop_filters(%Flop{filters: filters}), do: List.wrap(filters)
  defp flop_filters(%{filters: filters}) when is_list(filters), do: filters
  defp flop_filters(_attrs), do: []

  @doc """
  Constructs a CI run URL for a test run based on the CI provider and metadata.
  Returns nil if the test doesn't have complete CI information.
  """
  def test_ci_run_url(%Test{} = test) do
    Tuist.VCS.ci_run_url(%{
      ci_provider: normalize_ci_provider(test.ci_provider),
      ci_run_id: test.ci_run_id,
      ci_project_handle: test.ci_project_handle,
      ci_host: test.ci_host
    })
  end

  defp normalize_ci_provider(nil), do: nil
  defp normalize_ci_provider(""), do: nil

  defp normalize_ci_provider(provider) when is_binary(provider) do
    if provider in valid_ci_providers() do
      provider
    end
  end

  defp normalize_ci_provider(provider) when is_atom(provider), do: Atom.to_string(provider)

  @doc """
  Lists the run/target-level errors recorded for a test run, oldest-first.

  A sharded run collects errors from every shard, so an error that several
  shards hit (a target that fails to load in each of them) is stored once per
  shard. They are collapsed here, keeping the earliest, rather than on write,
  where concurrent shards could still race past each other.
  """
  def list_run_errors(test_run_id) do
    from(e in TestRunError,
      where: e.test_run_id == ^test_run_id,
      order_by: [asc: e.inserted_at]
    )
    |> ClickHouseRepo.all()
    |> Enum.uniq_by(&{&1.module_name, &1.message})
  end

  def create_test(attrs) do
    attrs = normalize_string_keys(attrs)
    shard_plan_id = Map.get(attrs, :shard_plan_id)

    if is_nil(shard_plan_id) do
      create_new_test(attrs)
    else
      create_or_update_sharded_test(attrs)
    end
  end

  defp normalize_string_keys(%_{} = struct), do: struct

  defp normalize_string_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), normalize_string_keys(v)}
      {k, v} -> {k, normalize_string_keys(v)}
    end)
  end

  defp normalize_string_keys(list) when is_list(list), do: Enum.map(list, &normalize_string_keys/1)

  defp normalize_string_keys(value), do: value

  defp create_new_test(attrs, shard_index \\ nil, shard_plan \\ nil) do
    test_modules = Map.get(attrs, :test_modules, [])
    is_ci = Map.get(attrs, :is_ci, false)
    has_flaky_tests = has_any_flaky_test_case?(test_modules)

    attrs =
      if has_flaky_tests and is_ci do
        Map.put(attrs, :is_flaky, true)
      else
        attrs
      end

    case %Test{}
         |> Test.create_changeset(attrs)
         |> IngestRepo.insert() do
      {:ok, test} ->
        create_run_destinations(test, Map.get(attrs, :run_destinations, []))
        create_run_errors(test, Map.get(attrs, :run_errors, []))

        {test_case_ids_with_flaky_run, test_case_runs} =
          create_test_modules(test, test_modules, shard_index, shard_plan)

        Tuist.Tasks.run_async(fn ->
          mark_test_run_as_flaky(test, test_case_ids_with_flaky_run)

          project = Tuist.Projects.get_project_by_id(test.project_id)

          Tuist.PubSub.broadcast(
            test,
            "#{project.account.name}/#{project.name}",
            :test_created
          )
        end)

        {:ok, %{test | test_case_runs: test_case_runs}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_run_destinations(%Test{id: test_run_id}, destinations) when is_list(destinations) do
    now = NaiveDateTime.utc_now()

    rows =
      destinations
      |> Enum.map(fn destination ->
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          name: destination_field(destination, :name),
          platform: destination_field(destination, :platform),
          os_version: destination_field(destination, :os_version),
          inserted_at: now
        }
      end)
      |> Enum.filter(&(&1.name && &1.platform && &1.os_version))

    case rows do
      [] -> :ok
      rows -> IngestRepo.insert_all(TestRunDestination, rows)
    end
  end

  defp create_run_destinations(_, _), do: :ok

  defp destination_field(destination, key) when is_atom(key) do
    Map.get(destination, key) || Map.get(destination, Atom.to_string(key))
  end

  # Run/target-level entries that aren't test failures: the test runner itself
  # errored (e.g. a target whose `.xctest` bundle couldn't be loaded), or Swift
  # Testing recorded an issue while no test was running. The parser lifts both
  # out of the test cases, so they don't create test_case_runs or fan out
  # webhooks; they're stored separately and surfaced as an "Errors" section.
  defp create_run_errors(%Test{id: test_run_id, project_id: project_id}, errors) when is_list(errors) do
    now = NaiveDateTime.utc_now()

    rows =
      errors
      |> Enum.map(fn error ->
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          project_id: project_id,
          module_name: error_field(error, :target) || "",
          message: error_field(error, :message),
          inserted_at: now
        }
      end)
      |> Enum.filter(&(&1.message && &1.message != ""))

    case rows do
      [] -> :ok
      rows -> IngestRepo.insert_all(TestRunError, rows)
    end
  end

  defp create_run_errors(_, _), do: :ok

  defp error_field(error, key) when is_atom(key) do
    Map.get(error, key) || Map.get(error, Atom.to_string(key))
  end

  defp create_or_update_sharded_test(attrs) do
    shard_plan_id = Map.fetch!(attrs, :shard_plan_id)
    project_id = Map.fetch!(attrs, :project_id)
    test_modules = Map.get(attrs, :test_modules, [])

    {:ok, shard_plan} = Shards.get_shard_plan(shard_plan_id)
    expected_shard_count = shard_plan.shard_count

    shard_index = Map.get(attrs, :shard_index)
    shard_status = Map.get(attrs, :status, "success")
    shard_duration = Map.get(attrs, :duration, 0)

    # `shard_runs` is the only authority on which run a plan's shards report
    # into. The first shard claims that mapping before its run row exists, so a
    # report that dies in between leaves a pointer the next shard rebuilds
    # through, rather than a run no later shard can find.
    mapped_id = mapped_shard_test_run_id(project_id, shard_plan_id)
    merged_id = mapped_id || Map.get(attrs, :id) || UUIDv7.generate()

    if is_nil(mapped_id) do
      insert_shard_run(
        shard_plan_id,
        project_id,
        merged_id,
        shard_index,
        shard_status,
        shard_duration,
        attrs
      )
    end

    existing = sharded_test_by_id(project_id, merged_id)

    attrs = Map.put(attrs, :id, merged_id)

    result =
      case existing do
        nil ->
          test_status =
            if expected_shard_count > 1 and shard_status not in @terminal_shard_failure_statuses do
              "in_progress"
            else
              shard_status
            end

          attrs =
            attrs
            |> Map.put(:status, test_status)
            |> Map.put_new(:build_run_id, shard_plan.build_run_id)
            |> Map.put_new(:gradle_build_id, shard_plan.gradle_build_id)

          create_new_test(attrs, shard_index, shard_plan)

        existing_test ->
          # Merged before the test case runs are built, not just before the
          # Test row is rewritten: the runs copy `scheme` and the git fields
          # off this struct, and the shard that first carries parsed metadata
          # would otherwise stamp them with the placeholder row's blanks.
          merged_test = merge_shard_metadata(existing_test, attrs)

          {test_case_ids_with_flaky_run, test_case_runs} =
            OpenTelemetry.Tracer.with_span "tests.create_test_modules" do
              create_test_modules(merged_test, test_modules, shard_index, shard_plan)
            end

          # Every shard carries its own errors, and only unattributed issues
          # leave the shard's status untouched, so dropping these would erase
          # the diagnostic entirely rather than merely lose detail on an
          # already-red run. Shards write concurrently and ClickHouse has no
          # uniqueness, so an error hit by several shards is deduplicated on
          # read instead of here.
          create_run_errors(merged_test, Map.get(attrs, :run_errors, []))

          insert_shard_run(
            shard_plan_id,
            project_id,
            existing_test.id,
            shard_index,
            shard_status,
            shard_duration,
            attrs
          )

          # A shard can move through processing, failed_processing, and a
          # successful client retry. Collapse that append-only history before
          # deciding whether the merged run is complete.
          #
          # The row inserted just above is not reliably read back within the
          # same request, so the reporting shard contributes its status from
          # memory and the query only supplies the other shards. Reading all
          # of them back instead made the last shard to report count itself
          # as still processing, which left the merged run in_progress with
          # every shard green.
          latest_statuses =
            existing_test.id
            |> latest_shard_statuses()
            |> Map.put(shard_index || 0, shard_status)
            |> Map.values()

          reported_count = Enum.count(latest_statuses, &(&1 != "processing"))

          merged_status = merged_shard_status(latest_statuses, reported_count, expected_shard_count)

          merged_duration = max(existing_test.duration, shard_duration)

          updated_test =
            merged_test
            |> Map.put(:status, merged_status)
            |> Map.put(:duration, merged_duration)

          update_attrs =
            updated_test
            |> Map.from_struct()
            |> Map.drop(@test_struct_non_field_keys)
            |> Map.put(:inserted_at, NaiveDateTime.utc_now())

          IngestRepo.insert_all(Test, [update_attrs])

          Tuist.Tasks.run_async(fn ->
            mark_test_run_as_flaky(updated_test, test_case_ids_with_flaky_run)

            project = Tuist.Projects.get_project_by_id(updated_test.project_id)

            Tuist.PubSub.broadcast(
              updated_test,
              "#{project.account.name}/#{project.name}",
              :test_created
            )
          end)

          {:ok, %{updated_test | test_case_runs: test_case_runs}}
      end

    with {:ok, test} <- result do
      # Rebuilding a run whose row went missing still owes the mapping this
      # shard's status; the claim above only covers the plan's first shard.
      if is_nil(existing) and not is_nil(mapped_id) do
        insert_shard_run(
          shard_plan_id,
          project_id,
          test.id,
          shard_index,
          shard_status,
          shard_duration,
          attrs
        )
      end

      {:ok, test}
    end
  end

  # Keyed on the `(project_id, shard_plan_id, …)` sorting key. Resolving this
  # against `test_runs` instead would scan the project's whole key range, since
  # `shard_plan_id` is not part of that table's sorting key.
  defp mapped_shard_test_run_id(project_id, shard_plan_id) do
    ClickHouseRepo.one(
      from(shard_run in ShardRun,
        where: shard_run.project_id == ^project_id,
        where: shard_run.shard_plan_id == ^shard_plan_id,
        order_by: [desc: shard_run.inserted_at],
        limit: 1,
        select: shard_run.test_run_id
      )
    )
  end

  # Avoids FINAL because ordering the physical rows by version returns the same
  # latest run without an in-memory merge.
  defp sharded_test_by_id(project_id, test_run_id) do
    ClickHouseRepo.one(
      from(test in Test,
        where: test.project_id == ^project_id,
        where: test.id == ^test_run_id,
        order_by: [desc: test.inserted_at],
        limit: 1
      )
    )
  end

  # Carry forward metadata fields when a later shard report has them and
  # the existing Test row left them blank. The first shard often arrives
  # with status=processing before xcresult parsing has populated `scheme`
  # and friends; without this merge the dashboard's title stays "Unknown"
  # for the lifetime of the run.
  @shard_mergeable_fields [
    :scheme,
    :macos_version,
    :xcode_version,
    :model_identifier,
    :git_branch,
    :git_commit_sha,
    :git_ref,
    :ci_run_id,
    :ci_project_handle,
    :ci_host,
    :ci_provider,
    :build_run_id,
    :gradle_build_id
  ]

  defp merge_shard_metadata(existing_test, attrs) do
    Enum.reduce(@shard_mergeable_fields, existing_test, fn field, acc ->
      incoming = Map.get(attrs, field)
      current = Map.get(acc, field)

      if blank?(current) and not blank?(incoming) do
        Map.put(acc, field, incoming)
      else
        acc
      end
    end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp latest_shard_statuses(test_run_id) do
    from(sr in ShardRun,
      where: sr.test_run_id == ^test_run_id,
      group_by: sr.shard_index,
      select: {sr.shard_index, fragment("argMax(?, ?)", sr.status, sr.inserted_at)}
    )
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  # A shard whose report never reaches the server holds the merged run at
  # `in_progress` until the six-hour reaper runs, so the pull request comment
  # and the dashboard show an hourglass over a run that is already red. A
  # failure any shard reported is terminal, so it decides the merged run
  # without waiting for the missing reports. Only success still needs every
  # shard to have reported.
  defp merged_shard_status(latest_statuses, reported_count, expected_shard_count) do
    if reported_count >= expected_shard_count or
         Enum.any?(latest_statuses, &(&1 in @terminal_shard_failure_statuses)) do
      compute_final_shard_status(latest_statuses)
    else
      "in_progress"
    end
  end

  defp compute_final_shard_status(latest_statuses) do
    cond do
      "failed_processing" in latest_statuses -> "failed_processing"
      "failure" in latest_statuses -> "failure"
      true -> "success"
    end
  end

  defp insert_shard_run(plan_id, project_id, test_run_id, shard_index, status, duration, attrs) do
    now = NaiveDateTime.utc_now()

    IngestRepo.insert_all(ShardRun, [
      %{
        shard_plan_id: plan_id,
        project_id: project_id,
        test_run_id: test_run_id,
        shard_index: shard_index || 0,
        status: status,
        duration: duration || 0,
        ran_at: Map.get(attrs, :ran_at, now),
        inserted_at: now
      }
    ])
  end

  defp mark_test_run_as_flaky(test, []), do: test
  defp mark_test_run_as_flaky(%{is_flaky: true} = test, _flaky_ids), do: test

  defp mark_test_run_as_flaky(test, _flaky_ids) do
    updated_test = %{test | is_flaky: true}

    attrs =
      updated_test
      |> Map.from_struct()
      |> Map.drop(@test_struct_non_field_keys)
      |> Map.put(:inserted_at, NaiveDateTime.utc_now())

    IngestRepo.insert_all(Test, [attrs])
    updated_test
  end

  defp enqueue_flaky_alert_evaluations(test, test_case_runs) do
    test_case_ids =
      test_case_runs
      |> Enum.map(& &1.test_case_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Automations.enqueue_flaky_alert_evaluations(test.project_id, test_case_ids)
  end

  defp has_any_flaky_test_case?(test_modules) do
    test_modules
    |> Enum.flat_map(&Map.get(&1, :test_cases, []))
    |> Enum.any?(&test_case_is_flaky?/1)
  end

  defp test_case_is_flaky?(case_attrs) do
    repetitions = Map.get(case_attrs, :repetitions, [])
    statuses = Enum.map(repetitions, &Map.get(&1, :status))

    "success" in statuses and "failure" in statuses
  end

  @doc """
  Creates test cases and returns a map of {name, module_name, suite_name} => test_case_id.
  Uses deterministic UUIDs based on the test case identity, so duplicates are handled
  by ClickHouse's ReplacingMergeTree engine (keeps the row with the latest inserted_at).

  Each test case data map should contain:
  - :name, :module_name, :suite_name - identity fields
  - :status, :duration, :ran_at - latest run data
  """
  def create_test_cases(project_id, test_case_data_list, existing_test_cases, opts \\ []) do
    test_run_id = Keyword.get(opts, :test_run_id)
    is_ci = Keyword.get(opts, :is_ci, false)
    now = NaiveDateTime.utc_now()

    test_case_ids_with_data =
      Enum.map(test_case_data_list, fn data ->
        id = generate_test_case_id(project_id, data.name, data.module_name, data.suite_name)
        {id, data}
      end)

    existing_data = existing_test_cases

    {test_cases, test_cases_with_flaky_run} =
      Enum.map_reduce(test_case_ids_with_data, [], fn {id, data}, acc ->
        existing = Map.get(existing_data, id, %{recent_durations: []})
        new_durations = Enum.take([data.duration | existing.recent_durations], 50)

        new_avg =
          if Enum.empty?(new_durations),
            do: 0,
            else: div(Enum.sum(new_durations), length(new_durations))

        current_run_is_flaky = Map.get(data, :is_flaky, false)
        existing_is_flaky = Map.get(existing, :is_flaky) || false

        # Update only the column matching the current run's environment; carry
        # the other forward from the prior row so ReplacingMergeTree's
        # whole-row replacement doesn't lose the timestamp from the opposite
        # environment. The Test Cases listing's CI/Local active-period
        # filter reads these columns directly.
        existing_last_ran_at_ci = Map.get(existing, :last_ran_at_ci)
        existing_last_ran_at_local = Map.get(existing, :last_ran_at_local)

        {last_ran_at_ci, last_ran_at_local} =
          if is_ci do
            {data.ran_at, existing_last_ran_at_local}
          else
            {existing_last_ran_at_ci, data.ran_at}
          end

        test_case = %{
          id: id,
          name: data.name,
          module_name: data.module_name,
          suite_name: data.suite_name,
          project_id: project_id,
          last_status: data.status,
          last_duration: data.duration,
          last_ran_at: data.ran_at,
          last_ran_at_ci: last_ran_at_ci,
          last_ran_at_local: last_ran_at_local,
          # Legacy columns, now inert: every pod reads `test_case_states`, so
          # there is nothing left to carry forward for. Written as the schema
          # defaults until a follow-up drops the columns outright.
          is_flaky: false,
          last_run_id: test_run_id,
          state: "enabled",
          inserted_at: now,
          recent_durations: new_durations,
          avg_duration: new_avg
        }

        acc = if current_run_is_flaky and not existing_is_flaky, do: [id | acc], else: acc
        {test_case, acc}
      end)

    new_test_case_ids =
      test_case_ids_with_data
      |> Enum.map(fn {id, _} -> id end)
      |> Enum.reject(&Map.has_key?(existing_data, &1))
      |> MapSet.new()

    Tuist.Tasks.run_async(fn -> TestCase.Buffer.insert_all(test_cases) end)

    test_case_id_map =
      Map.new(test_cases, fn tc ->
        {{tc.name, tc.module_name, tc.suite_name}, tc.id}
      end)

    {test_case_id_map, test_cases_with_flaky_run, new_test_case_ids, test_cases}
  end

  defp collect_test_case_ids(project_id, test_modules) do
    test_modules
    |> Enum.flat_map(fn module_attrs ->
      module_name = Map.get(module_attrs, :name)
      test_cases = Map.get(module_attrs, :test_cases, [])

      Enum.map(test_cases, fn case_attrs ->
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""
        generate_test_case_id(project_id, Map.get(case_attrs, :name), module_name, suite_name)
      end)
    end)
    |> Enum.uniq()
  end

  # Batch size for the existing-test-case lookup. The IDs travel as a single
  # ClickHouse array parameter (see existing_test_cases_chunk_query/2), so the
  # multipart request always carries one form field for them regardless of batch
  # size. We still chunk to keep that parameter's encoded value below
  # ClickHouse's per-field value-length limit on large reports.
  @existing_test_cases_batch_size 2_000

  defp get_existing_test_cases(_project_id, [], _flaky_run_test_case_ids), do: %{}

  # Returns the latest `recent_durations` and per-environment run timestamps per
  # test case for the given IDs. We avoid the FINAL hint because the per-call
  # merge cost dominates when this is called during ingestion (every test
  # report) and dedupe in Elixir from a small result set instead.
  #
  # `is_flaky` comes from `test_case_states` and is read-only here: it decides
  # whether this run is the one that newly flags the test case. Ingestion never
  # writes it back — see the legacy-column note in `create_test_cases/4`.
  defp get_existing_test_cases(project_id, test_case_ids, flaky_run_test_case_ids) do
    existing =
      test_case_ids
      |> Enum.chunk_every(@existing_test_cases_batch_size)
      |> Enum.reduce(%{}, fn ids_chunk, acc ->
        project_id
        |> fetch_existing_test_cases_chunk(ids_chunk)
        |> Enum.reduce(acc, &merge_latest_test_case/2)
      end)

    # Only the test cases that are flaky in *this* run need their stored flag:
    # it is read once, to decide whether this run is the one that newly flags
    # them, and that check short-circuits on the current run first. Fetching it
    # for every test case in the report meant an extra ClickHouse round-trip per
    # chunk whose result was discarded whenever nothing was flaky, which is the
    # overwhelmingly common case.
    flaky_flags =
      fetch_test_case_flaky_flags(project_id, Enum.filter(flaky_run_test_case_ids, &Map.has_key?(existing, &1)))

    Map.new(existing, fn {id, row} ->
      {id, Map.put(row, :is_flaky, Map.get(flaky_flags, id) || false)}
    end)
  end

  # Keyed off the resolved run data rather than the raw repetitions, because a
  # test case can also be flagged flaky by cross-run detection, which only shows
  # up here.
  defp flaky_run_test_case_ids(project_id, test_case_run_data) do
    for {{name, module_name, suite_name}, data} <- test_case_run_data,
        Map.get(data, :is_flaky, false) do
      generate_test_case_id(project_id, name, module_name, suite_name)
    end
  end

  defp fetch_test_case_flaky_flags(_project_id, []), do: %{}

  defp fetch_test_case_flaky_flags(project_id, test_case_ids) do
    test_case_ids
    |> Enum.chunk_every(@existing_test_cases_batch_size)
    |> Enum.reduce(%{}, fn ids_chunk, acc ->
      rows =
        project_id
        |> test_case_flaky_flags_chunk_query(ids_chunk)
        |> ClickHouseRepo.all(multipart: true)

      Enum.reduce(rows, acc, &Map.put(&2, &1.test_case_id, &1.is_flaky))
    end)
  end

  # Same single-`Array(UUID)`-parameter shape as
  # `existing_test_cases_chunk_query/2`, and for the same reason. The ID filter
  # sits inside the aggregate so it only collapses the rows this report asks
  # about rather than every flagged test case in the project.
  defp test_case_flaky_flags_chunk_query(project_id, ids_chunk) do
    from(s in TestCaseCurrentState,
      where:
        s.project_id == ^project_id and
          fragment("? IN (?)", s.test_case_id, type(^ids_chunk, {:array, Ecto.UUID})),
      group_by: s.test_case_id,
      select: %{
        test_case_id: s.test_case_id,
        # A test case whose rows all came from state events has `is_flaky` null
        # in the aggregate, and `argMaxIfMerge` yields null for it, so the group
        # exists but the value is null. Normalizing here rather than at the call
        # site keeps the null from reaching the ingestion arithmetic below.
        is_flaky: fragment("ifNull(argMaxIfMerge(is_flaky), false)")
      }
    )
  end

  defp fetch_existing_test_cases_chunk(project_id, ids_chunk) do
    project_id
    |> existing_test_cases_chunk_query(ids_chunk)
    |> ClickHouseRepo.all(multipart: true)
  end

  # Binds the IDs as a single `Array(UUID)` parameter via a fragment instead of
  # `tc.id in ^ids_chunk`. `in` expands to one bound parameter per ID, and in
  # multipart mode each parameter becomes its own form field, which overflows
  # ClickHouse's form-field limit on large reports.
  defp existing_test_cases_chunk_query(project_id, ids_chunk) do
    from(tc in TestCase,
      where:
        tc.project_id == ^project_id and
          fragment("? IN (?)", tc.id, type(^ids_chunk, {:array, Ecto.UUID})),
      select: %{
        id: tc.id,
        recent_durations: tc.recent_durations,
        last_ran_at_ci: tc.last_ran_at_ci,
        last_ran_at_local: tc.last_ran_at_local,
        inserted_at: tc.inserted_at
      }
    )
  end

  defp merge_latest_test_case(row, acc) do
    case Map.fetch(acc, row.id) do
      {:ok, existing} ->
        if NaiveDateTime.after?(row.inserted_at, existing.inserted_at) do
          Map.put(acc, row.id, row)
        else
          acc
        end

      :error ->
        Map.put(acc, row.id, row)
    end
  end

  defp generate_test_case_id(project_id, name, module_name, suite_name) do
    identity = "#{project_id}:#{name}:#{module_name}:#{suite_name}"

    <<a::32, b::16, c::16, d::16, e::48>> =
      :md5
      |> :crypto.hash(identity)
      |> binary_part(0, 16)

    Ecto.UUID.cast!(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>)
  end

  @doc """
  Gets a test case by its UUID with all denormalized fields.
  Returns {:ok, test_case} or {:error, :not_found}.
  """
  def get_test_case_by_id(id) do
    query =
      from(tc in TestCase,
        where: tc.id == ^id,
        order_by: [desc: tc.inserted_at],
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil ->
        {:error, :not_found}

      test_case ->
        resolved = resolve_test_case_state(test_case.project_id, test_case.id)
        {:ok, apply_test_case_state(test_case, resolved)}
    end
  end

  # `state` / `is_flaky` are resolved from `test_case_current_states` (the
  # pre-aggregated projection of the `test_case_states` ledger), not from the
  # `test_cases` row. The columns of the same name on `test_cases` are legacy
  # leftovers that ingestion still overwrites; they are never read. A test case
  # with no aggregate row has never been muted or flagged, so it resolves to the
  # defaults.
  @default_test_case_state %{state: "enabled", is_flaky: false}

  @doc """
  Returns the current control-plane state for each requested test case.

  Test cases without a state event are included as enabled so callers can
  apply state-based policies without treating an absent projection row as an
  unknown state.
  """
  def get_test_case_states(project_id, test_case_ids) do
    resolved_states = resolve_test_case_states(project_id, test_case_ids)

    Map.new(test_case_ids, fn test_case_id ->
      {test_case_id, Map.get(resolved_states, test_case_id, @default_test_case_state)}
    end)
  end

  # Scoped by `project_id` (which the caller already read off the test case) so
  # this rides the `(project_id, test_case_id)` sort prefix. The `GROUP BY` still
  # matters: partial aggregate states are not merged synchronously, so a key can
  # have several rows that `argMaxIfMerge` folds together.
  defp resolve_test_case_state(project_id, test_case_id) do
    query =
      from(s in TestCaseCurrentState,
        where: s.project_id == ^project_id and s.test_case_id == ^test_case_id,
        group_by: [s.project_id, s.test_case_id],
        select: %{
          state: fragment("argMaxIfMerge(state)"),
          is_flaky: fragment("argMaxIfMerge(is_flaky)")
        }
      )

    case ClickHouseRepo.one(query) do
      nil -> @default_test_case_state
      resolved -> normalize_test_case_state(resolved)
    end
  end

  # Each row carries only the column its event set, so a test case can have rows
  # for one column and none for the other. `argMaxIf` over an empty set yields
  # null for these nullable columns, which is the "never touched" case and
  # resolves to the default.
  defp normalize_test_case_state(resolved) do
    %{
      state: normalize_state(resolved.state),
      is_flaky: resolved.is_flaky || false
    }
  end

  defp normalize_state(state) when state in [nil, ""], do: "enabled"
  defp normalize_state(state), do: state

  defp apply_test_case_state(test_case, resolved) do
    %{test_case | state: resolved.state, is_flaky: resolved.is_flaky}
  end

  # Collapses the projection into the current value per test case. Scoped by
  # `project_id` so it rides the table's sort prefix. `argMaxIfMerge` folds each
  # test case's partial aggregate states (state and is_flaky were built from
  # their own non-null event streams, so they resolve independently).
  defp test_case_states_subquery(project_id) do
    from(s in TestCaseCurrentState,
      where: s.project_id == ^project_id,
      group_by: s.test_case_id,
      select: %{
        test_case_id: s.test_case_id,
        state: fragment("argMaxIfMerge(state)"),
        is_flaky: fragment("argMaxIfMerge(is_flaky)")
      }
    )
  end

  defp resolve_test_case_states(project_id, test_case_ids) do
    resolve_test_case_states(project_id, test_case_ids, [])
  end

  defp resolve_test_case_states(_project_id, [], _opts), do: %{}

  defp resolve_test_case_states(project_id, test_case_ids, opts) do
    query = test_case_states_subquery(project_id)

    query =
      if is_nil(test_case_ids) do
        query
      else
        where(query, [state], state.test_case_id in ^test_case_ids)
      end

    query =
      case Keyword.fetch(opts, :limit) do
        {:ok, limit} -> limit(query, ^limit)
        :error -> query
      end

    repo_opts =
      case Keyword.fetch(opts, :settings) do
        {:ok, settings} -> [settings: settings]
        :error -> []
      end

    query
    |> ClickHouseRepo.all(repo_opts)
    |> Map.new(fn state ->
      {state.test_case_id, normalize_test_case_state(state)}
    end)
  end

  @doc """
  Updates a test case by inserting a new row with the given attributes.
  ClickHouse ReplacingMergeTree will keep the most recent row.

  Only `is_flaky` and `state` are valid update attributes.

  Creates test case events to track the state change.

  ## Parameters
  - `test_case_id` - the test case UUID to update
  - `update_attrs` - map with `:is_flaky` boolean and/or `:state` (`"enabled"` | `"muted"` | `"skipped"`)
  - `opts` - optional keyword list with `:actor_id` (account_id for user actions, nil for system / automation)
    and `:alert_id` (set by `ActionExecutor` so the event timeline can attribute the change to its automation)
  """
  def update_test_case(test_case_id, update_attrs, opts \\ []) when is_map(update_attrs) do
    valid_keys = [:is_flaky, :state]
    filtered_attrs = Map.take(update_attrs, valid_keys)
    actor_id = Keyword.get(opts, :actor_id)
    alert_id = Keyword.get(opts, :alert_id)

    with {:ok, test_case} <- get_test_case_by_id(test_case_id) do
      ensure_projectable!(test_case)

      updated_test_case = Map.merge(test_case, filtered_attrs)

      event_types = determine_test_case_events(test_case, filtered_attrs)
      record_test_case_events(test_case, event_types, actor_id, alert_id)
      # Broadcast THIS call's update before fanning out to event-driven
      # automations. An automation action (e.g. change_state) re-enters
      # `update_test_case/3`, which will broadcast its own update; we want
      # that nested broadcast to land LAST so the LiveView ends up with the
      # automation-applied state, not our pre-automation snapshot.
      broadcast_test_case_update(updated_test_case, event_types)
      dispatch_event_driven_automations(test_case, event_types)
      dispatch_webhooks(updated_test_case, event_types, actor_id, alert_id)

      {:ok, updated_test_case}
    end
  end

  # Webhooks subscribe at the account-account level and fire on every state
  # transition — both user-initiated and automation-driven — so receivers
  # (e.g. a Jira ingest) see the full audit trail. Failures are swallowed
  # inside the dispatcher; we don't want a webhook problem to abort the
  # write that produced the event.
  defp dispatch_webhooks(_test_case, [], _actor_id, _alert_id), do: :ok

  defp dispatch_webhooks(test_case, event_types, actor_id, alert_id) do
    Dispatcher.dispatch_test_case_event(test_case, event_types,
      actor_id: actor_id,
      alert_id: alert_id
    )
  end

  @doc """
  PubSub topic LiveViews can subscribe to for real-time updates on a
  single test case (state / is_flaky flips). The matching broadcast
  payload is `{:test_case_updated, %{id: id, is_flaky: bool, state: string, event_types: [atom]}}`.
  """
  def test_case_topic(test_case_id), do: "test_case:#{test_case_id}"

  defp broadcast_test_case_update(_test_case, []), do: :ok

  defp broadcast_test_case_update(test_case, event_types) do
    payload = %{
      id: test_case.id,
      is_flaky: test_case.is_flaky,
      state: test_case.state,
      event_types: event_types
    }

    Phoenix.PubSub.broadcast(
      Tuist.PubSub,
      test_case_topic(test_case.id),
      {:test_case_updated, payload}
    )
  end

  # The projection is keyed by project and every read of it is project-scoped,
  # so an event without a real `project_id` records history that no read can
  # ever resolve back into state. That is the exact failure this whole change
  # exists to remove, so it fails loudly. Checked before any write rather than
  # at the point of use, so a violation can't leave the legacy column updated
  # with no matching event behind it.
  defp ensure_projectable!(test_case) do
    if is_nil(test_case.project_id) or test_case.project_id == 0 do
      raise ArgumentError, "test case #{test_case.id} has no project_id; refusing to record a state change"
    end

    :ok
  end

  defp record_test_case_events(_test_case, [], _actor_id, _alert_id), do: :ok

  # `project_id` is denormalized onto the event so `test_case_states_mv` can
  # project it into `test_case_states`, whose reads are all project-scoped. A
  # materialized view only sees the inserted rows and can't join back for it.
  defp record_test_case_events(test_case, event_types, actor_id, alert_id) do
    now = NaiveDateTime.utc_now()

    events =
      Enum.map(event_types, fn event_type ->
        %{
          id: UUIDv7.generate(),
          test_case_id: test_case.id,
          project_id: test_case.project_id,
          event_type: to_string(event_type),
          actor_id: actor_id,
          alert_id: alert_id,
          inserted_at: now
        }
      end)

    TestCaseEvent.Buffer.insert_all(events)
    # State-change events are rare and we want subscribers (e.g. the
    # `TestCaseLive` PubSub handler that triggers a history refresh) to see
    # them immediately rather than wait for the 5s buffer tick. Flushing is
    # cheap here — these events are emitted at most a few times per second
    # per test case.
    TestCaseEvent.Buffer.flush()
  end

  defp dispatch_event_driven_automations(test_case, event_types) do
    # Automation-driven updates re-enter `update_test_case/3`, which calls
    # back into this dispatcher: an automation reacting to `marked_flaky`
    # by muting the test fires its own `:muted` event for any alert
    # subscribed to `state_changed_to_muted`. Loop protection lives in
    # `Tuist.Automations.dispatch_test_case_event/2` (depth guard).
    Enum.each(event_types, fn event_type ->
      Automations.dispatch_test_case_event(event_type, test_case)
    end)
  end

  defp determine_test_case_events(old_test_case, new_attrs) do
    events = []

    events =
      case {Map.get(old_test_case, :is_flaky, false), Map.get(new_attrs, :is_flaky)} do
        {false, true} -> [:marked_flaky | events]
        {true, false} -> [:unmarked_flaky | events]
        _ -> events
      end

    events =
      case {Map.get(old_test_case, :state, "enabled"), Map.get(new_attrs, :state)} do
        {old_state, new_state} when old_state == new_state -> events
        {_old, nil} -> events
        {"muted", "enabled"} -> [:unmuted | events]
        {"skipped", "enabled"} -> [:unskipped | events]
        {_old, "muted"} -> [:muted | events]
        {_old, "skipped"} -> [:skipped | events]
        _ -> events
      end

    events
  end

  @doc """
  Lists test case events for a specific test case with pagination using Flop.
  Returns {events, meta} where meta is a Flop.Meta struct.
  """
  def list_test_case_events(test_case_id, attrs \\ %{}) do
    {events, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(
        from(e in TestCaseEvent, where: e.test_case_id == ^test_case_id),
        attrs,
        for: TestCaseEvent
      )

    events = Repo.preload(events, [:actor, :alert])
    {events, meta}
  end

  @doc """
  Lists test case runs with optional filters (e.g. test_case_id, test_run_id).
  Returns a tuple of {test_case_runs, meta} with pagination info.
  """
  def list_test_case_runs(attrs, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case extract_mv_scope_filter(attrs) do
      {:shard_id, _shard_id} ->
        list_test_case_runs_via_shard_mv(attrs, preloads)

      {:test_run_id, _test_run_id} ->
        list_test_case_runs_via_test_run_mv(attrs, preloads)

      {:test_case_id, _test_case_id} ->
        list_test_case_runs_from(from(tcr in TestCaseRun), attrs, preloads)

      {:project_id, _project_id} ->
        list_test_case_runs_via_project_mv(attrs, preloads)

      nil ->
        list_test_case_runs_from(from(tcr in TestCaseRun), attrs, preloads)
    end
  end

  defp list_test_case_runs_from(base_query, attrs, preloads) do
    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRun)

    results =
      results
      |> ClickHouseRepo.preload(preloads)
      |> Repo.preload(:ran_by_account)

    {results, meta}
  end

  defp list_test_case_runs_via_test_run_mv(attrs, preloads) do
    base_query = from(mv in TestCaseRunByTestRun, hints: ["FINAL"])

    {slim_results, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRunByTestRun)

    ids = Enum.map(slim_results, & &1.id)

    full_results = fetch_full_test_case_runs(slim_results)

    ordered_by_id = Map.new(full_results, &{&1.id, &1})
    ordered = ids |> Enum.map(&Map.get(ordered_by_id, &1)) |> Enum.reject(&is_nil/1)

    results =
      ordered
      |> ClickHouseRepo.preload(preloads)
      |> Repo.preload(:ran_by_account)

    {results, meta}
  end

  defp list_test_case_runs_via_shard_mv(attrs, preloads) do
    base_query = from(mv in TestCaseRunByShardId)

    {slim_results, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRunByShardId)

    ids = Enum.map(slim_results, & &1.id)

    full_results = fetch_full_test_case_runs(slim_results)

    ordered_by_id = Map.new(full_results, &{&1.id, &1})
    ordered = ids |> Enum.map(&Map.get(ordered_by_id, &1)) |> Enum.reject(&is_nil/1)

    results =
      ordered
      |> ClickHouseRepo.preload(preloads)
      |> Repo.preload(:ran_by_account)

    {results, meta}
  end

  defp list_test_case_runs_via_project_mv(attrs, preloads) do
    base_query = from(mv in TestCaseRunByProject, hints: ["FINAL"])

    {slim_results, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRunByProject)

    ids = Enum.map(slim_results, & &1.id)

    full_results = fetch_full_test_case_runs(slim_results)

    ordered_by_id = Map.new(full_results, &{&1.id, &1})
    ordered = ids |> Enum.map(&Map.get(ordered_by_id, &1)) |> Enum.reject(&is_nil/1)

    results =
      ordered
      |> ClickHouseRepo.preload(preloads)
      |> Repo.preload(:ran_by_account)

    {results, meta}
  end

  defp fetch_full_test_case_runs([]), do: []

  defp fetch_full_test_case_runs(slim_results) do
    ids = Enum.map(slim_results, & &1.id)

    {runs_with_test_case_id, runs_without_test_case_id} =
      Enum.split_with(slim_results, &(not is_nil(&1.test_case_id)))

    ids_without_test_case_id = Enum.map(runs_without_test_case_id, & &1.id)

    # `test_case_runs` is ordered by `(project_id, test_case_id, ran_at, id)`,
    # so hydrating by `id` alone reads the whole table. Correlating each run's
    # full primary key turns the hydration into one point read per run. Ecto
    # cannot compile a tuple `in` against an interpolated list, so the same
    # condition is expressed as an OR of per-run key equalities, which
    # ClickHouse still resolves through the primary key. Runs without a test
    # case id fall back to the id predicate because NULL never matches a key
    # comparison.
    key_condition =
      Enum.reduce(
        runs_with_test_case_id,
        dynamic([tcr], tcr.id in ^ids_without_test_case_id),
        fn run, acc ->
          dynamic(
            [tcr],
            ^acc or
              (tcr.project_id == ^run.project_id and tcr.test_case_id == ^run.test_case_id and
                 tcr.ran_at == ^run.ran_at and tcr.id == ^run.id)
          )
        end
      )

    base_query =
      from(tcr in TestCaseRun,
        where: ^key_condition,
        order_by: [desc: tcr.inserted_at]
      )

    results =
      case inserted_at_by_id(slim_results) do
        nil ->
          ClickHouseRepo.all(base_query)

        inserted_at_by_id ->
          inserted_ats = inserted_at_by_id |> Map.values() |> Enum.uniq()

          versioned_results =
            base_query
            |> where([tcr], tcr.inserted_at in ^inserted_ats)
            |> ClickHouseRepo.all()

          versioned_results =
            Enum.filter(versioned_results, fn result ->
              Map.fetch!(inserted_at_by_id, result.id) == result.inserted_at
            end)

          found_ids = MapSet.new(versioned_results, & &1.id)
          missing_ids = Enum.reject(ids, &MapSet.member?(found_ids, &1))

          missing_results =
            case missing_ids do
              [] ->
                []

              missing_ids ->
                base_query
                |> where([tcr], tcr.id in ^missing_ids)
                |> ClickHouseRepo.all()
            end

          versioned_results ++ missing_results
      end

    # `test_case_runs` is ReplacingMergeTree; re-inserts leave multiple
    # versions per id until background merges collapse them. The timestamp
    # filter normally selects the versions returned by the slim view and
    # prunes unrelated parts. Missing ids are retried without it so reads
    # remain correct if two replicas have temporarily different visibility.
    Enum.uniq_by(results, & &1.id)
  end

  defp inserted_at_by_id(slim_results) do
    versions = Enum.map(slim_results, &{&1.id, Map.get(&1, :inserted_at)})

    if Enum.all?(versions, fn {_id, inserted_at} -> not is_nil(inserted_at) end) do
      Map.new(versions)
    end
  end

  # Filter precedence for routing: a narrower scope wins so we use the
  # most-selective materialized view available. `test_case_id` keeps the main
  # table because callers also scope it by `project_id`, matching the primary
  # key prefix `(project_id, test_case_id)`. `project_id` falls through to the
  # project materialized view when no narrower scope is present; without it,
  # the listing query scans every row for the project.
  defp extract_mv_scope_filter(%{filters: filters}) when is_list(filters) do
    filters
    |> Enum.map(&filter_scope/1)
    |> pick_mv_scope()
  end

  defp extract_mv_scope_filter(%Flop{} = flop) do
    flop.filters
    |> List.wrap()
    |> Enum.map(&filter_scope/1)
    |> pick_mv_scope()
  end

  defp extract_mv_scope_filter(_), do: nil

  defp filter_scope(%{field: :test_run_id, op: :==, value: value}), do: {:test_run_id, value}
  defp filter_scope(%{field: :shard_id, op: :==, value: value}), do: {:shard_id, value}
  defp filter_scope(%{field: :test_case_id, op: :==, value: value}), do: {:test_case_id, value}
  defp filter_scope(%{field: :project_id, op: :==, value: value}), do: {:project_id, value}
  defp filter_scope(_), do: nil

  defp pick_mv_scope(scopes) do
    Enum.find_value([:test_run_id, :shard_id, :test_case_id, :project_id], fn key ->
      Enum.find(scopes, &match?({^key, _}, &1))
    end)
  end

  @doc """
  Gets a test case run by its UUID.
  Returns {:ok, test_case_run} or {:error, :not_found}.
  """
  def get_test_case_run_by_id(id, opts \\ []) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.id == ^id,
        limit: 1
      )

    query =
      case Keyword.get(opts, :project_id) do
        nil ->
          case uuidv7_to_yyyymm(id) do
            {:ok, month} ->
              where(query, [tcr], fragment("toYYYYMM(?)", tcr.inserted_at) == ^month)

            :error ->
              query
          end

        project_id ->
          query = where(query, [tcr], tcr.project_id == ^project_id)

          case uuidv7_to_yyyymm(id) do
            {:ok, month} ->
              where(query, [tcr], fragment("toYYYYMM(?)", tcr.inserted_at) == ^month)

            :error ->
              query
          end
      end

    case ClickHouseRepo.one(query) do
      nil ->
        {:error, :not_found}

      run ->
        preload = Keyword.get(opts, :preload, [])
        run = ClickHouseRepo.preload(run, preload)
        {:ok, run}
    end
  end

  # The test_case_runs table is partitioned by toYYYYMM(inserted_at). Without a
  # partition hint, the proj_by_id projection must check every part across all
  # monthly partitions (~93K rows read, ~2.7s p50 in production). UUIDv7 encodes
  # a millisecond timestamp in the first 48 bits, which closely matches
  # inserted_at, so we extract the month and add a toYYYYMM filter to prune all
  # but one partition (~8K rows read, ~35x improvement).
  defp uuidv7_to_yyyymm(uuid_string) do
    hex = uuid_string |> String.replace("-", "") |> String.slice(0, 12)
    timestamp_ms = String.to_integer(hex, 16)

    case DateTime.from_unix(timestamp_ms, :millisecond) do
      {:ok, datetime} -> {:ok, datetime.year * 100 + datetime.month}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp create_test_modules(test, test_modules, shard_index, shard_plan) do
    # Resolved once per run and threaded down rather than looked up where each
    # row is built: it decides `is_new` for every test case and
    # `is_default_branch` for every run row, and both used to mean a separate
    # Postgres round trip on a path that already runs per ingested test run.
    default_branch = project_default_branch(test.project_id)
    is_default_branch = default_branch?(test.git_branch, default_branch)

    test_case_run_data =
      OpenTelemetry.Tracer.with_span "tests.get_test_case_run_data" do
        get_test_case_run_data(test, test_modules, default_branch)
      end

    test_case_ids = collect_test_case_ids(test.project_id, test_modules)

    existing_test_cases =
      get_existing_test_cases(
        test.project_id,
        test_case_ids,
        flaky_run_test_case_ids(test.project_id, test_case_run_data)
      )

    test_case_run_data_by_module =
      Enum.group_by(
        test_case_run_data,
        fn {{_name, mod_name, _suite}, _data} -> mod_name end
      )

    test_modules
    |> Enum.flat_map_reduce([], fn module_attrs, acc_test_case_runs ->
      module_id = UUIDv7.generate()
      module_name = Map.get(module_attrs, :name)

      test_suites = Map.get(module_attrs, :test_suites, [])
      test_cases = Map.get(module_attrs, :test_cases, [])

      test_suite_count = length(test_suites)
      test_case_count = length(test_cases)

      avg_test_case_duration = calculate_avg_test_case_duration(test_cases)

      module_test_case_run_data =
        test_case_run_data_by_module
        |> Map.get(module_name, [])
        |> Map.new()

      module_is_flaky = any_test_case_run_flaky?(Map.values(module_test_case_run_data))

      module_run_attrs = %{
        id: module_id,
        name: module_name,
        test_run_id: test.id,
        status: Map.get(module_attrs, :status),
        is_flaky: module_is_flaky,
        duration: Map.get(module_attrs, :duration, 0),
        test_suite_count: test_suite_count,
        test_case_count: test_case_count,
        avg_test_case_duration: avg_test_case_duration,
        shard_id: if(shard_plan, do: shard_plan.id),
        shard_index: shard_index,
        project_id: test.project_id,
        is_ci: test.is_ci,
        git_branch: test.git_branch || "",
        ran_at: test.ran_at,
        inserted_at: NaiveDateTime.utc_now()
      }

      %TestModuleRun{}
      |> TestModuleRun.create_changeset(module_run_attrs)
      |> Ecto.Changeset.apply_action!(:insert)

      TestModuleRun.Buffer.insert(module_run_attrs)

      suite_name_to_id =
        create_test_suites(
          test,
          module_id,
          test_suites,
          test_cases,
          module_test_case_run_data,
          shard_plan,
          shard_index
        )

      {flaky_ids, test_case_runs} =
        create_test_cases_for_module(
          test,
          module_id,
          test_cases,
          suite_name_to_id,
          module_name,
          module_test_case_run_data,
          shard_plan,
          shard_index,
          existing_test_cases,
          is_default_branch
        )

      {flaky_ids, acc_test_case_runs ++ test_case_runs}
    end)
    |> tap(fn _ -> flush_test_case_run_buffers() end)
  end

  # One flush for the whole run rather than one per module.
  #
  # The client uploads attachments and crash reports as soon as it receives the
  # test case run IDs in the response, and those endpoints authorize each upload
  # against the run and its arguments. Both tables sit behind an ingestion
  # buffer that otherwise only flushes periodically, so the rows have to be
  # written through before the caller returns or the uploads race the flush and
  # are rejected as not found. Flushing here still satisfies that: every module
  # has been staged and this runs before `create_new_test/3` returns.
  #
  # Doing it per module was expensive out of proportion to what it bought.
  # ClickHouse insert cost on `test_case_runs` is almost entirely fixed
  # overhead (~480ms whether the batch is 52 rows or 25,515), and every buffer
  # is a single named process shared by every worker on the node, so each extra
  # flush blocked all of them for another round trip. Runs carry a median of 2
  # modules but a p90 of 134 and a maximum of 647, so the tail was paying
  # hundreds of serialized round trips to write data that one insert covers.
  defp flush_test_case_run_buffers do
    TestCaseRun.Buffer.flush()
    TestCaseRunArgument.Buffer.flush()
    :ok
  end

  defp get_test_case_run_data(test, test_modules, default_branch) do
    all_test_cases =
      Enum.flat_map(test_modules, fn module_attrs ->
        module_name = Map.get(module_attrs, :name)
        test_cases = Map.get(module_attrs, :test_cases, [])

        Enum.map(test_cases, fn case_attrs ->
          Map.put(case_attrs, :module_name, module_name)
        end)
      end)

    test_case_data =
      Enum.map(all_test_cases, fn case_attrs ->
        case_name = Map.get(case_attrs, :name)
        module_name = Map.get(case_attrs, :module_name)
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""
        test_case_id = generate_test_case_id(test.project_id, case_name, module_name, suite_name)

        %{
          identity_key: {case_name, module_name, suite_name},
          test_case_id: test_case_id,
          status: Map.get(case_attrs, :status),
          is_flaky: test_case_is_flaky?(case_attrs)
        }
      end)

    {test_case_data, historical_flaky_runs} =
      check_cross_run_flakiness(test, test_case_data)

    mark_test_case_runs_as_flaky(test.project_id, test.git_commit_sha, historical_flaky_runs)

    test_case_data = check_new_test_cases(test, test_case_data, default_branch)

    Map.new(test_case_data, fn data ->
      {data.identity_key, %{status: data.status, is_flaky: data.is_flaky, is_new: data.is_new}}
    end)
  end

  defp check_cross_run_flakiness(%{is_ci: false}, test_case_data), do: {test_case_data, []}
  defp check_cross_run_flakiness(%{git_commit_sha: nil}, test_case_data), do: {test_case_data, []}

  defp check_cross_run_flakiness(test, test_case_data) do
    test_case_ids = Enum.map(test_case_data, & &1.test_case_id)
    scheme = test.scheme || ""

    existing_runs =
      get_existing_ci_runs_for_commit(test_case_ids, test.git_commit_sha, test.project_id, scheme)

    Enum.map_reduce(test_case_data, [], fn data, historical_runs ->
      {data, flaky_failures} = resolve_cross_run_flaky_failures(data, existing_runs)
      {data, flaky_failures ++ historical_runs}
    end)
  end

  # A run is flaky only when it is a failure that the same test case also passed
  # on for the same commit and scheme — a failure that did not reproduce. The
  # passing runs that prove the test can succeed on the commit are left clean, so
  # flaky-run counts and rates reflect the spurious failures rather than every
  # execution of the commit.
  defp resolve_cross_run_flaky_failures(%{status: status} = data, _existing_runs)
       when status not in ["success", "failure"] do
    {data, []}
  end

  defp resolve_cross_run_flaky_failures(data, existing_runs) do
    existing = Map.get(existing_runs, data.test_case_id, [])
    {existing_successes, existing_failures} = Enum.split_with(existing, &(to_string(&1.status) == "success"))

    cond do
      # This run failed and the test already passed on the commit: the current
      # failure is the flake. Earlier failures were already flagged when their
      # passing sibling arrived, so there is nothing to back-mark.
      data.status == "failure" and existing_successes != [] ->
        {%{data | is_flaky: true}, []}

      # This run passed and the test already failed on the commit: those earlier
      # failures are now proven flaky, so back-mark them.
      data.status == "success" and existing_failures != [] ->
        {data, Enum.reject(existing_failures, & &1.is_flaky)}

      true ->
        {data, []}
    end
  end

  defp get_existing_ci_runs_for_commit([], _git_commit_sha, _project_id, _scheme), do: %{}

  defp get_existing_ci_runs_for_commit(test_case_ids, git_commit_sha, project_id, scheme) do
    test_case_id_set = MapSet.new(test_case_ids)

    query =
      from(tcr in TestCaseRunByCommit,
        where: tcr.project_id == ^project_id,
        where: tcr.git_commit_sha == ^git_commit_sha,
        where: tcr.scheme == ^scheme,
        where: tcr.is_ci == true,
        group_by: [tcr.id, tcr.test_case_id],
        select: %{
          id: tcr.id,
          test_case_id: tcr.test_case_id,
          status: fragment("argMax(?, ?)", tcr.status, tcr.inserted_at),
          is_flaky: fragment("argMax(?, ?)", tcr.is_flaky, tcr.inserted_at)
        }
      )

    query
    |> ClickHouseRepo.all()
    |> Enum.filter(fn run ->
      to_string(run.status) in ["success", "failure"] and run.test_case_id in test_case_id_set
    end)
    |> Enum.group_by(& &1.test_case_id)
  end

  defp check_new_test_cases(test, test_case_data, default_branch) do
    if is_nil(default_branch) do
      Enum.map(test_case_data, &Map.put(&1, :is_new, false))
    else
      existing_on_default_branch =
        get_test_case_ids_with_ci_runs_on_branch(test.project_id, default_branch)

      Enum.map(test_case_data, fn data ->
        is_new = data.test_case_id not in existing_on_default_branch
        Map.put(data, :is_new, is_new)
      end)
    end
  end

  defp project_default_branch(project_id) do
    project = Tuist.Projects.get_project_by_id(project_id)
    project && project.default_branch
  end

  # Classifying a run against the default branch is done here, at ingestion,
  # because the aggregates that need it are ClickHouse materialized views and
  # the default branch lives in Postgres. A view cannot reach across, so the
  # answer has to be denormalized onto the row while it is being written.
  #
  # A project that renames its default branch leaves the runs written before
  # the rename classified against the old name. Nothing rewrites them: the
  # aggregate this feeds is only ever read over a trailing window, so a rename
  # heals on its own once the window has moved past it, and the alternative is
  # rewriting a multi-billion-row fact table on a settings change.
  #
  # An unset default branch means no run is on it, which is the same answer the
  # listing gives for a project whose default branch simply never ran. The
  # empty string is not a branch name, so it never matches an unset column.
  defp default_branch?(_git_branch, nil), do: false
  defp default_branch?(_git_branch, ""), do: false
  defp default_branch?(git_branch, default_branch), do: git_branch == default_branch

  defp get_test_case_ids_with_ci_runs_on_branch(project_id, branch) do
    ninety_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -90, :day)

    from(bp in TestCaseBranchPresence,
      where: bp.project_id == ^project_id,
      where: bp.git_branch == ^branch,
      where: bp.is_ci == true,
      where: bp.ran_at >= ^ninety_days_ago,
      distinct: true,
      select: bp.test_case_id
    )
    |> ClickHouseRepo.all()
    |> MapSet.new()
  end

  # Chunk size for the default-branch validation lookup. An alert's triggered
  # set can be large (a `flakiness_rate < threshold` cleanup rule matches most
  # of a project's test cases, which can run into tens of thousands). The ids
  # travel as a single ClickHouse array parameter, so chunking keeps that
  # parameter's encoded value below ClickHouse's per-request limits.
  @default_branch_validation_batch_size 2_000

  @doc """
  Given a list of test case ids, returns the subset that has at least one
  successful, non-flaky run on the project's default branch. A test case with
  no such run has never been validated on the trusted branch (for example, a
  brand-new test that has only ever run on a pull-request branch) and should
  not be eligible for automated quarantine.
  """
  def test_case_ids_with_successful_default_branch_run(_project_id, [], _default_branch), do: []

  def test_case_ids_with_successful_default_branch_run(project_id, test_case_ids, default_branch) do
    test_case_ids
    |> Enum.chunk_every(@default_branch_validation_batch_size)
    |> Enum.flat_map(&fetch_validated_test_case_ids_chunk(project_id, &1, default_branch))
  end

  # Reads `test_case_runs_validated_on_branch`, a ReplacingMergeTree fed by the
  # `test_case_runs_validated_on_branch_mv` materialized view holding one marker
  # row per `(project_id, git_branch, test_case_id)` that has ever had a
  # successful, non-flaky run. Each test case collapses to a single row, so
  # validating a large triggered set is a bounded primary-key point lookup
  # instead of scanning every matching run of the raw `test_case_runs` table
  # (which, on busy projects, read millions of rows per evaluation).
  #
  # Binds the ids as a single `Array(UUID)` parameter via a fragment instead of
  # `v.test_case_id in ^ids_chunk`. `in` expands to one bound parameter per id,
  # which overflows ClickHouse's request limits when the triggered set is large.
  # `distinct` collapses any not-yet-merged duplicate marker rows; the schema is
  # borrowed from `TestCaseRun` purely to type the shared columns.
  defp fetch_validated_test_case_ids_chunk(project_id, ids_chunk, default_branch) do
    ClickHouseRepo.all(
      from(v in {"test_case_runs_validated_on_branch", TestCaseRun},
        where: v.project_id == ^project_id,
        where: v.git_branch == ^default_branch,
        where: fragment("? IN (?)", v.test_case_id, type(^ids_chunk, {:array, Ecto.UUID})),
        distinct: true,
        select: v.test_case_id
      ),
      multipart: true
    )
  end

  defp create_test_suites(test, module_id, test_suites, test_cases, test_case_run_data, shard_plan, shard_index) do
    test_cases_by_suite =
      Enum.group_by(test_cases, fn case_attrs ->
        Map.get(case_attrs, :test_suite_name, "")
      end)

    {test_suite_runs, suite_name_to_id} =
      Enum.map_reduce(test_suites, %{}, fn suite_attrs, acc ->
        suite_id = UUIDv7.generate()
        suite_name = Map.get(suite_attrs, :name)

        suite_test_cases = Map.get(test_cases_by_suite, suite_name, [])
        test_case_count = length(suite_test_cases)

        avg_test_case_duration = calculate_avg_test_case_duration(suite_test_cases)

        suite_data =
          test_case_run_data
          |> Enum.filter(fn {{_name, _module, suite}, _data} -> suite == suite_name end)
          |> Enum.map(fn {_key, data} -> data end)

        suite_is_flaky = any_test_case_run_flaky?(suite_data)

        suite_run = %{
          id: suite_id,
          name: suite_name,
          test_run_id: test.id,
          test_module_run_id: module_id,
          status: Map.get(suite_attrs, :status),
          is_flaky: suite_is_flaky,
          duration: Map.get(suite_attrs, :duration, 0),
          test_case_count: test_case_count,
          avg_test_case_duration: avg_test_case_duration,
          shard_id: if(shard_plan, do: shard_plan.id),
          shard_index: shard_index,
          project_id: test.project_id,
          is_ci: test.is_ci,
          git_branch: test.git_branch || "",
          ran_at: test.ran_at,
          inserted_at: NaiveDateTime.utc_now()
        }

        updated_mapping = Map.put(acc, suite_name, suite_id)
        {suite_run, updated_mapping}
      end)

    TestSuiteRun.Buffer.insert_all(test_suite_runs)
    suite_name_to_id
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.FunctionArity
  defp create_test_cases_for_module(
         test,
         module_id,
         test_cases,
         suite_name_to_id,
         module_name,
         test_case_run_data,
         shard_plan,
         shard_index,
         existing_test_cases,
         is_default_branch
       ) do
    test_case_data_list =
      test_cases
      |> Enum.map(fn case_attrs ->
        case_name = Map.get(case_attrs, :name)
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""
        identity_key = {case_name, module_name, suite_name}
        %{status: status, is_flaky: is_flaky} = Map.get(test_case_run_data, identity_key)

        %{
          name: case_name,
          module_name: module_name,
          suite_name: suite_name,
          status: status,
          is_flaky: is_flaky and test.is_ci,
          duration: Map.get(case_attrs, :duration, 0),
          ran_at: test.ran_at
        }
      end)
      |> Enum.uniq_by(fn data -> {data.name, data.module_name, data.suite_name} end)

    {test_case_id_map, test_case_ids_with_flaky_run, new_test_case_ids, test_cases_created} =
      create_test_cases(test.project_id, test_case_data_list, existing_test_cases,
        test_run_id: test.id,
        is_ci: test.is_ci
      )

    {test_case_runs, all_failures, all_repetitions, all_attachments, all_arguments} =
      Enum.reduce(test_cases, {[], [], [], [], []}, fn case_attrs,
                                                       {runs_acc, failures_acc, reps_acc, attachments_acc, args_acc} ->
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""

        test_suite_run_id = Map.get(suite_name_to_id, suite_name)

        test_case_run_id = UUIDv7.generate()

        case_name = Map.get(case_attrs, :name)
        identity_key = {case_name, module_name, suite_name}
        test_case_id = Map.get(test_case_id_map, identity_key)

        %{status: status, is_flaky: is_flaky, is_new: is_new} =
          Map.get(test_case_run_data, identity_key)

        test_case_run = %{
          id: test_case_run_id,
          name: case_name,
          test_run_id: test.id,
          test_module_run_id: module_id,
          test_suite_run_id: test_suite_run_id,
          test_case_id: test_case_id,
          project_id: test.project_id,
          is_ci: test.is_ci,
          scheme: test.scheme,
          account_id: test.account_id,
          ran_at: test.ran_at,
          git_branch: test.git_branch,
          is_default_branch: is_default_branch,
          git_commit_sha: test.git_commit_sha || "",
          status: status,
          is_flaky: is_flaky,
          is_new: is_new,
          is_quarantined: Map.get(case_attrs, :is_quarantined, false),
          duration: Map.get(case_attrs, :duration, 0),
          inserted_at: NaiveDateTime.utc_now(),
          module_name: module_name,
          suite_name: suite_name,
          shard_id: if(shard_plan, do: shard_plan.id),
          shard_index: shard_index
        }

        {test_case_run, arg_records, arg_failures, arg_repetitions} =
          build_argument_data(case_attrs, test_case_run_id, test_case_run)

        test_case_failures = build_failures(case_attrs, test_case_run_id)
        test_case_repetitions = build_repetitions(case_attrs, test_case_run_id)
        test_case_attachments = build_attachments(case_attrs, test_case_run_id, test.id)

        {
          [test_case_run | runs_acc],
          arg_failures ++ test_case_failures ++ failures_acc,
          arg_repetitions ++ test_case_repetitions ++ reps_acc,
          test_case_attachments ++ attachments_acc,
          arg_records ++ args_acc
        }
      end)

    # Buffered here, flushed once by `create_test_modules/4` after every module
    # has been staged. The rows still land before the caller returns, which is
    # what the attachment and crash-report endpoints depend on (see the flush
    # site), but a run no longer pays one round trip per module.
    TestCaseRun.Buffer.insert_all(test_case_runs)

    if Enum.any?(all_arguments) do
      TestCaseRunArgument.Buffer.insert_all(all_arguments)
    end

    Tuist.Tasks.run_async(fn ->
      TestCaseFailure.Buffer.insert_all(all_failures)

      if Enum.any?(all_repetitions) do
        TestCaseRunRepetition.Buffer.insert_all(all_repetitions)
      end

      if Enum.any?(all_attachments) do
        TestCaseRunAttachment.Buffer.insert_all(all_attachments)
      end

      enqueue_flaky_alert_evaluations(test, test_case_runs)
    end)

    # The audit-log row and the outbound webhook fire on the same set:
    # a test case whose row didn't exist before *and* whose run is the
    # first one on the default branch. `test_case.updated` derives both
    # signals from the same `event_types` list (see `update_test_case/3`);
    # `test_case.created` mirrors that by deriving both from a single
    # filtered run list here.
    first_run_test_case_runs = filter_first_run_test_case_runs(test_case_runs, new_test_case_ids)
    create_first_run_events(first_run_test_case_runs)
    dispatch_test_case_created_webhooks(test.project_id, test_cases_created, first_run_test_case_runs)

    {test_case_ids_with_flaky_run, test_case_runs}
  end

  defp build_argument_records(arguments, test_case_run_id) do
    now = NaiveDateTime.utc_now()

    Enum.reduce(arguments, {[], [], []}, fn arg_attrs, {args_acc, failures_acc, reps_acc} ->
      argument_id = UUIDv7.generate()

      arg_record = %{
        id: argument_id,
        test_case_run_id: test_case_run_id,
        name: Map.get(arg_attrs, :name),
        status: Map.get(arg_attrs, :status),
        duration: Map.get(arg_attrs, :duration, 0),
        inserted_at: now
      }

      arg_failures =
        arg_attrs
        |> Map.get(:failures, [])
        |> Enum.map(fn failure_attrs ->
          %{
            id: UUIDv7.generate(),
            test_case_run_id: test_case_run_id,
            test_case_run_argument_id: argument_id,
            message: Map.get(failure_attrs, :message),
            path: Map.get(failure_attrs, :path),
            line_number: Map.get(failure_attrs, :line_number),
            issue_type: Map.get(failure_attrs, :issue_type) || "unknown",
            inserted_at: now
          }
        end)

      arg_repetitions =
        arg_attrs
        |> Map.get(:repetitions, [])
        |> Enum.map(fn rep_attrs ->
          %{
            id: UUIDv7.generate(),
            test_case_run_id: test_case_run_id,
            test_case_run_argument_id: argument_id,
            repetition_number: Map.get(rep_attrs, :repetition_number),
            name: Map.get(rep_attrs, :name),
            status: Map.get(rep_attrs, :status),
            duration: Map.get(rep_attrs, :duration, 0),
            inserted_at: now
          }
        end)

      {[arg_record | args_acc], arg_failures ++ failures_acc, arg_repetitions ++ reps_acc}
    end)
  end

  defp build_argument_data(case_attrs, test_case_run_id, test_case_run) do
    arguments = Map.get(case_attrs, :arguments, [])

    {arg_records, arg_failures, arg_repetitions} =
      build_argument_records(arguments, test_case_run_id)

    test_case_run =
      if Enum.any?(arg_records) do
        Map.put(test_case_run, :arguments, Enum.map(arg_records, &Map.take(&1, [:id, :name])))
      else
        test_case_run
      end

    {test_case_run, arg_records, arg_failures, arg_repetitions}
  end

  defp build_failures(case_attrs, test_case_run_id) do
    case_attrs
    |> Map.get(:failures, [])
    |> Enum.map(fn failure_attrs ->
      %{
        id: UUIDv7.generate(),
        test_case_run_id: test_case_run_id,
        test_case_run_argument_id: nil,
        message: Map.get(failure_attrs, :message),
        path: Map.get(failure_attrs, :path),
        line_number: Map.get(failure_attrs, :line_number),
        issue_type: Map.get(failure_attrs, :issue_type) || "unknown",
        inserted_at: NaiveDateTime.utc_now()
      }
    end)
  end

  defp build_repetitions(case_attrs, test_case_run_id) do
    case_attrs
    |> Map.get(:repetitions, [])
    |> Enum.map(fn rep_attrs ->
      %{
        id: UUIDv7.generate(),
        test_case_run_id: test_case_run_id,
        test_case_run_argument_id: nil,
        repetition_number: Map.get(rep_attrs, :repetition_number),
        name: Map.get(rep_attrs, :name),
        status: Map.get(rep_attrs, :status),
        duration: Map.get(rep_attrs, :duration, 0),
        inserted_at: NaiveDateTime.utc_now()
      }
    end)
  end

  defp build_attachments(case_attrs, test_case_run_id, test_run_id) do
    case_attrs
    |> Map.get(:attachments, [])
    |> Enum.map(fn att_attrs ->
      %{
        id: Map.get(att_attrs, :attachment_id) || UUIDv7.generate(),
        test_case_run_id: test_case_run_id,
        test_case_run_argument_id: Map.get(att_attrs, :test_case_run_argument_id),
        test_run_id: test_run_id,
        file_name: Map.get(att_attrs, :file_name),
        repetition_number: Map.get(att_attrs, :repetition_number),
        inserted_at: NaiveDateTime.utc_now()
      }
    end)
  end

  # The intersection of "this test case row is brand-new" and "the run
  # is the first one observed on the default branch (in the last 90
  # days)". Both signals must agree before we call it a first run.
  defp filter_first_run_test_case_runs(test_case_runs, new_test_case_ids) do
    Enum.filter(test_case_runs, fn run ->
      run.is_new and run.test_case_id in new_test_case_ids
    end)
  end

  defp create_first_run_events([]), do: :ok

  defp create_first_run_events(first_run_test_case_runs) do
    now = NaiveDateTime.utc_now()

    events =
      Enum.map(first_run_test_case_runs, fn run ->
        %{
          id: TestCaseEvent.first_run_id(run.test_case_id),
          test_case_id: run.test_case_id,
          project_id: run.project_id,
          event_type: "first_run",
          actor_id: nil,
          alert_id: nil,
          inserted_at: now
        }
      end)

    TestCaseEvent.Buffer.insert_all(events)
  end

  # Webhook fan-out for the same set of test cases that get a `first_run`
  # audit-log row. The dispatcher swallows resolver / no-subscriber paths
  # and wraps the `Oban.insert_all/1` call in its own try/rescue, so this
  # function doesn't need an outer rescue — surfacing a real failure here
  # is more useful than silently logging it.
  defp dispatch_test_case_created_webhooks(_project_id, _test_cases, []), do: :ok

  defp dispatch_test_case_created_webhooks(project_id, test_cases, first_run_test_case_runs) do
    first_run_ids = MapSet.new(first_run_test_case_runs, & &1.test_case_id)
    new_test_cases = Enum.filter(test_cases, &MapSet.member?(first_run_ids, &1.id))
    Dispatcher.dispatch_test_case_created(project_id, new_test_cases)
    :ok
  end

  defp calculate_avg_test_case_duration(test_cases) do
    test_case_count = length(test_cases)

    if test_case_count > 0 do
      total_duration =
        Enum.reduce(test_cases, 0, fn case_attrs, acc ->
          acc + Map.get(case_attrs, :duration, 0)
        end)

      round(total_duration / test_case_count)
    else
      0
    end
  end

  @doc """
  Lists test cases for a project directly from the test_cases table.
  Denormalized fields (last_status, last_duration, last_ran_at) are kept up to date
  by ReplacingMergeTree on each test run.

  Options:
    * `:default_branch_only`: when `true`, the duration statistic covers only
      runs on the project's default branch. Defaults to `false`, which covers
      every branch. It deliberately does not narrow which test cases the
      listing returns: a test case that ran this fortnight is part of the
      suite whichever branch it ran on, and dropping rows would turn a
      question about durations into a question about membership.
    * `:is_ci`: scopes both "active" and the duration statistic to CI (`true`)
      or local (`false`) runs. Activity is read from the matching denormalized
      column on `test_cases`; the duration comes from the matching `is_ci`
      slice of `test_case_duration_daily_stats_per_case`. `nil` (the default)
      means "any environment".
    * `:preload`: which duration fields to compute, any of
      `:duration_p50_ms`, `:duration_p90_ms`, `:duration_p99_ms` and
      `:duration_avg_ms`.

  A preloaded field carries that statistic over the active window. Each is
  `nil` when the test case has fewer than `#{@min_duration_samples}` runs in the
  window, and `:duration_sample_count` comes along with any of them, since a
  caller that gets `nil` needs to know how many runs there were. Sort by them
  with the matching `:duration_p50` / `:duration_p90` / `:duration_p99` /
  `:duration_avg` fields, which order on the same values. Together they replace
  `:avg_duration`, the denormalized mean of the last 50 runs that is unbounded
  in time and blind to environment, as what the dashboard shows and ranks by.
  `:avg_duration` is still populated for the public API and MCP tool, which
  expose the column by name.

  Each statistic costs a merge across the project's whole active suite, so
  callers ask for the ones they render rather than the set: the Test Cases
  table takes all four, the "Slowest test cases" card takes only the median.
  Ordering by a duration field also computes it, since the ordering reads the
  alias the computation puts in the SELECT. Callers that do neither, namely the
  public API and the MCP tool, run exactly the query they ran before.

  The listing intentionally has no date-window option. Callers that take a
  user-controlled date picker on the same page (e.g. the Test Cases LiveView)
  show analytics for the picked range while the table stays anchored to the
  trailing `@active_window_days` window — that way the table is a stable
  view of the project's active surface and never silently drops rows because
  a custom historical range excluded their most recent run. The duration
  statistic is bounded to that same window, so it covers exactly the runs that
  decide whether a row appears at all.
  """
  def list_test_cases(project_id, attrs, opts \\ []) do
    filters = Map.get(attrs, :filters, [])
    has_name_filter = Enum.any?(filters, fn f -> f.field == :name end)
    quarantine_filter? = quarantine_filter?(filters)
    is_ci = Keyword.get(opts, :is_ci)
    default_branch_only = Keyword.get(opts, :default_branch_only, false)
    duration_fields = requested_duration_fields(opts, attrs)

    # `state` / `is_flaky` are resolved from `test_case_states`, not from the
    # legacy columns on `test_cases`, so they are pulled out of the Flop filter
    # set and applied by hand below.
    {control_plane_filters, flop_filters} = Enum.split_with(filters, &control_plane_filter?/1)
    attrs = Map.put(attrs, :filters, flop_filters)

    {state_filter_mode, resolved_states} =
      state_filter_mode(project_id, control_plane_filters)

    base_query =
      case state_filter_mode do
        :joined ->
          from(test_case in TestCase,
            hints: ["FINAL"],
            left_join: test_case_state in subquery(test_case_states_subquery(project_id)),
            as: :test_case_state,
            on: test_case.id == test_case_state.test_case_id,
            where: test_case.project_id == ^project_id
          )

        :preloaded ->
          from(test_case in TestCase,
            hints: ["FINAL"],
            where: test_case.project_id == ^project_id
          )
      end

    base_query =
      case state_filter_mode do
        :joined ->
          Enum.reduce(control_plane_filters, base_query, &apply_joined_control_plane_filter/2)

        :preloaded ->
          apply_preloaded_control_plane_filters(
            control_plane_filters,
            base_query,
            resolved_states
          )
      end

    base_query =
      cond do
        # Quarantined-by-state filters (`state in ["muted", "skipped"]` or the
        # legacy `quarantined=true` shortcut) bypass the active window. Skipped
        # tests intentionally never run, so their `last_ran_at` doesn't
        # refresh — without this branch they'd age out after 14 days and the
        # CLI/Gradle plugin would silently start running them again.
        quarantine_filter? ->
          base_query

        has_name_filter ->
          base_query

        true ->
          apply_active_window(base_query, is_ci)
      end

    flop = Tuist.ClickHouseFlop.validate!(attrs, for: TestCase)

    query_settings =
      if state_filter_mode == :joined do
        @test_case_state_join_settings
      else
        []
      end

    # The duration join is added after the count: the count only needs the
    # filtered `test_cases` rows, and the aggregate scan behind the join would
    # be pure overhead there.
    total_count = test_cases_count(base_query, flop, query_settings)

    case state_filter_mode do
      :joined ->
        base_query
        |> select_resolved_test_case_state()
        |> select_durations(project_id, duration_fields, is_ci, default_branch_only)
        |> Tuist.ClickHouseFlop.run(flop,
          for: TestCase,
          count: total_count,
          query_opts: [settings: query_settings]
        )

      :preloaded ->
        {test_cases, meta} =
          base_query
          |> select_durations(project_id, duration_fields, is_ci, default_branch_only)
          |> Tuist.ClickHouseFlop.run(flop,
            for: TestCase,
            count: total_count,
            query_opts: [settings: @duration_join_settings]
          )

        resolved_page_states =
          resolve_test_case_states(project_id, Enum.map(test_cases, & &1.id))

        test_cases =
          Enum.map(test_cases, fn test_case ->
            resolved = Map.get(resolved_page_states, test_case.id, @default_test_case_state)
            apply_test_case_state(test_case, resolved)
          end)

        {test_cases, meta}
    end
  end

  @doc """
  Duration fields `list_test_cases/3` can compute and sort by.
  """
  def duration_fields, do: @duration_fields

  @doc """
  Runs a test case needs inside the active window before `list_test_cases/3`
  reports durations for it.
  """
  def min_duration_samples, do: @min_duration_samples

  # A field is computed when the caller preloads it by the name it is read under
  # (`:duration_p90_ms`) or orders by the name it sorts under (`:duration_p90`).
  # The second is not a convenience: the ordering reads the alias this puts in
  # the SELECT, so ordering without computing would build an ORDER BY over a
  # name ClickHouse cannot resolve.
  #
  # Flop accepts both atom and string params, so an order can arrive either way.
  defp requested_duration_fields(opts, attrs) do
    preloaded = to_string_set(Keyword.get(opts, :preload, []))
    ordered = to_string_set(Map.get(attrs, :order_by) || Map.get(attrs, "order_by"))

    Enum.filter(@duration_fields, fn field ->
      MapSet.member?(preloaded, "#{field}_ms") or MapSet.member?(ordered, to_string(field))
    end)
  end

  defp to_string_set(value), do: MapSet.new(List.wrap(value), &to_string/1)

  # Each statistic is aliased with `selected_as/2` so `Tuist.ClickHouseFlop` can
  # order by it even though it lives in a different table than `test_cases`.
  # `NULL` below the sample floor is what makes the unranked rows sortable:
  # `:asc_nulls_last` / `:desc_nulls_last` then keeps them at the bottom
  # whichever column and direction is chosen, instead of a sentinel that would
  # put them first in one direction.
  #
  # The join is `left_join`: a test case is in the listing because it ran inside
  # the active window in the selected environment, which does not guarantee it
  # cleared the sample floor, and an inner join would drop those rows from the
  # table entirely rather than showing them unranked.
  defp select_durations(query, _project_id, [], _is_ci, _default_branch_only), do: query

  defp select_durations(query, project_id, duration_fields, is_ci, default_branch_only) do
    stats =
      test_case_duration_stats_subquery(project_id, duration_fields, is_ci, default_branch_only)

    fields = Map.new(duration_fields, &{:"#{&1}_ms", guarded_duration_dynamic(&1)})

    fields =
      Map.put(
        fields,
        :duration_sample_count,
        dynamic([duration_stats: duration_stats], duration_stats.run_count)
      )

    from(test_case in query,
      left_join: duration_stats in subquery(stats),
      as: :duration_stats,
      on: test_case.id == duration_stats.test_case_id,
      select_merge: ^fields
    )
  end

  defp guarded_duration_dynamic(field) do
    dynamic(
      [duration_stats: duration_stats],
      selected_as(
        fragment(
          "if(? >= ?, ?, NULL)",
          duration_stats.run_count,
          ^@min_duration_samples,
          field(duration_stats, ^field)
        ),
        ^field
      )
    )
  end

  # One clause per statistic rather than an interpolated expression: a fragment
  # takes SQL at compile time, and `literal/1` would render the whole call as a
  # quoted identifier.
  defp duration_merge_dynamic(:duration_p50), do: dynamic(fragment("round(quantileMerge(0.5)(p50_duration))"))

  defp duration_merge_dynamic(:duration_p90), do: dynamic(fragment("round(quantileMerge(0.9)(p90_duration))"))

  defp duration_merge_dynamic(:duration_p99), do: dynamic(fragment("round(quantileMerge(0.99)(p99_duration))"))

  defp duration_merge_dynamic(:duration_avg), do: dynamic(fragment("round(avgMerge(avg_duration))"))

  # ClickHouse fills the missing side of a LEFT JOIN with each type's default
  # rather than NULL, so a test case with no rows here arrives as
  # `run_count = 0` and is handled by the sample floor like any other
  # under-sampled row.
  defp test_case_duration_stats_subquery(project_id, duration_fields, is_ci, default_branch_only) do
    window_start = active_window_start_date()

    fields = Map.new(duration_fields, &{&1, duration_merge_dynamic(&1)})

    fields =
      fields
      |> Map.put(:test_case_id, dynamic([stats], stats.test_case_id))
      |> Map.put(:run_count, dynamic(fragment("uniqExactMerge(run_count)")))

    query =
      from(stats in TestCaseDurationDailyStatsPerCase,
        where: stats.project_id == ^project_id,
        where: stats.date >= ^window_start,
        group_by: stats.test_case_id,
        select: ^fields
      )

    query
    |> apply_duration_environment_filter(is_ci)
    |> apply_duration_branch_filter(default_branch_only)
  end

  defp apply_duration_environment_filter(query, nil), do: query

  defp apply_duration_environment_filter(query, is_ci), do: where(query, [stats], stats.is_ci == ^is_ci)

  # There is deliberately no fallback to every branch when a test case has no
  # default-branch runs. `Analytics.test_case_reliability_by_id/4` does fall
  # back, and for a success rate that is harmless. For a duration it is the
  # opposite of harmless: the rows with no default-branch runs are exactly the
  # ones whose all-branch figure is a feature-branch outlier, so falling back
  # would redisplay the number this scoping exists to remove, and do it
  # silently. Such a row instead drops below the sample floor, renders as "not
  # enough runs", and sorts last in either direction.
  defp apply_duration_branch_filter(query, false), do: query

  defp apply_duration_branch_filter(query, true), do: where(query, [stats], stats.is_default_branch == true)

  defp state_filter_mode(_project_id, []), do: {:preloaded, %{}}

  defp state_filter_mode(project_id, _control_plane_filters) do
    test_case_ids =
      ClickHouseRepo.all(
        from(state in TestCaseCurrentState,
          where: state.project_id == ^project_id,
          group_by: state.test_case_id,
          order_by: [asc: state.test_case_id],
          limit: @max_preloaded_test_case_states + 1,
          select: state.test_case_id
        ),
        settings: @test_case_state_probe_settings
      )

    if length(test_case_ids) <= @max_preloaded_test_case_states do
      {:preloaded, resolve_test_case_states(project_id, test_case_ids)}
    else
      {:joined, %{}}
    end
  end

  # Two different nulls collapse to the same answer here. A test case with no
  # `test_case_states` row at all gets null from the LEFT JOIN, and one whose
  # rows only ever set the *other* column gets null out of `argMaxIf`. Both mean
  # "never touched", so both resolve to the defaults. Every comparison against
  # these columns has to go through the same `ifNull`, because a null would
  # otherwise make the predicate null and silently drop the row.
  defp select_resolved_test_case_state(query) do
    from([test_case, test_case_state: state] in query,
      select_merge: %{
        state: fragment("ifNull(?, 'enabled')", state.state),
        is_flaky: fragment("ifNull(?, false)", state.is_flaky)
      }
    )
  end

  defp control_plane_filter?(filter) do
    control_plane_filter_field(filter) != nil
  end

  defp control_plane_filter_field(%{field: field}) when field in [:state, "state"], do: :state
  defp control_plane_filter_field(%{field: field}) when field in [:is_flaky, "is_flaky"], do: :is_flaky
  defp control_plane_filter_field(_filter), do: nil

  # Only the operators the callers actually build: `:==` / `:!=` from the
  # dashboard's option filter, `:==` / `:in` from the API's `state` and
  # `quarantined` params. Anything else matches nothing rather than silently
  # degrading to equality, which would invert the meaning of a negated filter.
  defp apply_preloaded_control_plane_filters(filters, query, resolved_states) do
    case control_plane_filter_matchers(filters) do
      {:ok, matchers} ->
        matcher = fn state -> Enum.all?(matchers, & &1.(state)) end
        default_matches? = matcher.(@default_test_case_state)

        {matching_ids, non_matching_ids} =
          Enum.reduce(resolved_states, {[], []}, fn {test_case_id, state}, {matching, non_matching} ->
            if matcher.(state) do
              {[test_case_id | matching], non_matching}
            else
              {matching, [test_case_id | non_matching]}
            end
          end)

        apply_resolved_state_ids(query, default_matches?, matching_ids, non_matching_ids)

      :error ->
        where(query, false)
    end
  end

  defp control_plane_filter_matchers(filters) do
    Enum.reduce_while(filters, {:ok, []}, fn filter, {:ok, matchers} ->
      case control_plane_filter_matcher(filter) do
        {:ok, matcher} ->
          {:cont, {:ok, [matcher | matchers]}}

        :error ->
          log_unsupported_control_plane_filter(filter)
          {:halt, :error}
      end
    end)
  end

  defp control_plane_filter_matcher(filter) do
    op = Map.get(filter, :op, :==)
    value = Map.get(filter, :value)

    case {control_plane_filter_field(filter), op} do
      {:state, :in} ->
        values = List.wrap(value)
        {:ok, &Enum.member?(values, &1.state)}

      {:state, :not_in} ->
        values = List.wrap(value)
        {:ok, &(not Enum.member?(values, &1.state))}

      {:state, :==} ->
        {:ok, &(&1.state == value)}

      {:state, :!=} ->
        {:ok, &(&1.state != value)}

      {:is_flaky, :==} ->
        {:ok, &(&1.is_flaky == value)}

      {:is_flaky, :!=} ->
        {:ok, &(&1.is_flaky != value)}

      {_field, _op} ->
        :error
    end
  end

  defp apply_resolved_state_ids(query, true, _matching_ids, []), do: query

  defp apply_resolved_state_ids(query, true, _matching_ids, non_matching_ids),
    do: where(query, [test_case], test_case.id not in ^non_matching_ids)

  defp apply_resolved_state_ids(query, false, [], _non_matching_ids), do: where(query, false)

  defp apply_resolved_state_ids(query, false, matching_ids, _non_matching_ids),
    do: where(query, [test_case], test_case.id in ^matching_ids)

  defp apply_joined_control_plane_filter(filter, query) do
    op = Map.get(filter, :op, :==)
    value = Map.get(filter, :value)

    case {control_plane_filter_field(filter), op} do
      {:state, :in} ->
        where(
          query,
          [test_case_state: state],
          fragment(
            "ifNull(?, 'enabled') IN (?)",
            state.state,
            type(^List.wrap(value), {:array, :string})
          )
        )

      {:state, :not_in} ->
        where(
          query,
          [test_case_state: state],
          fragment(
            "ifNull(?, 'enabled') NOT IN (?)",
            state.state,
            type(^List.wrap(value), {:array, :string})
          )
        )

      {:state, :==} ->
        where(
          query,
          [test_case_state: state],
          fragment("ifNull(?, 'enabled') = ?", state.state, type(^value, :string))
        )

      {:state, :!=} ->
        where(
          query,
          [test_case_state: state],
          fragment("ifNull(?, 'enabled') != ?", state.state, type(^value, :string))
        )

      {:is_flaky, :==} ->
        where(query, [test_case_state: state], fragment("ifNull(?, false) = ?", state.is_flaky, ^value))

      {:is_flaky, :!=} ->
        where(query, [test_case_state: state], fragment("ifNull(?, false) != ?", state.is_flaky, ^value))

      {field, op} ->
        log_unsupported_control_plane_filter(%{field: field, op: op})
        where(query, false)
    end
  end

  defp log_unsupported_control_plane_filter(filter) do
    field = control_plane_filter_field(filter)
    op = Map.get(filter, :op, :==)

    # Neither the dashboard nor the public API builds anything else: the
    # trait filter's dropdown only offers `:==` and `:!=`, and the API
    # hard-codes `:==` and `:in`. A hand-edited query string can still
    # smuggle one of the other Noora operators through, because the
    # operator whitelist there isn't narrowed to the filter's type. Match
    # nothing rather than raising: this runs inside the listing's
    # `assign_async`, where an exception surfaces as an empty table anyway,
    # only with a crashed task and the error noise that comes with it.
    Logger.warning("Ignoring test case #{field} filter with unsupported operator #{inspect(op)}")
  end

  defp test_cases_count(query, flop, query_settings) do
    query
    |> Tuist.ClickHouseFlop.filter(flop, for: TestCase)
    |> select([test_case], count(test_case.id))
    |> ClickHouseRepo.one(settings: query_settings)
  end

  defp quarantine_filter?(filters) do
    Enum.any?(filters, fn
      %{field: :state, value: value} when value in ["muted", "skipped"] ->
        true

      %{field: "state", value: value} when value in ["muted", "skipped"] ->
        true

      %{field: :state, op: :in, value: values} when is_list(values) ->
        Enum.any?(values, &(&1 in ["muted", "skipped"]))

      %{field: "state", op: :in, value: values} when is_list(values) ->
        Enum.any?(values, &(&1 in ["muted", "skipped"]))

      _ ->
        false
    end)
  end

  # The window starts at midnight rather than at an instant `@active_window_days`
  # x 24 hours ago, because the per-case duration aggregates are keyed by day and
  # cannot express a cutoff inside one. Both halves of the listing therefore mean
  # the same window: a row is admitted on exactly the runs its durations are
  # computed from. The alternative, a timestamp for admission and a whole
  # boundary day for durations, let a row be ranked on up to a day of runs that
  # the window itself would not have admitted.
  defp active_window_start_date, do: Date.add(Date.utc_today(), -@active_window_days)

  # `last_ran_at_ci` and `last_ran_at_local` are denormalized on `test_cases`
  # (kept current by `create_test_cases/4`'s read-modify-write merge per
  # test_case_id). Reading them directly — no `test_case_runs` join —
  # replaces what used to be a ~94 M row / 4 GB scan on production for one
  # project. Only the lower bound is checked: a test that ran once inside
  # the window and many times since still has its latest timestamp ≥
  # window_start, so it correctly stays in the listing.
  defp apply_active_window(query, is_ci) do
    window_start = NaiveDateTime.new!(active_window_start_date(), ~T[00:00:00])

    case is_ci do
      true ->
        where(query, [test_case], test_case.last_ran_at_ci >= ^window_start)

      false ->
        where(query, [test_case], test_case.last_ran_at_local >= ^window_start)

      _ ->
        where(query, [test_case], test_case.last_ran_at >= ^window_start)
    end
  end

  @doc """
  Lists test cases that are marked as flaky for a project.
  Queries test_cases where is_flaky = true and joins with test_case_runs for aggregated stats.
  """
  def list_flaky_test_cases(project_id, attrs, opts \\ []) do
    page = Map.get(attrs, :page, 1)
    page_size = Map.get(attrs, :page_size, 20)
    order_by = attrs |> Map.get(:order_by, [:flaky_runs_count]) |> List.first()
    order_direction = attrs |> Map.get(:order_directions, [:desc]) |> List.first()
    filters = Map.get(attrs, :filters, [])
    offset = (page - 1) * page_size

    search_term = extract_search_term(filters)

    results =
      project_id
      |> build_flaky_test_cases_query(search_term, opts)
      |> apply_flaky_order(order_by, order_direction)
      |> from(limit: ^page_size, offset: ^offset)
      |> ClickHouseRepo.all()

    flaky_tests = Enum.map(results, &row_to_flaky_test_case/1)

    total_count =
      project_id
      |> build_flaky_test_cases_count_query(search_term, opts)
      |> ClickHouseRepo.one()

    total_pages = if total_count > 0, do: ceil(total_count / page_size), else: 0

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    }

    {flaky_tests, meta}
  end

  defp extract_search_term(filters) do
    search_filter = Enum.find(filters, fn f -> f[:field] == :name and f[:op] == :ilike_and end)
    if search_filter, do: search_filter[:value]
  end

  # The flaky-stats join is `left_join`, not `inner_join`: a test case can be
  # currently flagged flaky (per `test_case_events`) without having any
  # `flaky_test_case_runs` rows in the analytics window — for example a
  # low-frequency test that was auto-flagged a while ago and hasn't run since,
  # or a test whose recent flaky runs sit in a different `:is_ci` segment.
  # `inner_join` here would silently drop such rows and put the list out of
  # sync with the analytics card, which counts purely off events.
  defp build_flaky_test_cases_query(project_id, search_term, opts) do
    base_query =
      from(test_case in TestCase,
        hints: ["FINAL"],
        inner_join: flaky in subquery(currently_flaky_test_case_ids_subquery(project_id, opts)),
        on: test_case.id == flaky.test_case_id,
        left_join: stats in subquery(flaky_stats_subquery(project_id, opts)),
        on: test_case.id == stats.test_case_id,
        where: test_case.project_id == ^project_id,
        select: %{
          id: test_case.id,
          name: test_case.name,
          module_name: test_case.module_name,
          suite_name: test_case.suite_name,
          marked_flaky_at: flaky.marked_flaky_at,
          flaky_runs_count: coalesce(stats.flaky_runs_count, 0),
          # ClickHouse's LEFT JOIN fills missing rows with each type's
          # zero value rather than NULL. `nullIf` collapses those zero
          # sentinels back to NULL so the consumer doesn't render
          # `1970-01-01` / `00000000-…` for stale-flagged tests.
          last_flaky_at: fragment("nullIf(?, toDateTime64(0, 6))", stats.last_flaky_at),
          last_flaky_run_id:
            fragment(
              "nullIf(?, toUUID('00000000-0000-0000-0000-000000000000'))",
              stats.last_flaky_run_id
            )
        }
      )

    apply_name_search(base_query, search_term)
  end

  defp build_flaky_test_cases_count_query(project_id, search_term, opts) do
    base_query =
      from(test_case in TestCase,
        hints: ["FINAL"],
        inner_join: flaky in subquery(currently_flaky_test_case_ids_subquery(project_id, opts)),
        on: test_case.id == flaky.test_case_id,
        left_join: stats in subquery(flaky_stats_subquery(project_id, opts)),
        on: test_case.id == stats.test_case_id,
        where: test_case.project_id == ^project_id,
        select: count(test_case.id)
      )

    apply_name_search(base_query, search_term)
  end

  defp flaky_stats_subquery(project_id, opts) do
    from(flaky_run in FlakyTestCaseRun,
      where: flaky_run.project_id == ^project_id,
      group_by: flaky_run.test_case_id,
      select: %{
        test_case_id: flaky_run.test_case_id,
        flaky_runs_count: count(flaky_run.test_case_id),
        last_flaky_at: max(flaky_run.inserted_at),
        last_flaky_run_id: fragment("argMax(test_run_id, inserted_at)")
      }
    )
    |> apply_flaky_time_filter(opts)
    |> apply_flaky_environment_filter(opts)
  end

  defp currently_flaky_test_case_ids_subquery(project_id, opts) do
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    end_naive = DateTime.to_naive(end_datetime)

    project_tc_ids =
      from(tc in TestCase,
        where: tc.project_id == ^project_id,
        select: tc.id
      )

    from(e in TestCaseEvent,
      where: e.event_type in ["marked_flaky", "unmarked_flaky"],
      where: e.inserted_at <= ^end_naive,
      where: e.test_case_id in subquery(project_tc_ids),
      group_by: e.test_case_id,
      having: fragment("argMax(?, ?) = 'marked_flaky'", e.event_type, e.inserted_at),
      # The `having` guarantees the latest event is `marked_flaky`, so the max
      # timestamp is the moment the test case entered its current flaky state.
      select: %{test_case_id: e.test_case_id, marked_flaky_at: max(e.inserted_at)}
    )
  end

  defp apply_flaky_time_filter(query, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)

    query
    |> then(fn q ->
      if start_datetime do
        naive = DateTime.to_naive(start_datetime)
        from(r in q, where: r.ran_at >= ^naive)
      else
        q
      end
    end)
    |> then(fn q ->
      if end_datetime do
        naive = DateTime.to_naive(end_datetime)
        from(r in q, where: r.ran_at <= ^naive)
      else
        q
      end
    end)
  end

  defp apply_flaky_environment_filter(query, opts) do
    case Keyword.get(opts, :is_ci) do
      nil -> query
      true -> from(r in query, where: r.is_ci == true)
      false -> from(r in query, where: r.is_ci == false)
    end
  end

  defp apply_name_search(query, nil), do: query
  defp apply_name_search(query, term), do: from(q in query, where: ilike(q.name, ^"%#{term}%"))

  defp apply_flaky_order(query, :flaky_runs_count, :asc),
    do: from([tc, _flaky, stats] in query, order_by: [asc: coalesce(stats.flaky_runs_count, 0)])

  defp apply_flaky_order(query, :last_flaky_at, :desc),
    do: from([tc, _flaky, stats] in query, order_by: [desc: stats.last_flaky_at])

  defp apply_flaky_order(query, :last_flaky_at, :asc),
    do: from([tc, _flaky, stats] in query, order_by: [asc: stats.last_flaky_at])

  defp apply_flaky_order(query, :name, :desc), do: from([tc, _flaky, _stats] in query, order_by: [desc: tc.name])

  defp apply_flaky_order(query, :name, :asc), do: from([tc, _flaky, _stats] in query, order_by: [asc: tc.name])

  defp apply_flaky_order(query, :marked_flaky_at, :desc),
    do: from([tc, flaky, _stats] in query, order_by: [desc: flaky.marked_flaky_at, asc: tc.id])

  defp apply_flaky_order(query, :marked_flaky_at, :asc),
    do: from([tc, flaky, _stats] in query, order_by: [asc: flaky.marked_flaky_at, asc: tc.id])

  defp apply_flaky_order(query, _, _),
    do: from([tc, _flaky, stats] in query, order_by: [desc: coalesce(stats.flaky_runs_count, 0)])

  defp row_to_flaky_test_case(row) do
    %FlakyTestCase{
      id: row.id,
      name: row.name,
      module_name: row.module_name,
      suite_name: row.suite_name,
      marked_flaky_at: row.marked_flaky_at,
      flaky_runs_count: row.flaky_runs_count,
      last_flaky_at: row.last_flaky_at,
      last_flaky_run_id: row.last_flaky_run_id
    }
  end

  @doc """
  Lists test cases that are currently quarantined for a project.
  Returns quarantined test cases with information about who quarantined them.
  """
  def list_quarantined_test_cases(project_id, attrs, _opts \\ []) do
    page = Map.get(attrs, :page, 1)
    page_size = Map.get(attrs, :page_size, 20)
    order_by = attrs |> Map.get(:order_by, [:last_ran_at]) |> List.first()
    order_direction = attrs |> Map.get(:order_directions, [:desc]) |> List.first()
    filters = Map.get(attrs, :filters, [])
    offset = (page - 1) * page_size

    search_term = extract_search_term(filters)
    quarantined_by_filter = extract_quarantined_by_filter(filters)
    module_name_filter = extract_text_filter(filters, :module_name)
    suite_name_filter = extract_text_filter(filters, :suite_name)
    state_filter = extract_state_filter(filters)

    results =
      project_id
      |> build_quarantined_test_cases_query(
        search_term,
        quarantined_by_filter,
        module_name_filter,
        suite_name_filter,
        state_filter
      )
      |> apply_quarantined_order(order_by, order_direction)
      |> from(limit: ^page_size, offset: ^offset)
      |> ClickHouseRepo.all()

    account_names = get_actor_account_names(results)

    quarantined_tests = Enum.map(results, &row_to_quarantined_test_case(&1, account_names))

    total_count =
      project_id
      |> build_quarantined_test_cases_count_query(
        search_term,
        quarantined_by_filter,
        module_name_filter,
        suite_name_filter,
        state_filter
      )
      |> ClickHouseRepo.one()

    total_pages = if total_count > 0, do: ceil(total_count / page_size), else: 0

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    }

    {quarantined_tests, meta}
  end

  defp extract_quarantined_by_filter(filters) do
    Enum.find_value(filters, fn
      %{field: :quarantined_by, op: op, value: value} -> {op, value}
      _ -> nil
    end)
  end

  defp extract_text_filter(filters, field) do
    field_string = to_string(field)

    Enum.find_value(filters, fn
      %{field: f, value: value} when is_binary(value) and value != "" ->
        if to_string(f) == field_string, do: value

      _ ->
        nil
    end)
  end

  defp extract_state_filter(filters) do
    Enum.find_value(filters, fn
      %{field: :state, value: value} when value in @active_quarantine_states -> value
      %{field: "state", value: value} when value in @active_quarantine_states -> value
      _ -> nil
    end)
  end

  defp build_quarantined_test_cases_query(
         project_id,
         search_term,
         quarantined_by_filter,
         module_name_filter,
         suite_name_filter,
         state_filter
       ) do
    from(test_case in TestCase,
      as: :test_case,
      hints: ["FINAL"],
      inner_join: quarantined in subquery(quarantined_test_case_states_subquery(project_id, state_filter)),
      as: :test_case_state,
      on: test_case.id == quarantined.test_case_id,
      left_join: quarantine in subquery(quarantine_info_subquery(project_id)),
      as: :quarantine,
      on: test_case.id == quarantine.test_case_id,
      where: test_case.project_id == ^project_id,
      select: %{
        id: test_case.id,
        name: test_case.name,
        module_name: test_case.module_name,
        suite_name: test_case.suite_name,
        last_ran_at: test_case.last_ran_at,
        last_run_id: test_case.last_run_id,
        last_status: test_case.last_status,
        state: quarantined.state,
        quarantined_by_account_id: quarantine.actor_id,
        # ClickHouse's LEFT JOIN zero-fills non-nullable columns, so a test
        # case without quarantine events would surface as `1970-01-01`.
        quarantined_at: fragment("nullIf(?, toDateTime64(0, 6))", quarantine.quarantined_at)
      }
    )
    |> apply_name_search(search_term)
    |> apply_quarantined_by_filter(quarantined_by_filter)
    |> apply_module_name_filter(module_name_filter)
    |> apply_suite_name_filter(suite_name_filter)
  end

  defp build_quarantined_test_cases_count_query(
         project_id,
         search_term,
         quarantined_by_filter,
         module_name_filter,
         suite_name_filter,
         state_filter
       ) do
    base_query =
      from(test_case in TestCase,
        as: :test_case,
        hints: ["FINAL"],
        inner_join: quarantined in subquery(quarantined_test_case_states_subquery(project_id, state_filter)),
        as: :test_case_state,
        on: test_case.id == quarantined.test_case_id,
        where: test_case.project_id == ^project_id,
        select: count(test_case.id)
      )

    # Unlike the list query, which always joins :quarantine because it selects
    # and sorts on its columns, the count needs the join only when filtering by
    # quarantined_by. The shapes can differ without the totals diverging: the
    # subquery groups by test_case_id, so the join is at most 1:1 and can
    # neither drop nor duplicate rows.
    base_query =
      if quarantined_by_filter do
        from([test_case: test_case] in base_query,
          left_join: quarantine in subquery(quarantine_info_subquery(project_id)),
          as: :quarantine,
          on: test_case.id == quarantine.test_case_id
        )
      else
        base_query
      end

    base_query
    |> apply_name_search(search_term)
    |> apply_quarantined_by_filter(quarantined_by_filter)
    |> apply_module_name_filter(module_name_filter)
    |> apply_suite_name_filter(suite_name_filter)
  end

  @doc """
  Returns the list of accounts that have quarantined test cases for a project.
  Used to populate the "Quarantined by" filter dropdown.
  """
  def get_quarantine_actors(project_id) do
    quarantined_ids_subquery =
      from(s in subquery(quarantined_test_case_states_subquery(project_id, nil)),
        select: s.test_case_id
      )

    actor_ids =
      from(e in TestCaseEvent,
        where: e.test_case_id in subquery(quarantined_ids_subquery),
        where: e.event_type in ^@active_quarantine_event_types,
        group_by: e.test_case_id,
        having: fragment("tupleElement(argMax(tuple(?), ?), 1) IS NOT NULL", e.actor_id, e.inserted_at),
        select: fragment("tupleElement(argMax(tuple(?), ?), 1)", e.actor_id, e.inserted_at)
      )
      |> ClickHouseRepo.all()
      |> Enum.uniq()

    if Enum.any?(actor_ids) do
      Repo.all(from(a in Account, where: a.id in ^actor_ids))
    else
      []
    end
  end

  # The latest active quarantine event per test case: who quarantined it and
  # when. Both aggregates resolve to the same event, because for a currently
  # quarantined test case the most recent `muted`/`skipped` event is the one
  # that put it in that state.
  #
  # `actor_id` is wrapped in `tuple(...)` because ClickHouse aggregates skip
  # NULL arguments: a bare `argMax(actor_id, inserted_at)` ignores
  # automation-written events (NULL actor) and resurrects the last *human*
  # actor — e.g. a test muted by an automation showed the user who had
  # manually skipped it months earlier. A tuple is never NULL, so `argMax`
  # considers every event and NULL correctly wins as "quarantined by Tuist".
  defp quarantine_info_subquery(project_id) do
    from(e in TestCaseEvent,
      where: e.project_id == ^project_id,
      where: e.event_type in ^@active_quarantine_event_types,
      group_by: e.test_case_id,
      select: %{
        test_case_id: e.test_case_id,
        actor_id: fragment("tupleElement(argMax(tuple(?), ?), 1)", e.actor_id, e.inserted_at),
        quarantined_at: max(e.inserted_at)
      }
    )
  end

  defp get_actor_account_names(results) do
    actor_ids =
      results
      |> Enum.map(& &1.quarantined_by_account_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if Enum.any?(actor_ids) do
      from(a in Account, where: a.id in ^actor_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1.name})
    else
      %{}
    end
  end

  # Secondary `id` keeps the sort deterministic when the primary column has
  # ties. Without it ClickHouse is free to reshuffle tied rows between pages,
  # which surfaces as "duplicates" across pagination because the same row can
  # appear on two pages while another is skipped.
  defp apply_quarantined_order(query, :last_ran_at, :desc),
    do: from([test_case: tc] in query, order_by: [desc: tc.last_ran_at, asc: tc.id])

  defp apply_quarantined_order(query, :last_ran_at, :asc),
    do: from([test_case: tc] in query, order_by: [asc: tc.last_ran_at, asc: tc.id])

  defp apply_quarantined_order(query, :name, :desc),
    do: from([test_case: tc] in query, order_by: [desc: tc.name, asc: tc.id])

  defp apply_quarantined_order(query, :name, :asc),
    do: from([test_case: tc] in query, order_by: [asc: tc.name, asc: tc.id])

  defp apply_quarantined_order(query, :quarantined_at, :desc),
    do: from([test_case: tc, quarantine: quarantine] in query, order_by: [desc: quarantine.quarantined_at, asc: tc.id])

  defp apply_quarantined_order(query, :quarantined_at, :asc),
    do: from([test_case: tc, quarantine: quarantine] in query, order_by: [asc: quarantine.quarantined_at, asc: tc.id])

  defp apply_quarantined_order(query, _, _),
    do: from([test_case: tc] in query, order_by: [desc: tc.last_ran_at, asc: tc.id])

  # The currently quarantined test cases for a project, optionally narrowed to
  # one state. Joining against this instead of filtering `test_cases.state` also
  # makes the quarantine listing selective on the small side: only test cases
  # that were ever muted or skipped have a row in `test_case_states`.
  #
  # Resolved in two levels on purpose. The inner query finalizes the current
  # state per test case with `argMaxIfMerge`; the outer query filters on that
  # plain column. Merging and filtering in one level would collide: aliasing
  # `argMaxIfMerge(state) AS state` shadows the source aggregate column, so a
  # `HAVING argMaxIfMerge(state)` re-applies the merge to the finalized String
  # and ClickHouse rejects it.
  #
  # Deliberately no `ifNull(..., 'enabled')` normalisation, because here a null
  # must *not* become `enabled`. A test case with only flaky rows resolves to a
  # null state, and `NULL IN (...)` is 0 in ClickHouse, so the outer filter
  # correctly drops it. Wrapping this in `ifNull` would start matching test
  # cases that were never quarantined.
  defp quarantined_test_case_states_subquery(project_id, state_filter) do
    states = if state_filter in @active_quarantine_states, do: [state_filter], else: @active_quarantine_states

    resolved =
      from(s in TestCaseCurrentState,
        where: s.project_id == ^project_id,
        group_by: s.test_case_id,
        select: %{
          test_case_id: s.test_case_id,
          state: fragment("argMaxIfMerge(state)")
        }
      )

    from(q in subquery(resolved),
      where: q.state in ^states,
      select: %{
        test_case_id: q.test_case_id,
        state: q.state
      }
    )
  end

  defp apply_quarantined_by_filter(query, nil), do: query

  defp apply_quarantined_by_filter(query, {:==, :tuist}),
    do: from([quarantine: quarantine] in query, where: is_nil(quarantine.actor_id))

  defp apply_quarantined_by_filter(query, {:!=, :tuist}),
    do: from([quarantine: quarantine] in query, where: not is_nil(quarantine.actor_id))

  defp apply_quarantined_by_filter(query, {:==, user_id}) when is_integer(user_id),
    do: from([quarantine: quarantine] in query, where: quarantine.actor_id == ^user_id)

  defp apply_quarantined_by_filter(query, {:!=, user_id}) when is_integer(user_id),
    do: from([quarantine: quarantine] in query, where: quarantine.actor_id != ^user_id or is_nil(quarantine.actor_id))

  defp apply_quarantined_by_filter(query, _), do: query

  defp apply_module_name_filter(query, nil), do: query

  defp apply_module_name_filter(query, term),
    do: from([test_case: tc] in query, where: ilike(tc.module_name, ^"%#{term}%"))

  defp apply_suite_name_filter(query, nil), do: query

  defp apply_suite_name_filter(query, term), do: from([test_case: tc] in query, where: ilike(tc.suite_name, ^"%#{term}%"))

  defp row_to_quarantined_test_case(row, account_names) do
    %QuarantinedTestCase{
      id: row.id,
      name: row.name,
      module_name: row.module_name,
      suite_name: row.suite_name,
      quarantined_by_account_id: row.quarantined_by_account_id,
      quarantined_by_account_name: Map.get(account_names, row.quarantined_by_account_id),
      quarantined_at: row.quarantined_at,
      last_ran_at: row.last_ran_at,
      last_run_id: row.last_run_id,
      last_status: row.last_status,
      state: row.state
    }
  end

  defp mark_test_case_runs_as_flaky(_project_id, _git_commit_sha, []), do: :ok

  defp mark_test_case_runs_as_flaky(project_id, git_commit_sha, runs) when is_list(runs) do
    now = DateTime.utc_now(:second)

    corrections =
      runs
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(fn run ->
        %{
          test_case_run_id: run.id,
          project_id: project_id,
          test_case_id: run.test_case_id,
          git_commit_sha: git_commit_sha,
          state: "pending",
          inserted_at: now,
          updated_at: now
        }
      end)

    {:ok, _jobs} =
      Repo.transaction(fn ->
        {_count, inserted_corrections} =
          Repo.insert_all(TestCaseRunFlakyCorrection, corrections,
            on_conflict: :nothing,
            conflict_target: [:test_case_run_id],
            returning: [
              :test_case_run_id,
              :project_id,
              :git_commit_sha
            ]
          )

        enqueue_flaky_correction_jobs(inserted_corrections)
      end)

    :ok
  end

  defp flaky_correction_batch_id(test_case_run_ids) do
    test_case_run_ids
    |> Enum.sort()
    |> Enum.join(":")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc false
  def apply_test_case_run_flaky_corrections(test_case_run_ids) do
    test_case_run_ids
    |> pending_flaky_correction_ids_by_project_and_commit()
    |> Enum.each(fn grouped_test_case_run_ids ->
      {:ok, :ok} =
        Repo.transaction(
          fn ->
            do_apply_test_case_run_flaky_corrections(grouped_test_case_run_ids)
          end,
          timeout: 120_000
        )
    end)

    :ok
  end

  defp pending_flaky_correction_ids_by_project_and_commit(test_case_run_ids) do
    from(correction in TestCaseRunFlakyCorrection,
      where: correction.test_case_run_id in ^test_case_run_ids,
      where: correction.state == "pending",
      order_by: correction.test_case_run_id,
      select: %{
        test_case_run_id: correction.test_case_run_id,
        project_id: correction.project_id,
        git_commit_sha: correction.git_commit_sha
      }
    )
    |> Repo.all()
    |> Enum.group_by(&{&1.project_id, &1.git_commit_sha})
    |> Enum.map(fn {_project_and_commit, corrections} ->
      Enum.map(corrections, & &1.test_case_run_id)
    end)
  end

  defp do_apply_test_case_run_flaky_corrections(test_case_run_ids) do
    corrections =
      Repo.all(
        from(correction in TestCaseRunFlakyCorrection,
          where: correction.test_case_run_id in ^test_case_run_ids,
          where: correction.state == "pending",
          order_by: correction.test_case_run_id,
          lock: "FOR UPDATE"
        )
      )

    applied_ids =
      corrections
      |> Enum.group_by(&{&1.project_id, &1.git_commit_sha})
      |> Enum.flat_map(fn {{project_id, git_commit_sha}, grouped_corrections} ->
        latest_flaky_states =
          latest_test_case_run_flaky_states(
            project_id,
            git_commit_sha,
            grouped_corrections
          )

        {already_applied, corrections_to_insert} =
          Enum.split_with(grouped_corrections, fn correction ->
            Map.get(latest_flaky_states, correction.test_case_run_id) == true
          end)

        corrections_to_insert =
          Enum.filter(corrections_to_insert, fn correction ->
            Map.get(latest_flaky_states, correction.test_case_run_id) == false
          end)

        insert_test_case_run_flaky_corrections(
          project_id,
          git_commit_sha,
          corrections_to_insert
        )

        if corrections_to_insert != [] do
          report_test_case_run_multiplicity(project_id, git_commit_sha, corrections_to_insert)
        end

        Enum.map(already_applied ++ corrections_to_insert, & &1.test_case_run_id)
      end)

    if applied_ids != [] do
      Repo.update_all(
        from(correction in TestCaseRunFlakyCorrection,
          where: correction.test_case_run_id in ^applied_ids,
          where: correction.state == "pending"
        ),
        set: [state: "applied", updated_at: DateTime.utc_now(:second)]
      )
    end

    :ok
  end

  @doc false
  def enqueue_pending_test_case_run_flaky_corrections(opts \\ []) do
    older_than =
      Keyword.get_lazy(opts, :older_than, fn ->
        DateTime.add(DateTime.utc_now(:second), -5 * 60, :second)
      end)

    limit = Keyword.get(opts, :limit, @flaky_correction_sweep_limit)

    corrections =
      Repo.all(
        from(correction in TestCaseRunFlakyCorrection,
          where: correction.state == "pending",
          where: correction.inserted_at <= ^older_than,
          order_by: [asc: correction.inserted_at, asc: correction.test_case_run_id],
          limit: ^limit,
          select: %{
            test_case_run_id: correction.test_case_run_id,
            project_id: correction.project_id,
            git_commit_sha: correction.git_commit_sha
          }
        )
      )

    jobs = enqueue_flaky_correction_jobs(corrections)
    {:ok, length(jobs)}
  end

  defp enqueue_flaky_correction_jobs(corrections) do
    corrections
    |> Enum.group_by(&{&1.project_id, &1.git_commit_sha})
    |> Enum.flat_map(fn {_project_and_commit, grouped_corrections} ->
      grouped_corrections
      |> Enum.map(& &1.test_case_run_id)
      |> Enum.chunk_every(@flaky_correction_batch_size)
      |> Enum.map(fn batch_test_case_run_ids ->
        CorrectTestCaseRunFlakyStateWorker.new(%{
          batch_id: flaky_correction_batch_id(batch_test_case_run_ids),
          test_case_run_ids: batch_test_case_run_ids
        })
      end)
    end)
    |> Enum.reduce([], fn changeset, jobs ->
      {:ok, job} = Oban.insert(changeset)

      if job.conflict?, do: jobs, else: [job | jobs]
    end)
  end

  defp latest_test_case_run_flaky_states(project_id, git_commit_sha, corrections) do
    test_case_ids = corrections |> Enum.map(& &1.test_case_id) |> Enum.uniq()
    test_case_run_ids = Enum.map(corrections, & &1.test_case_run_id)

    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.test_case_id in ^test_case_ids,
      where: tcr.git_commit_sha == ^git_commit_sha,
      where: tcr.id in ^test_case_run_ids,
      group_by: tcr.id,
      select: {
        tcr.id,
        fragment("argMax(?, ?)", tcr.is_flaky, tcr.inserted_at)
      }
    )
    |> ClickHouseRepo.all(settings: @flaky_correction_lookup_settings)
    |> Map.new()
  end

  defp insert_test_case_run_flaky_corrections(_project_id, _git_commit_sha, []), do: :ok

  defp insert_test_case_run_flaky_corrections(project_id, git_commit_sha, corrections) do
    test_case_ids = corrections |> Enum.map(& &1.test_case_id) |> Enum.uniq()
    test_case_run_ids = Enum.map(corrections, & &1.test_case_run_id)

    sql = """
    INSERT INTO test_case_runs (
      id,
      name,
      test_run_id,
      test_module_run_id,
      test_suite_run_id,
      test_case_id,
      project_id,
      is_ci,
      scheme,
      account_id,
      ran_at,
      git_branch,
      is_default_branch,
      git_commit_sha,
      status,
      is_flaky,
      is_new,
      is_quarantined,
      duration,
      inserted_at,
      module_name,
      suite_name,
      shard_id,
      shard_index
    )
    SELECT
      id,
      name,
      test_run_id,
      test_module_run_id,
      test_suite_run_id,
      test_case_id,
      project_id,
      is_ci,
      scheme,
      account_id,
      ran_at,
      git_branch,
      is_default_branch,
      git_commit_sha,
      status,
      true,
      is_new,
      is_quarantined,
      duration,
      addMicroseconds(inserted_at, 1),
      module_name,
      suite_name,
      shard_id,
      shard_index
    FROM (
      SELECT *
      FROM test_case_runs
      WHERE project_id = {project_id:Int64}
        AND test_case_id IN {test_case_ids:Array(UUID)}
        AND git_commit_sha = {git_commit_sha:String}
        AND id IN {test_case_run_ids:Array(UUID)}
      ORDER BY id, inserted_at DESC
      LIMIT 1 BY id
    )
    WHERE is_flaky = false
    ORDER BY ALL
    """

    IngestRepo.query!(
      sql,
      %{
        project_id: project_id,
        test_case_ids: test_case_ids,
        git_commit_sha: git_commit_sha,
        test_case_run_ids: test_case_run_ids
      },
      settings: [
        insert_deduplication_token: "test-case-run-flaky-correction:#{flaky_correction_batch_id(test_case_run_ids)}",
        deduplicate_insert_select: "force_enable",
        deduplicate_blocks_in_dependent_materialized_views: 1
      ]
    )
  end

  defp report_test_case_run_multiplicity(project_id, git_commit_sha, corrections) do
    test_case_ids = corrections |> Enum.map(& &1.test_case_id) |> Enum.uniq()
    test_case_run_ids = Enum.map(corrections, & &1.test_case_run_id)

    physical_tuple_counts =
      ClickHouseRepo.all(
        from(tcr in TestCaseRun,
          where: tcr.project_id == ^project_id,
          where: tcr.test_case_id in ^test_case_ids,
          where: tcr.git_commit_sha == ^git_commit_sha,
          where: tcr.id in ^test_case_run_ids,
          group_by: tcr.id,
          select: {tcr.id, count()}
        )
      )

    max_physical_tuple_count =
      physical_tuple_counts
      |> Enum.map(&elem(&1, 1))
      |> Enum.max(fn -> 0 end)

    violating_test_case_run_ids =
      for {test_case_run_id, physical_tuple_count} <- physical_tuple_counts,
          physical_tuple_count > 2,
          do: test_case_run_id

    :telemetry.execute(
      Tuist.Telemetry.event_name_test_case_run_flaky_correction(),
      %{
        physical_tuple_count: max_physical_tuple_count,
        multiplicity_violation: length(violating_test_case_run_ids)
      },
      %{}
    )

    if violating_test_case_run_ids != [] do
      Sentry.capture_message(
        "Test case run physical tuple multiplicity exceeded",
        extra: %{
          max_physical_tuple_count: max_physical_tuple_count,
          violation_count: length(violating_test_case_run_ids),
          test_case_run_ids: Enum.take(violating_test_case_run_ids, 50)
        }
      )
    end
  end

  defp any_test_case_run_flaky?(test_case_run_data) do
    Enum.any?(test_case_run_data, fn %{is_flaky: is_flaky} -> is_flaky end)
  end

  @doc """
  Returns the count of unique flaky run groups (scheme + commit_sha) for a test case.
  """
  def get_flaky_runs_groups_count_for_test_case(project_id, test_case_id) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        select: fragment("count(DISTINCT (scheme, git_commit_sha))")
      )

    ClickHouseRepo.one(query) || 0
  end

  @doc """
  Returns a map of test_case_id => count of unique flaky run groups for multiple test cases.
  """
  def get_flaky_runs_groups_counts_for_test_cases(_project_id, []), do: %{}

  def get_flaky_runs_groups_counts_for_test_cases(project_id, test_case_ids) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.test_case_id in ^test_case_ids,
        where: tcr.is_flaky == true,
        group_by: tcr.test_case_id,
        select: {tcr.test_case_id, fragment("count(DISTINCT (scheme, git_commit_sha))")}
      )

    query
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  @doc """
  Fetches flaky runs for a specific test case, grouped by scheme and commit SHA.
  Returns paginated groups, each containing all runs with their failures.
  """
  def list_flaky_runs_for_test_case(project_id, test_case_id, params \\ %{}) do
    page = Map.get(params, :page, 1)
    page_size = Map.get(params, :page_size, 20)
    offset = (page - 1) * page_size

    groups_query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        group_by: [tcr.scheme, tcr.git_commit_sha],
        select: %{
          scheme: tcr.scheme,
          git_commit_sha: tcr.git_commit_sha,
          latest_ran_at: max(tcr.ran_at)
        },
        order_by: [desc: max(tcr.ran_at)],
        limit: ^page_size,
        offset: ^offset
      )

    groups = ClickHouseRepo.all(groups_query)
    group_keys = MapSet.new(groups, fn g -> {g.scheme, g.git_commit_sha} end)
    commit_shas = groups |> Enum.map(& &1.git_commit_sha) |> Enum.uniq()

    # Fetch every run on the flaky commits, not just the flagged failures, so the
    # per-group pass/fail breakdown reflects the full history of the commit. The
    # group itself is still identified by `is_flaky` runs in `groups_query`.
    group_runs =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.git_commit_sha in ^commit_shas,
        order_by: [desc: tcr.ran_at]
      )
      |> ClickHouseRepo.all()
      |> Enum.filter(fn run -> MapSet.member?(group_keys, {run.scheme, run.git_commit_sha}) end)

    run_ids = Enum.map(group_runs, & &1.id)

    failures = get_failures_for_runs(run_ids)
    failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

    repetitions = get_repetitions_for_runs(run_ids)
    repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

    runs_by_group = Enum.group_by(group_runs, fn run -> {run.scheme, run.git_commit_sha} end)

    flaky_groups =
      Enum.map(groups, fn group ->
        group_key = {group.scheme, group.git_commit_sha}
        runs = Map.get(runs_by_group, group_key, [])

        runs_with_details =
          Enum.map(runs, fn run ->
            run_failures = Map.get(failures_by_run_id, run.id, [])

            run_repetitions =
              repetitions_by_run_id
              |> Map.get(run.id, [])
              |> Enum.sort_by(& &1.repetition_number)

            run
            |> Map.put(:failures, run_failures)
            |> Map.put(:repetitions, run_repetitions)
          end)

        {passed_count, failed_count} = count_passed_failed(runs_with_details)

        %{
          scheme: group.scheme,
          git_commit_sha: group.git_commit_sha,
          latest_ran_at: group.latest_ran_at,
          passed_count: passed_count,
          failed_count: failed_count,
          runs: runs_with_details
        }
      end)

    total_count = get_flaky_runs_groups_count_for_test_case(project_id, test_case_id)

    meta = %{
      total_count: total_count,
      total_pages: if(total_count > 0, do: ceil(total_count / page_size), else: 0),
      current_page: page,
      page_size: page_size
    }

    {flaky_groups, meta}
  end

  def get_flaky_run_group_for_test_case_run(test_case_run) do
    group_runs =
      ClickHouseRepo.all(
        from(tcr in TestCaseRun,
          where: tcr.project_id == ^test_case_run.project_id,
          where: tcr.test_case_id == ^test_case_run.test_case_id,
          where: tcr.git_commit_sha == ^test_case_run.git_commit_sha,
          where: tcr.scheme == ^test_case_run.scheme,
          order_by: [desc: tcr.ran_at]
        )
      )

    if Enum.any?(group_runs, & &1.is_flaky) do
      run_ids = Enum.map(group_runs, & &1.id)

      failures = get_failures_for_runs(run_ids)
      failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

      repetitions = get_repetitions_for_runs(run_ids)
      repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

      runs_with_details =
        Enum.map(group_runs, fn run ->
          run_failures = Map.get(failures_by_run_id, run.id, [])

          run_repetitions =
            repetitions_by_run_id
            |> Map.get(run.id, [])
            |> Enum.sort_by(& &1.repetition_number)

          run
          |> Map.put(:failures, run_failures)
          |> Map.put(:repetitions, run_repetitions)
        end)

      {passed_count, failed_count} = count_passed_failed(runs_with_details)

      %{
        scheme: test_case_run.scheme,
        git_commit_sha: test_case_run.git_commit_sha,
        latest_ran_at: group_runs |> Enum.map(& &1.ran_at) |> Enum.max(NaiveDateTime),
        passed_count: passed_count,
        failed_count: failed_count,
        runs: runs_with_details
      }
    end
  end

  defp count_passed_failed(runs_with_details) do
    Enum.reduce(runs_with_details, {0, 0}, fn run, {passed, failed} ->
      if Enum.any?(run.repetitions) do
        rep_passed = Enum.count(run.repetitions, &(&1.status == "success"))
        rep_failed = Enum.count(run.repetitions, &(&1.status == "failure"))
        {passed + rep_passed, failed + rep_failed}
      else
        case run.status do
          "success" -> {passed + 1, failed}
          "failure" -> {passed, failed + 1}
          _ -> {passed, failed}
        end
      end
    end)
  end

  @doc """
  Gets flaky runs for a specific test run, grouped by test case name.
  Returns a list of groups, each containing runs with their failures.
  """
  def get_flaky_runs_for_test_run(test_run_id) do
    [test_run_id]
    |> get_flaky_runs_for_test_runs()
    |> Map.get(test_run_id, [])
  end

  @doc """
  Batched form of `get_flaky_runs_for_test_run/1`. Returns a map keyed by
  `test_run_id`. The CommentWorker fan-out path resolves N test runs per PR
  comment; using this avoids N round-trips against `test_case_runs_by_test_run`
  during the post-CI burst.
  """
  def get_flaky_runs_for_test_runs([]), do: %{}

  def get_flaky_runs_for_test_runs(test_run_ids) when is_list(test_run_ids) do
    current_by_test_run = fetch_flaky_runs_for_test_runs(test_run_ids)

    cross_by_test_run =
      fetch_cross_run_flaky_runs(test_run_ids, current_by_test_run)

    flaky_runs_by_test_run =
      Map.new(test_run_ids, fn test_run_id ->
        current = Map.get(current_by_test_run, test_run_id, [])
        cross = Map.get(cross_by_test_run, test_run_id, [])
        {test_run_id, current ++ cross}
      end)

    all_run_ids =
      flaky_runs_by_test_run
      |> Map.values()
      |> Enum.flat_map(fn runs -> Enum.map(runs, & &1.id) end)

    failures_by_run_id =
      all_run_ids |> get_failures_for_runs() |> Enum.group_by(& &1.test_case_run_id)

    repetitions_by_run_id =
      all_run_ids |> get_repetitions_for_runs() |> Enum.group_by(& &1.test_case_run_id)

    Map.new(flaky_runs_by_test_run, fn {test_run_id, flaky_runs} ->
      {test_run_id, group_flaky_runs(flaky_runs, failures_by_run_id, repetitions_by_run_id)}
    end)
  end

  defp group_flaky_runs(flaky_runs, failures_by_run_id, repetitions_by_run_id) do
    flaky_runs
    |> Enum.group_by(fn run -> {run.test_case_id, run.name, run.module_name, run.suite_name} end)
    |> Enum.map(fn {{test_case_id, name, module_name, suite_name}, runs} ->
      latest_ran_at = runs |> Enum.map(& &1.ran_at) |> Enum.max(NaiveDateTime)

      runs_with_details =
        Enum.map(runs, fn run ->
          run_failures = Map.get(failures_by_run_id, run.id, [])

          run_repetitions =
            repetitions_by_run_id
            |> Map.get(run.id, [])
            |> Enum.sort_by(& &1.repetition_number)

          run
          |> Map.put(:failures, run_failures)
          |> Map.put(:repetitions, run_repetitions)
        end)

      {passed_count, failed_count} = count_passed_failed(runs_with_details)

      %{
        test_case_id: test_case_id,
        name: name,
        module_name: module_name,
        suite_name: suite_name,
        latest_ran_at: latest_ran_at,
        passed_count: passed_count,
        failed_count: failed_count,
        runs: runs_with_details
      }
    end)
    |> Enum.sort_by(& &1.latest_ran_at, {:desc, NaiveDateTime})
  end

  # Avoids `FINAL` (which forces a cross-part merge of the entire matched
  # range). Aggregating with `argMax(...inserted_at)` deduplicates only the
  # rows that already pass the `test_run_id` primary-key filter, then
  # `HAVING` checks the *latest* version of `is_flaky` for each test case.
  # Returns a map keyed by `test_run_id` so callers can preserve per-run
  # grouping after the batched query.
  defp fetch_flaky_runs_for_test_runs(test_run_ids) do
    slim_query =
      from(mv in TestCaseRunByTestRun,
        where: mv.test_run_id in ^test_run_ids,
        group_by: [mv.test_run_id, mv.id],
        having: fragment("argMax(?, ?) = ?", mv.is_flaky, mv.inserted_at, true),
        select: %{
          id: mv.id,
          test_run_id: mv.test_run_id,
          project_id: fragment("argMax(?, ?)", mv.project_id, mv.inserted_at),
          test_case_id: fragment("argMax(?, ?)", mv.test_case_id, mv.inserted_at),
          ran_at: fragment("argMax(?, ?)", mv.ran_at, mv.inserted_at)
        }
      )

    slim_results = ClickHouseRepo.all(slim_query)
    full_by_id = slim_results |> fetch_full_test_case_runs() |> Map.new(&{&1.id, &1})

    slim_results
    |> Enum.group_by(& &1.test_run_id)
    |> Map.new(fn {test_run_id, slim_rows} ->
      ordered =
        slim_rows
        |> Enum.sort_by(& &1.ran_at, {:desc, NaiveDateTime})
        |> Enum.map(&Map.get(full_by_id, &1.id))
        |> Enum.reject(&is_nil/1)

      {test_run_id, ordered}
    end)
  end

  # Resolves the "same test_case_id ran on the same commit in OTHER
  # test_runs" lookup for an entire batch of test_run_ids in one query. The
  # test cases are already known to be flaky (they come from each run's own
  # flagged runs); this pulls every run on the commit for them — passes
  # included — so the grouped view shows the full pass/fail breakdown.
  #
  # The single ClickHouse query is filtered against the *union* of
  # per-axis IN sets across the batch, but each test_run's slice of the
  # result is then re-filtered in Elixir against THAT test_run's own
  # per-axis sets. This preserves the per-call semantics — run A only
  # sees matches that satisfy A's own (project, test_case, commit) IN
  # filters — without inflating its set with runs that only matched
  # because run B contributed an unrelated key to the union. Without
  # this re-filter, A flaky on `(Foo, sha1)` and B flaky on
  # `(Bar, sha2)` would mistakenly cross-link Bar@sha2 into A's flaky
  # group in the PR comment.
  defp fetch_cross_run_flaky_runs(test_run_ids, current_by_test_run) do
    per_run_keys =
      Map.new(test_run_ids, fn test_run_id ->
        {test_run_id, current_by_test_run |> Map.get(test_run_id, []) |> collect_cross_run_keys()}
      end)

    {project_ids, test_case_ids, commit_shas} =
      current_by_test_run
      |> Map.values()
      |> List.flatten()
      |> collect_cross_run_keys()

    cond do
      Enum.empty?(test_run_ids) ->
        %{}

      Enum.empty?(commit_shas) or Enum.empty?(test_case_ids) ->
        Map.new(test_run_ids, &{&1, []})

      true ->
        all_matches =
          ClickHouseRepo.all(
            from(tcr in TestCaseRun,
              where: tcr.project_id in ^project_ids,
              where: tcr.test_case_id in ^test_case_ids,
              where: tcr.git_commit_sha in ^commit_shas,
              order_by: [desc: tcr.ran_at]
            )
          )

        Map.new(test_run_ids, fn test_run_id ->
          {test_run_id, scope_cross_run_matches(all_matches, test_run_id, per_run_keys)}
        end)
    end
  end

  defp scope_cross_run_matches(all_matches, test_run_id, per_run_keys) do
    {own_projects, own_test_cases, own_commits} =
      Map.get(per_run_keys, test_run_id, {[], [], []})

    if Enum.empty?(own_commits) or Enum.empty?(own_test_cases) do
      []
    else
      project_set = MapSet.new(own_projects)
      test_case_set = MapSet.new(own_test_cases)
      commit_set = MapSet.new(own_commits)

      Enum.filter(all_matches, fn match ->
        match.test_run_id != test_run_id and
          MapSet.member?(project_set, match.project_id) and
          MapSet.member?(test_case_set, match.test_case_id) and
          MapSet.member?(commit_set, match.git_commit_sha)
      end)
    end
  end

  defp collect_cross_run_keys(current_flaky_runs) do
    project_ids = current_flaky_runs |> Enum.map(& &1.project_id) |> Enum.uniq()
    test_case_ids = current_flaky_runs |> Enum.map(& &1.test_case_id) |> Enum.uniq()

    commit_shas =
      current_flaky_runs
      |> Enum.map(& &1.git_commit_sha)
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.uniq()

    {project_ids, test_case_ids, commit_shas}
  end

  defp get_failures_for_runs([]), do: []

  defp get_failures_for_runs(run_ids) do
    query =
      from(f in TestCaseFailure,
        where: f.test_case_run_id in ^run_ids,
        select: %{
          test_case_run_id: f.test_case_run_id,
          message: f.message,
          path: f.path,
          line_number: f.line_number,
          issue_type: f.issue_type
        }
      )

    ClickHouseRepo.all(query)
  end

  defp get_repetitions_for_runs([]), do: []

  defp get_repetitions_for_runs(run_ids) do
    query =
      from(r in TestCaseRunRepetition,
        where: r.test_case_run_id in ^run_ids,
        select: %{
          test_case_run_id: r.test_case_run_id,
          repetition_number: r.repetition_number,
          name: r.name,
          status: r.status,
          duration: r.duration
        }
      )

    ClickHouseRepo.all(query)
  end

  @doc """
  How long a run is given to hear from every shard before it is presumed
  abandoned. The dashboard reads the same window to decide when a shard that
  never reported can be called missing rather than still running.
  """
  def stale_run_window_hours, do: @stale_run_window_hours

  @doc """
  Marks in-progress test runs older than the stale run window as failed.
  """
  def expire_stale_in_progress_test_runs do
    six_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -@stale_run_window_hours, :hour)
    now = NaiveDateTime.utc_now()

    # `test_runs` is ReplacingMergeTree, and FINAL re-expands granule
    # selection across parts so duplicates can be merged. That defeats the
    # `idx_status` skip index, which is the only thing that makes finding
    # `in_progress` rows cheap. Find candidate ids without FINAL (the skip
    # index then prunes granules), then re-resolve their latest version via
    # the `proj_by_id` projection. Status and age must be checked only after
    # resolving the latest version, or an older in-progress version could
    # overwrite a completed run.
    candidate_ids =
      ClickHouseRepo.all(
        from(t in Test,
          where: t.status == "in_progress",
          where: t.inserted_at < ^six_hours_ago,
          select: t.id,
          distinct: true
        )
      )

    latest_candidate_runs =
      if candidate_ids == [] do
        []
      else
        from(t in Test,
          where: t.id in ^candidate_ids,
          order_by: [asc: t.id, desc: t.inserted_at]
        )
        |> ClickHouseRepo.all()
        |> Enum.uniq_by(& &1.id)
      end

    stale_runs =
      Enum.filter(
        latest_candidate_runs,
        &(&1.status == "in_progress" and NaiveDateTime.before?(&1.inserted_at, six_hours_ago))
      )

    updated_runs =
      Enum.map(stale_runs, fn run ->
        run
        |> Map.from_struct()
        |> Map.drop(@test_struct_non_field_keys)
        |> Map.merge(%{status: "failure", inserted_at: now})
      end)

    IngestRepo.insert_all(Test, updated_runs)

    sharded_runs = Enum.filter(stale_runs, & &1.shard_plan_id)
    shard_plan_ids = sharded_runs |> Enum.map(& &1.shard_plan_id) |> Enum.uniq()
    test_run_ids = Enum.map(sharded_runs, & &1.id)

    plans =
      from(sp in Tuist.Shards.ShardPlan,
        where: sp.id in ^shard_plan_ids
      )
      |> ClickHouseRepo.all()
      |> Map.new(&{&1.id, &1})

    reported =
      from(sr in ShardRun,
        where: sr.test_run_id in ^test_run_ids,
        select: {sr.test_run_id, sr.shard_index}
      )
      |> ClickHouseRepo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    missing_shard_runs =
      Enum.flat_map(sharded_runs, fn run ->
        case Map.get(plans, run.shard_plan_id) do
          nil ->
            []

          plan ->
            reported_indices = reported |> Map.get(run.id, []) |> MapSet.new()

            0..(plan.shard_count - 1)
            |> Enum.reject(&MapSet.member?(reported_indices, &1))
            |> Enum.map(fn index ->
              %{
                shard_plan_id: run.shard_plan_id,
                project_id: run.project_id,
                test_run_id: run.id,
                shard_index: index,
                status: "failure",
                duration: 0,
                ran_at: now,
                inserted_at: now
              }
            end)
        end
      end)

    IngestRepo.insert_all(ShardRun, missing_shard_runs)

    :ok
  end

  def create_test_case_run_attachment(attrs) do
    %TestCaseRunAttachment{}
    |> TestCaseRunAttachment.create_changeset(attrs)
    |> IngestRepo.insert()
  end

  def get_attachment_by_id(id) do
    query =
      from(a in TestCaseRunAttachment,
        where: a.id == ^id,
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  def get_test_case_run_attachment(test_case_run_id, attachment_id) do
    query =
      from(a in TestCaseRunAttachment,
        where: a.test_case_run_id == ^test_case_run_id and a.id == ^attachment_id,
        limit: 1
      )

    # Crash report uploads immediately read a newly created attachment through a different
    # ClickHouse pool, so this lookup must not use stale replica metadata.
    case ClickHouseRepo.one(query, settings: [select_sequential_consistency: 1]) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  def get_attachment(test_case_run_id, file_name) do
    query =
      from(a in TestCaseRunAttachment,
        where: a.test_case_run_id == ^test_case_run_id and a.file_name == ^file_name,
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  def attachment_storage_key(%{test_run_id: test_run_id} = params) when not is_nil(test_run_id) do
    %{
      account_handle: account_handle,
      project_handle: project_handle,
      attachment_id: attachment_id,
      file_name: file_name
    } =
      params

    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/tests/runs/#{test_run_id}/attachments/#{attachment_id}/#{file_name}"
  end

  # Legacy path for attachments created before test_run_id was added to the schema.
  # New attachments use the test_run_id-based path above.
  def attachment_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        test_case_run_id: test_case_run_id,
        attachment_id: attachment_id,
        file_name: file_name
      }) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/tests/test-case-runs/#{test_case_run_id}/attachments/#{attachment_id}/#{file_name}"
  end
end
