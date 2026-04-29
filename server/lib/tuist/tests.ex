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
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
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
  alias Tuist.Tests.TestCaseEvent
  alias Tuist.Tests.TestCaseFailure
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunArgument
  alias Tuist.Tests.TestCaseRunAttachment
  alias Tuist.Tests.TestCaseRunByCommit
  alias Tuist.Tests.TestCaseRunByShardId
  alias Tuist.Tests.TestCaseRunByTestRun
  alias Tuist.Tests.TestCaseRunDashboardCount
  alias Tuist.Tests.TestCaseRunRepetition
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.TestRunDestination
  alias Tuist.Tests.TestSuiteRun

  require OpenTelemetry.Tracer

  # Number of days of run history used to decide whether a test case is "active"
  # (i.e. still part of the suite). Used by `list_test_cases/2` and by the Test
  # Cases / Flaky Tests analytics charts so they stay in sync.
  @active_window_days 14

  @doc """
  Number of trailing days used across the product to decide whether a test case
  is still considered part of the suite.
  """
  def active_window_days, do: @active_window_days

  # State-change events emitted by `update_test_case` use the `muted` /
  # `unmuted` names. Pre-rename rows have already been backfilled to these
  # names by `RenameLegacyQuarantineEvents`, so consumers can match on a
  # single canonical value.
  @mute_event_types ~w(muted unmuted)
  @skip_event_types ~w(skipped unskipped)
  @quarantine_event_types @mute_event_types ++ @skip_event_types
  @active_quarantine_event_types ~w(muted skipped)

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
    twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24, :hour)

    ClickHouseRepo.one(
      from(t in Test,
        hints: ["FINAL"],
        where: t.inserted_at >= ^twenty_four_hours_ago,
        select: count()
      )
    ) ||
      0
  end

  def last_24h_test_case_run_count do
    yesterday = Date.add(Date.utc_today(), -1)

    ClickHouseRepo.one(
      from(d in TestCaseRunDashboardCount,
        where: d.day >= ^yesterday,
        select: fragment("countMerge(count)")
      )
    ) || 0
  end

  def last_24h_flaky_test_case_run_count do
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
            hints: ["FINAL"],
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
    Tuist.ClickHouseFlop.validate_and_run!(TestSuiteRun, attrs, for: TestSuiteRun)
  end

  def list_test_module_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestModuleRun, attrs, for: TestModuleRun)
  end

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

  defp create_or_update_sharded_test(attrs) do
    shard_plan_id = Map.fetch!(attrs, :shard_plan_id)
    project_id = Map.fetch!(attrs, :project_id)
    test_modules = Map.get(attrs, :test_modules, [])

    existing =
      ClickHouseRepo.one(
        from(t in Test,
          hints: ["FINAL"],
          where: t.shard_plan_id == ^shard_plan_id,
          where: t.project_id == ^project_id,
          order_by: [desc: t.inserted_at],
          limit: 1
        )
      )

    {:ok, shard_plan} = Shards.get_shard_plan(shard_plan_id)
    expected_shard_count = shard_plan.shard_count

    shard_index = Map.get(attrs, :shard_index)
    shard_status = Map.get(attrs, :status, "success")
    shard_duration = Map.get(attrs, :duration, 0)

    result =
      case existing do
        nil ->
          test_status = if expected_shard_count > 1, do: "in_progress", else: shard_status

          attrs =
            attrs
            |> Map.put(:status, test_status)
            |> Map.put_new(:build_run_id, shard_plan.build_run_id)
            |> Map.put_new(:gradle_build_id, shard_plan.gradle_build_id)

          create_new_test(attrs, shard_index, shard_plan)

        existing_test ->
          {test_case_ids_with_flaky_run, test_case_runs} =
            OpenTelemetry.Tracer.with_span "tests.create_test_modules" do
              create_test_modules(existing_test, test_modules, shard_index, shard_plan)
            end

          reported_count = count_reported_shards(existing_test.id) + 1

          merged_status =
            if reported_count >= expected_shard_count do
              compute_final_shard_status(existing_test, shard_status)
            else
              "in_progress"
            end

          merged_duration = max(existing_test.duration, shard_duration)

          updated_test = %{existing_test | status: merged_status, duration: merged_duration}

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
      insert_shard_run(
        shard_plan_id,
        project_id,
        test.id,
        shard_index,
        shard_status,
        shard_duration,
        attrs
      )

      {:ok, test}
    end
  end

  defp count_reported_shards(test_run_id) do
    ClickHouseRepo.one(
      from(sr in ShardRun,
        where: sr.test_run_id == ^test_run_id,
        select: count()
      )
    ) || 0
  end

  defp compute_final_shard_status(existing_test, current_shard_status) do
    has_failed_shard =
      ClickHouseRepo.one(
        from(sr in ShardRun,
          where: sr.test_run_id == ^existing_test.id,
          where: sr.status == "failure",
          select: count(),
          limit: 1
        )
      ) || 0

    cond do
      current_shard_status == "failure" -> "failure"
      has_failed_shard > 0 -> "failure"
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
        existing_is_flaky = Map.get(existing, :is_flaky, false)
        existing_state = Map.get(existing, :state, "enabled")

        test_case = %{
          id: id,
          name: data.name,
          module_name: data.module_name,
          suite_name: data.suite_name,
          project_id: project_id,
          last_status: data.status,
          last_duration: data.duration,
          last_ran_at: data.ran_at,
          is_flaky: existing_is_flaky,
          last_run_id: test_run_id,
          state: existing_state,
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

    {test_case_id_map, test_cases_with_flaky_run, new_test_case_ids}
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

  # Batch size for `id IN (...)` lookups. Each UUID is ~38 bytes encoded in the
  # SQL, so 5_000 IDs is ~190 KB, well below ClickHouse's default
  # `max_query_size` of 256 KB even with surrounding query text. Larger batches
  # would risk a `TOO_LARGE_QUERY` rejection on big test reports.
  @existing_test_cases_batch_size 5_000

  defp get_existing_test_cases(_project_id, []), do: %{}

  # Returns the latest `recent_durations`, `is_flaky`, and `state` per test case
  # for the given IDs. We avoid the FINAL hint because the per-call merge cost
  # dominates when this is called during ingestion (every test report) and
  # dedupe in Elixir from a small result set instead.
  defp get_existing_test_cases(project_id, test_case_ids) do
    test_case_ids
    |> Enum.chunk_every(@existing_test_cases_batch_size)
    |> Enum.reduce(%{}, fn ids_chunk, acc ->
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        where: test_case.id in ^ids_chunk,
        select: %{
          id: test_case.id,
          recent_durations: test_case.recent_durations,
          is_flaky: test_case.is_flaky,
          state: test_case.state,
          inserted_at: test_case.inserted_at
        }
      )
      |> IngestRepo.all()
      |> Enum.reduce(acc, fn row, inner_acc ->
        Map.update(inner_acc, row.id, row, fn existing ->
          if NaiveDateTime.after?(row.inserted_at, existing.inserted_at), do: row, else: existing
        end)
      end)
    end)
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
      nil -> {:error, :not_found}
      test_case -> {:ok, test_case}
    end
  end

  @doc """
  Updates a test case by inserting a new row with the given attributes.
  ClickHouse ReplacingMergeTree will keep the most recent row.

  Only `is_flaky` and `state` are valid update attributes.

  Creates test case events to track the state change.

  ## Parameters
  - `test_case_id` - the test case UUID to update
  - `update_attrs` - map with `:is_flaky` boolean and/or `:state` (`"enabled"` | `"muted"` | `"skipped"`)
  - `opts` - optional keyword list with `:actor_id` (account_id for user actions, nil for system)
  """
  def update_test_case(test_case_id, update_attrs, opts \\ []) when is_map(update_attrs) do
    valid_keys = [:is_flaky, :state]
    filtered_attrs = Map.take(update_attrs, valid_keys)
    actor_id = Keyword.get(opts, :actor_id)

    with {:ok, test_case} <- get_test_case_by_id(test_case_id) do
      attrs =
        test_case
        |> Map.from_struct()
        |> Map.delete(:__meta__)
        |> Map.merge(filtered_attrs)
        |> Map.put(:inserted_at, NaiveDateTime.utc_now())

      IngestRepo.insert_all(TestCase, [attrs])

      create_events_for_test_case_changes(test_case_id, test_case, filtered_attrs, actor_id)

      {:ok, Map.merge(test_case, filtered_attrs)}
    end
  end

  defp create_events_for_test_case_changes(test_case_id, old_test_case, new_attrs, actor_id) do
    event_types = determine_test_case_events(old_test_case, new_attrs)

    if Enum.any?(event_types) do
      now = NaiveDateTime.utc_now()

      events =
        Enum.map(event_types, fn event_type ->
          %{
            id: UUIDv7.generate(),
            test_case_id: test_case_id,
            event_type: to_string(event_type),
            actor_id: actor_id,
            inserted_at: now
          }
        end)

      TestCaseEvent.Buffer.insert_all(events)
    end
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

    events = Repo.preload(events, :actor)
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

  defp fetch_full_test_case_runs([]), do: []

  defp fetch_full_test_case_runs(slim_results) do
    ids = Enum.map(slim_results, & &1.id)
    project_ids = slim_results |> Enum.map(& &1.project_id) |> Enum.uniq()
    test_case_ids = slim_results |> Enum.map(& &1.test_case_id) |> Enum.uniq()

    ClickHouseRepo.all(
      from(tcr in TestCaseRun,
        hints: ["FINAL"],
        where: tcr.project_id in ^project_ids,
        where: tcr.test_case_id in ^test_case_ids,
        where: tcr.id in ^ids
      )
    )
  end

  defp extract_mv_scope_filter(%{filters: filters}) when is_list(filters) do
    Enum.find_value(filters, fn
      %{field: :test_run_id, op: :==, value: value} -> {:test_run_id, value}
      %{field: :shard_id, op: :==, value: value} -> {:shard_id, value}
      _ -> nil
    end)
  end

  defp extract_mv_scope_filter(%Flop{} = flop) do
    flop.filters
    |> List.wrap()
    |> Enum.find_value(fn
      %Flop.Filter{field: :test_run_id, op: :==, value: value} -> {:test_run_id, value}
      %Flop.Filter{field: :shard_id, op: :==, value: value} -> {:shard_id, value}
      _ -> nil
    end)
  end

  defp extract_mv_scope_filter(_), do: nil

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
    test_case_run_data =
      OpenTelemetry.Tracer.with_span "tests.get_test_case_run_data" do
        get_test_case_run_data(test, test_modules)
      end

    test_case_ids = collect_test_case_ids(test.project_id, test_modules)
    existing_test_cases = get_existing_test_cases(test.project_id, test_case_ids)

    test_case_run_data_by_module =
      Enum.group_by(
        test_case_run_data,
        fn {{_name, mod_name, _suite}, _data} -> mod_name end
      )

    Enum.flat_map_reduce(test_modules, [], fn module_attrs, acc_test_case_runs ->
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
          existing_test_cases
        )

      {flaky_ids, acc_test_case_runs ++ test_case_runs}
    end)
  end

  defp get_test_case_run_data(test, test_modules) do
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

    mark_test_case_runs_as_flaky(historical_flaky_runs)

    test_case_data = check_new_test_cases(test, test_case_data)

    Map.new(test_case_data, fn data ->
      {data.identity_key, %{status: data.status, is_flaky: data.is_flaky, is_new: data.is_new}}
    end)
  end

  defp check_cross_run_flakiness(%{is_ci: false}, test_case_data), do: {test_case_data, []}
  defp check_cross_run_flakiness(%{git_commit_sha: nil}, test_case_data), do: {test_case_data, []}

  defp check_cross_run_flakiness(test, test_case_data) do
    test_case_ids = Enum.map(test_case_data, & &1.test_case_id)

    existing_runs =
      get_existing_ci_runs_for_commit(test_case_ids, test.git_commit_sha, test.project_id)

    Enum.map_reduce(test_case_data, [], fn data, historical_runs ->
      case filter_cross_run_flaky(data, existing_runs) do
        [] ->
          {data, historical_runs}

        flaky_runs ->
          {%{data | is_flaky: true}, flaky_runs ++ historical_runs}
      end
    end)
  end

  defp filter_cross_run_flaky(data, existing_runs) do
    existing = Map.get(existing_runs, data.test_case_id, [])

    if data.status in ["success", "failure"] do
      Enum.filter(existing, &(to_string(&1.status) != data.status))
    else
      []
    end
  end

  defp get_existing_ci_runs_for_commit([], _git_commit_sha, _project_id), do: %{}

  defp get_existing_ci_runs_for_commit(test_case_ids, git_commit_sha, project_id) do
    test_case_id_set = MapSet.new(test_case_ids)

    query =
      from(tcr in TestCaseRunByCommit,
        where: tcr.project_id == ^project_id,
        where: tcr.git_commit_sha == ^git_commit_sha,
        where: tcr.is_ci == true,
        where: tcr.status in ["success", "failure"],
        select: %{id: tcr.id, test_case_id: tcr.test_case_id, status: tcr.status}
      )

    query
    |> ClickHouseRepo.all()
    |> Enum.filter(&(&1.test_case_id in test_case_id_set))
    |> Enum.group_by(& &1.test_case_id)
  end

  defp check_new_test_cases(test, test_case_data) do
    project = Tuist.Projects.get_project_by_id(test.project_id)
    default_branch = project && project.default_branch

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
         existing_test_cases
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

    {test_case_id_map, test_case_ids_with_flaky_run, new_test_case_ids} =
      create_test_cases(test.project_id, test_case_data_list, existing_test_cases, test_run_id: test.id)

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
          git_commit_sha: test.git_commit_sha || "",
          status: status,
          is_flaky: is_flaky,
          is_new: is_new,
          is_quarantined: Map.get(case_attrs, :is_quarantined, false),
          duration: Map.get(case_attrs, :duration, 0),
          inserted_at: NaiveDateTime.utc_now(),
          module_name: module_name,
          suite_name: suite_name || "",
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

    Tuist.Tasks.run_async(fn ->
      TestCaseRun.Buffer.insert_all(test_case_runs)
      TestCaseFailure.Buffer.insert_all(all_failures)

      if Enum.any?(all_repetitions) do
        TestCaseRunRepetition.Buffer.insert_all(all_repetitions)
      end

      if Enum.any?(all_attachments) do
        TestCaseRunAttachment.Buffer.insert_all(all_attachments)
      end

      if Enum.any?(all_arguments) do
        TestCaseRunArgument.Buffer.insert_all(all_arguments)
      end
    end)

    create_first_run_events(test_case_runs, new_test_case_ids)

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

  defp create_first_run_events(test_case_runs, new_test_case_ids) do
    new_test_case_runs =
      Enum.filter(test_case_runs, fn run ->
        run.is_new and run.test_case_id in new_test_case_ids
      end)

    if Enum.any?(new_test_case_runs) do
      now = NaiveDateTime.utc_now()

      events =
        Enum.map(new_test_case_runs, fn run ->
          %{
            id: TestCaseEvent.first_run_id(run.test_case_id),
            test_case_id: run.test_case_id,
            event_type: "first_run",
            actor_id: nil,
            inserted_at: now
          }
        end)

      TestCaseEvent.Buffer.insert_all(events)
    end
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
    * `:active_period` — `{start_datetime, end_datetime}` tuple. When set, the result
      is restricted to test cases that had at least one run in the given window
      (via a join with `test_case_runs`), regardless of `last_ran_at`.
    * `:is_ci` — when combined with `:active_period`, further restricts the run
      lookup to CI (`true`) or local (`false`) runs.
  """
  def list_test_cases(project_id, attrs, opts \\ []) do
    filters = Map.get(attrs, :filters, [])
    has_name_filter = Enum.any?(filters, fn f -> f.field == :name end)
    quarantine_filter? = quarantine_filter?(filters)
    active_period = Keyword.get(opts, :active_period)
    is_ci = Keyword.get(opts, :is_ci)

    base_query =
      from(test_case in TestCase,
        hints: ["FINAL"],
        where: test_case.project_id == ^project_id
      )

    base_query =
      cond do
        not is_nil(active_period) ->
          active_ids = active_test_case_ids_query(project_id, active_period, is_ci)

          from(test_case in base_query,
            inner_join: active in subquery(active_ids),
            on: test_case.id == active.test_case_id
          )

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
          window_start = NaiveDateTime.add(NaiveDateTime.utc_now(), -@active_window_days, :day)
          where(base_query, [test_case], test_case.last_ran_at >= ^window_start)
      end

    Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCase)
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

  # `inserted_at` is added alongside `ran_at` so the partition pruner can skip
  # months outside the window. `test_case_runs` is `PARTITION BY
  # toYYYYMM(inserted_at)` and `ran_at` is not a partition key. Rows with
  # `inserted_at < ran_at` would not exist (insert happens after the run
  # completes), so this never excludes a row that the `ran_at` window would
  # have included.
  defp active_test_case_ids_query(project_id, {start_datetime, end_datetime}, is_ci) do
    start_naive = DateTime.to_naive(start_datetime)
    end_naive = DateTime.to_naive(end_datetime)

    query =
      from(run in TestCaseRun,
        where:
          run.project_id == ^project_id and
            run.ran_at >= ^start_naive and
            run.ran_at <= ^end_naive and
            run.inserted_at >= ^start_naive and
            not is_nil(run.test_case_id),
        group_by: run.test_case_id,
        select: %{test_case_id: run.test_case_id}
      )

    case is_ci do
      true -> from(r in query, where: r.is_ci == true)
      false -> from(r in query, where: r.is_ci == false)
      _ -> query
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

  defp build_flaky_test_cases_query(project_id, search_term, opts) do
    base_query =
      from(test_case in TestCase,
        hints: ["FINAL"],
        inner_join: flaky in subquery(currently_flaky_test_case_ids_subquery(project_id, opts)),
        on: test_case.id == flaky.test_case_id,
        inner_join: stats in subquery(flaky_stats_subquery(project_id, opts)),
        on: test_case.id == stats.test_case_id,
        where: test_case.project_id == ^project_id,
        select: %{
          id: test_case.id,
          name: test_case.name,
          module_name: test_case.module_name,
          suite_name: test_case.suite_name,
          flaky_runs_count: stats.flaky_runs_count,
          last_flaky_at: stats.last_flaky_at,
          last_flaky_run_id: stats.last_flaky_run_id
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
        inner_join: stats in subquery(flaky_stats_subquery(project_id, opts)),
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
      select: %{test_case_id: e.test_case_id}
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

  defp apply_flaky_order(query, _, _),
    do: from([tc, _flaky, stats] in query, order_by: [desc: coalesce(stats.flaky_runs_count, 0)])

  defp row_to_flaky_test_case(row) do
    %FlakyTestCase{
      id: row.id,
      name: row.name,
      module_name: row.module_name,
      suite_name: row.suite_name,
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

    test_case_ids = Enum.map(results, & &1.id)
    quarantine_info = get_quarantine_info_for_test_cases(test_case_ids)

    quarantined_tests =
      Enum.map(results, fn row ->
        info = Map.get(quarantine_info, row.id, %{})
        row_to_quarantined_test_case(row, info)
      end)

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
      %{field: :state, value: value} when value in ["muted", "skipped"] -> value
      %{field: "state", value: value} when value in ["muted", "skipped"] -> value
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
    base_query =
      apply_quarantined_state_filter(
        from(test_case in TestCase,
          as: :test_case,
          hints: ["FINAL"],
          where: test_case.project_id == ^project_id,
          select: %{
            id: test_case.id,
            name: test_case.name,
            module_name: test_case.module_name,
            suite_name: test_case.suite_name,
            last_ran_at: test_case.last_ran_at,
            last_run_id: test_case.last_run_id,
            last_status: test_case.last_status,
            state: test_case.state
          }
        ),
        state_filter
      )

    base_query =
      if quarantined_by_filter do
        quarantine_info_subquery =
          from(e in TestCaseEvent,
            where: e.event_type in ^@active_quarantine_event_types,
            group_by: e.test_case_id,
            select: %{
              test_case_id: e.test_case_id,
              actor_id: fragment("argMax(?, ?)", e.actor_id, e.inserted_at)
            }
          )

        from([test_case: test_case] in base_query,
          left_join: quarantine in subquery(quarantine_info_subquery),
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

  defp build_quarantined_test_cases_count_query(
         project_id,
         search_term,
         quarantined_by_filter,
         module_name_filter,
         suite_name_filter,
         state_filter
       ) do
    base_query =
      apply_quarantined_state_filter(
        from(test_case in TestCase,
          as: :test_case,
          hints: ["FINAL"],
          where: test_case.project_id == ^project_id,
          select: count(test_case.id)
        ),
        state_filter
      )

    base_query =
      if quarantined_by_filter do
        quarantine_info_subquery =
          from(e in TestCaseEvent,
            where: e.event_type in ^@active_quarantine_event_types,
            group_by: e.test_case_id,
            select: %{
              test_case_id: e.test_case_id,
              actor_id: fragment("argMax(?, ?)", e.actor_id, e.inserted_at)
            }
          )

        from([test_case: test_case] in base_query,
          left_join: quarantine in subquery(quarantine_info_subquery),
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
      from(tc in TestCase,
        hints: ["FINAL"],
        where: tc.project_id == ^project_id and tc.state in ["muted", "skipped"],
        select: tc.id
      )

    actor_ids =
      from(e in TestCaseEvent,
        where: e.test_case_id in subquery(quarantined_ids_subquery),
        where: e.event_type in ^@active_quarantine_event_types,
        group_by: e.test_case_id,
        having: fragment("argMax(?, ?) IS NOT NULL", e.actor_id, e.inserted_at),
        select: fragment("argMax(?, ?)", e.actor_id, e.inserted_at)
      )
      |> ClickHouseRepo.all()
      |> Enum.uniq()

    if Enum.any?(actor_ids) do
      Repo.all(from(a in Account, where: a.id in ^actor_ids))
    else
      []
    end
  end

  defp get_quarantine_info_for_test_cases([]), do: %{}

  defp get_quarantine_info_for_test_cases(test_case_ids) do
    query =
      from(e in TestCaseEvent,
        where: e.test_case_id in ^test_case_ids,
        where: e.event_type in ^@active_quarantine_event_types,
        group_by: e.test_case_id,
        select: %{
          test_case_id: e.test_case_id,
          actor_id: fragment("argMax(?, ?)", e.actor_id, e.inserted_at)
        }
      )

    events = ClickHouseRepo.all(query)

    actor_ids =
      events
      |> Enum.map(& &1.actor_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    accounts =
      if Enum.any?(actor_ids) do
        from(a in Account, where: a.id in ^actor_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    Map.new(events, fn event ->
      account = Map.get(accounts, event.actor_id)

      {event.test_case_id,
       %{
         actor_id: event.actor_id,
         actor_name: if(account, do: account.name)
       }}
    end)
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

  defp apply_quarantined_order(query, _, _),
    do: from([test_case: tc] in query, order_by: [desc: tc.last_ran_at, asc: tc.id])

  defp apply_quarantined_state_filter(query, nil),
    do: from([test_case: tc] in query, where: tc.state in ["muted", "skipped"])

  defp apply_quarantined_state_filter(query, state) when state in ["muted", "skipped"],
    do: from([test_case: tc] in query, where: tc.state == ^state)

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

  defp row_to_quarantined_test_case(row, quarantine_info) do
    %QuarantinedTestCase{
      id: row.id,
      name: row.name,
      module_name: row.module_name,
      suite_name: row.suite_name,
      quarantined_by_account_id: Map.get(quarantine_info, :actor_id),
      quarantined_by_account_name: Map.get(quarantine_info, :actor_name),
      last_ran_at: row.last_ran_at,
      last_run_id: row.last_run_id,
      last_status: row.last_status,
      state: row.state
    }
  end

  defp mark_test_case_runs_as_flaky([]), do: :ok

  defp mark_test_case_runs_as_flaky(runs) when is_list(runs) do
    ids = runs |> Enum.map(& &1.id) |> Enum.uniq()

    # FINAL is required because `test_case_runs` is a ReplacingMergeTree:
    # without it, a run that has already been re-inserted (e.g. previously
    # marked flaky) can return multiple versions for the same id until the
    # merge collapses them, and we'd re-insert every version.
    full_runs =
      ClickHouseRepo.all(from(tcr in TestCaseRun, hints: ["FINAL"], where: tcr.id in ^ids))

    updated_runs =
      Enum.map(full_runs, fn run ->
        run
        |> Map.from_struct()
        |> Map.drop([
          :__meta__,
          :ran_by_account,
          :failures,
          :repetitions,
          :crash_report,
          :attachments
        ])
        |> Map.merge(%{is_flaky: true, inserted_at: NaiveDateTime.utc_now()})
      end)

    TestCaseRun.Buffer.insert_all(updated_runs)
    :ok
  end

  defp any_test_case_run_flaky?(test_case_run_data) do
    Enum.any?(test_case_run_data, fn %{is_flaky: is_flaky} -> is_flaky end)
  end

  @doc """
  Returns the count of unique flaky run groups (scheme + commit_sha) for a test case.
  """
  def get_flaky_runs_groups_count_for_test_case(test_case_id) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        select: fragment("count(DISTINCT (scheme, git_commit_sha))")
      )

    ClickHouseRepo.one(query) || 0
  end

  @doc """
  Returns a map of test_case_id => count of unique flaky run groups for multiple test cases.
  """
  def get_flaky_runs_groups_counts_for_test_cases([]), do: %{}

  def get_flaky_runs_groups_counts_for_test_cases(test_case_ids) do
    query =
      from(tcr in TestCaseRun,
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
  def list_flaky_runs_for_test_case(test_case_id, params \\ %{}) do
    page = Map.get(params, :page, 1)
    page_size = Map.get(params, :page_size, 20)
    offset = (page - 1) * page_size

    groups_query =
      from(tcr in TestCaseRun,
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

    flaky_runs_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at]
      )

    flaky_runs =
      flaky_runs_query
      |> ClickHouseRepo.all()
      |> Enum.filter(fn run -> MapSet.member?(group_keys, {run.scheme, run.git_commit_sha}) end)

    run_ids = Enum.map(flaky_runs, & &1.id)

    failures = get_failures_for_runs(run_ids)
    failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

    repetitions = get_repetitions_for_runs(run_ids)
    repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

    runs_by_group = Enum.group_by(flaky_runs, fn run -> {run.scheme, run.git_commit_sha} end)

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

    total_count = get_flaky_runs_groups_count_for_test_case(test_case_id)

    meta = %{
      total_count: total_count,
      total_pages: if(total_count > 0, do: ceil(total_count / page_size), else: 0),
      current_page: page,
      page_size: page_size
    }

    {flaky_groups, meta}
  end

  def get_flaky_run_group_for_test_case_run(test_case_run) do
    flaky_runs_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_run.test_case_id,
        where: tcr.git_commit_sha == ^test_case_run.git_commit_sha,
        where: tcr.scheme == ^test_case_run.scheme,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at]
      )

    flaky_runs = ClickHouseRepo.all(flaky_runs_query)

    if Enum.empty?(flaky_runs) do
      nil
    else
      run_ids = Enum.map(flaky_runs, & &1.id)

      failures = get_failures_for_runs(run_ids)
      failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

      repetitions = get_repetitions_for_runs(run_ids)
      repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

      runs_with_details =
        Enum.map(flaky_runs, fn run ->
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
        latest_ran_at: flaky_runs |> Enum.map(& &1.ran_at) |> Enum.max(NaiveDateTime),
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
    current_flaky_runs = fetch_flaky_runs_for_test_run(test_run_id)

    cross_run_counterparts =
      get_cross_run_flaky_runs(test_run_id, current_flaky_runs)

    flaky_runs = current_flaky_runs ++ cross_run_counterparts

    run_ids = Enum.map(flaky_runs, & &1.id)

    failures = get_failures_for_runs(run_ids)
    failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

    repetitions = get_repetitions_for_runs(run_ids)
    repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

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

  defp fetch_flaky_runs_for_test_run(test_run_id) do
    slim_query =
      from(mv in TestCaseRunByTestRun,
        hints: ["FINAL"],
        where: mv.test_run_id == ^test_run_id and mv.is_flaky == true,
        order_by: [desc: mv.ran_at]
      )

    slim_results = ClickHouseRepo.all(slim_query)
    ids = Enum.map(slim_results, & &1.id)
    full_results = fetch_full_test_case_runs(slim_results)
    ordered_by_id = Map.new(full_results, &{&1.id, &1})
    ids |> Enum.map(&Map.get(ordered_by_id, &1)) |> Enum.reject(&is_nil/1)
  end

  defp get_cross_run_flaky_runs(_test_run_id, []), do: []

  defp get_cross_run_flaky_runs(test_run_id, current_flaky_runs) do
    test_case_ids = current_flaky_runs |> Enum.map(& &1.test_case_id) |> Enum.uniq()

    commit_shas =
      current_flaky_runs
      |> Enum.map(& &1.git_commit_sha)
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.uniq()

    if Enum.empty?(commit_shas) do
      []
    else
      query =
        from(tcr in TestCaseRun,
          where: tcr.test_run_id != ^test_run_id,
          where: tcr.git_commit_sha in ^commit_shas,
          where: tcr.test_case_id in ^test_case_ids,
          where: tcr.is_flaky == true,
          order_by: [desc: tcr.ran_at]
        )

      ClickHouseRepo.all(query)
    end
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
  Marks in-progress test runs older than 6 hours as failed.
  """
  def expire_stale_in_progress_test_runs do
    six_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -6, :hour)
    now = NaiveDateTime.utc_now()

    stale_runs =
      ClickHouseRepo.all(
        from(t in Test,
          hints: ["FINAL"],
          where: t.status == "in_progress",
          where: t.inserted_at < ^six_hours_ago
        )
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
