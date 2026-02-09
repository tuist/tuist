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
    - For multi-row queries: a subquery with `GROUP BY id` and `max(inserted_at)` to identify
      the latest version of each row, then join back to get the full row data
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Alerts.Workers.FlakyThresholdCheckWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests.FlakyTestCase
  alias Tuist.Tests.QuarantinedTestCase
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseEvent
  alias Tuist.Tests.TestCaseFailure
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunRepetition
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.TestSuiteRun

  def valid_ci_providers, do: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

  def get_test(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    query =
      from(t in Test,
        where: t.id == ^id,
        order_by: [desc: t.inserted_at],
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test -> {:ok, Repo.preload(test, preload)}
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

  def list_test_runs(attrs) do
    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(Test, attrs, for: Test)

    results = Repo.preload(results, :ran_by_account)

    {results, meta}
  end

  def list_test_case_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestCaseRun, attrs, for: TestCaseRun)
  end

  def get_test_run_failures_count(test_run_id) do
    query =
      from f in TestCaseFailure,
        join: tcr in TestCaseRun,
        on: f.test_case_run_id == tcr.id,
        where: tcr.test_run_id == ^test_run_id,
        select: count(f.id)

    ClickHouseRepo.one(query) || 0
  end

  def list_test_run_failures(test_run_id, attrs) do
    query =
      from f in TestCaseFailure,
        join: tcr in TestCaseRun,
        on: f.test_case_run_id == tcr.id,
        where: tcr.test_run_id == ^test_run_id,
        select: %{
          id: f.id,
          test_case_run_id: f.test_case_run_id,
          message: f.message,
          path: f.path,
          line_number: f.line_number,
          issue_type: f.issue_type,
          inserted_at: f.inserted_at,
          test_case_name: tcr.name,
          test_module_name: tcr.module_name,
          test_suite_name: tcr.suite_name
        }

    Tuist.ClickHouseFlop.validate_and_run!(query, attrs, for: TestCaseFailure)
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
      String.to_existing_atom(provider)
    end
  end

  defp normalize_ci_provider(provider) when is_atom(provider), do: provider

  def create_test(attrs) do
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
        test_case_ids_with_flaky_run = create_test_modules(test, test_modules)

        schedule_flaky_threshold_check(test.project_id, test_case_ids_with_flaky_run)

        project = Tuist.Projects.get_project_by_id(test.project_id)

        Tuist.PubSub.broadcast(
          test,
          "#{project.account.name}/#{project.name}",
          :test_created
        )

        {:ok, test}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp schedule_flaky_threshold_check(_project_id, []), do: :ok

  defp schedule_flaky_threshold_check(project_id, test_case_ids) do
    %{project_id: project_id, test_case_ids: test_case_ids}
    |> FlakyThresholdCheckWorker.new(schedule_in: 5)
    |> Oban.insert!()

    :ok
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
  def create_test_cases(project_id, test_case_data_list) do
    now = NaiveDateTime.utc_now()

    test_case_ids_with_data =
      Enum.map(test_case_data_list, fn data ->
        id = generate_test_case_id(project_id, data.name, data.module_name, data.suite_name)
        {id, data}
      end)

    test_case_ids = Enum.map(test_case_ids_with_data, fn {id, _} -> id end)

    existing_data = get_project_test_cases(project_id, test_case_ids)

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
          inserted_at: now,
          recent_durations: new_durations,
          avg_duration: new_avg
        }

        acc = if current_run_is_flaky and not existing_is_flaky, do: [id | acc], else: acc
        {test_case, acc}
      end)

    IngestRepo.insert_all(TestCase, test_cases)

    test_case_id_map =
      Map.new(test_cases, fn tc ->
        {{tc.name, tc.module_name, tc.suite_name}, tc.id}
      end)

    {test_case_id_map, test_cases_with_flaky_run}
  end

  defp get_project_test_cases(_project_id, []), do: %{}

  defp get_project_test_cases(project_id, test_case_ids) do
    test_case_id_set = MapSet.new(test_case_ids)

    latest_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    query =
      from(test_case in TestCase,
        join: latest in subquery(latest_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        select: %{
          id: test_case.id,
          recent_durations: test_case.recent_durations,
          is_flaky: test_case.is_flaky
        }
      )

    query
    |> IngestRepo.all()
    |> Enum.filter(&(&1.id in test_case_id_set))
    |> Map.new(fn row -> {row.id, row} end)
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

  Only `is_flaky` and `is_quarantined` are valid update attributes.

  Creates test case events to track the state change.

  ## Parameters
  - `test_case_id` - the test case UUID to update
  - `update_attrs` - map with `:is_flaky` and/or `:is_quarantined` boolean values
  - `opts` - optional keyword list with `:actor_id` (account_id for user actions, nil for system)
  """
  def update_test_case(test_case_id, update_attrs, opts \\ []) when is_map(update_attrs) do
    valid_keys = [:is_flaky, :is_quarantined]
    filtered_attrs = Map.take(update_attrs, valid_keys)
    actor_id = Keyword.get(opts, :actor_id)

    with {:ok, test_case} <- get_test_case_by_id(test_case_id) do
      attrs =
        test_case
        |> Map.from_struct()
        |> Map.delete(:__meta__)
        |> Map.merge(filtered_attrs)
        |> Map.put(:inserted_at, NaiveDateTime.utc_now())

      {1, nil} = IngestRepo.insert_all(TestCase, [attrs])

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

      IngestRepo.insert_all(TestCaseEvent, events)
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
      case {Map.get(old_test_case, :is_quarantined, false), Map.get(new_attrs, :is_quarantined)} do
        {false, true} -> [:quarantined | events]
        {true, false} -> [:unquarantined | events]
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
      Tuist.ClickHouseFlop.validate_and_run!(from(e in TestCaseEvent, where: e.test_case_id == ^test_case_id), attrs,
        for: TestCaseEvent
      )

    events = Repo.preload(events, :actor)
    {events, meta}
  end

  @doc """
  Lists test case runs for a specific test case by its UUID.
  Returns a tuple of {test_case_runs, meta} with pagination info.
  """
  def list_test_case_runs_by_test_case_id(test_case_id, attrs) do
    base_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id
      )

    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRun)

    results = Repo.preload(results, :ran_by_account)

    {results, meta}
  end

  @doc """
  Gets a test case run by its UUID.
  Returns {:ok, test_case_run} or {:error, :not_found}.
  """
  def get_test_case_run_by_id(id) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.id == ^id,
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @doc """
  Lists test case runs by name components (module_name, name, and optionally suite_name).
  Supports filtering by is_flaky and pagination.

  ## Parameters
  - `project_id` - the project ID
  - `params` - map with required `:module_name` and `:name`, optional `:suite_name` and `:is_flaky`
  - `pagination` - map with `:page` and `:page_size`
  """
  def list_test_case_runs_by_name(project_id, params, pagination) do
    base_query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.module_name == ^params.module_name,
        where: tcr.name == ^params.name,
        order_by: [desc: tcr.ran_at]
      )

    base_query =
      if suite_name = Map.get(params, :suite_name) do
        from(tcr in base_query, where: tcr.suite_name == ^suite_name)
      else
        base_query
      end

    base_query =
      if Map.has_key?(params, :is_flaky) do
        from(tcr in base_query, where: tcr.is_flaky == ^params.is_flaky)
      else
        base_query
      end

    page = Map.get(pagination, :page, 1)
    page_size = Map.get(pagination, :page_size, 20)

    count_query = from(tcr in base_query, select: count(tcr.id))
    total_count = ClickHouseRepo.one(count_query) || 0
    total_pages = if total_count > 0, do: ceil(total_count / page_size), else: 1

    offset = (page - 1) * page_size

    results_query =
      from(tcr in base_query,
        limit: ^page_size,
        offset: ^offset
      )

    results = ClickHouseRepo.all(results_query)

    meta = %{
      has_next_page?: page < total_pages,
      has_previous_page?: page > 1,
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }

    {results, meta}
  end

  defp create_test_modules(test, test_modules) do
    test_case_run_data = get_test_case_run_data(test, test_modules)

    Enum.flat_map(test_modules, fn module_attrs ->
      module_id = UUIDv7.generate()
      module_name = Map.get(module_attrs, :name)

      test_suites = Map.get(module_attrs, :test_suites, [])
      test_cases = Map.get(module_attrs, :test_cases, [])

      test_suite_count = length(test_suites)
      test_case_count = length(test_cases)

      avg_test_case_duration = calculate_avg_test_case_duration(test_cases)

      module_test_case_run_data =
        test_case_run_data
        |> Enum.filter(fn {{_name, mod_name, _suite}, _data} -> mod_name == module_name end)
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
        inserted_at: NaiveDateTime.utc_now()
      }

      {:ok, _module_run} =
        %TestModuleRun{}
        |> TestModuleRun.create_changeset(module_run_attrs)
        |> IngestRepo.insert()

      suite_name_to_id = create_test_suites(test, module_id, test_suites, test_cases, module_test_case_run_data)

      create_test_cases_for_module(
        test,
        module_id,
        test_cases,
        suite_name_to_id,
        module_name,
        module_test_case_run_data
      )
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

    {test_case_data, historical_flaky_ids} =
      check_cross_run_flakiness(test, test_case_data)

    mark_test_case_runs_as_flaky(historical_flaky_ids)

    test_case_data = check_new_test_cases(test, test_case_data)

    Map.new(test_case_data, fn data ->
      {data.identity_key, %{status: data.status, is_flaky: data.is_flaky, is_new: data.is_new}}
    end)
  end

  defp check_cross_run_flakiness(%{is_ci: false}, test_case_data), do: {test_case_data, []}
  defp check_cross_run_flakiness(%{git_commit_sha: nil}, test_case_data), do: {test_case_data, []}

  defp check_cross_run_flakiness(test, test_case_data) do
    test_case_ids = Enum.map(test_case_data, & &1.test_case_id)
    existing_runs = get_existing_ci_runs_for_commit(test_case_ids, test.git_commit_sha)

    Enum.map_reduce(test_case_data, [], fn data, historical_ids ->
      case get_cross_run_flaky_ids(data, existing_runs) do
        [] ->
          {data, historical_ids}

        flaky_ids ->
          {%{data | is_flaky: true}, flaky_ids ++ historical_ids}
      end
    end)
  end

  defp get_cross_run_flaky_ids(data, existing_runs) do
    existing = Map.get(existing_runs, data.test_case_id, [])

    if data.status in ["success", "failure"] do
      existing
      |> Enum.filter(&(&1.status != data.status))
      |> Enum.map(& &1.id)
    else
      []
    end
  end

  defp get_existing_ci_runs_for_commit([], _git_commit_sha), do: %{}

  defp get_existing_ci_runs_for_commit(test_case_ids, git_commit_sha) do
    test_case_id_set = MapSet.new(test_case_ids)

    query =
      from(tcr in TestCaseRun,
        where: tcr.git_commit_sha == ^git_commit_sha,
        where: tcr.is_ci == true,
        where: tcr.status in ["success", "failure"],
        select: %{test_case_id: tcr.test_case_id, id: tcr.id, status: tcr.status}
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
      test_case_ids = Enum.map(test_case_data, & &1.test_case_id)
      existing_on_default_branch = get_test_case_ids_with_ci_runs_on_branch(test_case_ids, default_branch)

      Enum.map(test_case_data, fn data ->
        is_new = data.test_case_id not in existing_on_default_branch
        Map.put(data, :is_new, is_new)
      end)
    end
  end

  defp get_test_case_ids_with_ci_runs_on_branch([], _branch), do: MapSet.new()

  defp get_test_case_ids_with_ci_runs_on_branch(test_case_ids, branch) do
    test_case_id_set = MapSet.new(test_case_ids)
    ninety_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -90, :day)

    query =
      from(tcr in TestCaseRun,
        where: tcr.git_branch == ^branch,
        where: tcr.is_ci == true,
        where: tcr.ran_at >= ^ninety_days_ago,
        distinct: true,
        select: tcr.test_case_id
      )

    query
    |> ClickHouseRepo.all()
    |> Enum.filter(&(&1 in test_case_id_set))
    |> MapSet.new()
  end

  defp create_test_suites(test, module_id, test_suites, test_cases, test_case_run_data) do
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
          inserted_at: NaiveDateTime.utc_now()
        }

        updated_mapping = Map.put(acc, suite_name, suite_id)
        {suite_run, updated_mapping}
      end)

    IngestRepo.insert_all(TestSuiteRun, test_suite_runs)
    suite_name_to_id
  end

  defp create_test_cases_for_module(test, module_id, test_cases, suite_name_to_id, module_name, test_case_run_data) do
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

    {test_case_id_map, test_case_ids_with_flaky_run} = create_test_cases(test.project_id, test_case_data_list)

    {test_case_runs, all_failures, all_repetitions} =
      Enum.reduce(test_cases, {[], [], []}, fn case_attrs, {runs_acc, failures_acc, reps_acc} ->
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""

        test_suite_run_id = Map.get(suite_name_to_id, suite_name)

        test_case_run_id = UUIDv7.generate()

        case_name = Map.get(case_attrs, :name)
        identity_key = {case_name, module_name, suite_name}
        test_case_id = Map.get(test_case_id_map, identity_key)

        repetitions = Map.get(case_attrs, :repetitions, [])

        %{status: status, is_flaky: is_flaky, is_new: is_new} = Map.get(test_case_run_data, identity_key)

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
          duration: Map.get(case_attrs, :duration, 0),
          inserted_at: NaiveDateTime.utc_now(),
          module_name: module_name,
          suite_name: suite_name || ""
        }

        failures = Map.get(case_attrs, :failures, [])

        test_case_failures =
          Enum.map(failures, fn failure_attrs ->
            %{
              id: UUIDv7.generate(),
              test_case_run_id: test_case_run_id,
              message: Map.get(failure_attrs, :message),
              path: Map.get(failure_attrs, :path),
              line_number: Map.get(failure_attrs, :line_number),
              issue_type: Map.get(failure_attrs, :issue_type) || "unknown",
              inserted_at: NaiveDateTime.utc_now()
            }
          end)

        test_case_repetitions =
          Enum.map(repetitions, fn rep_attrs ->
            %{
              id: UUIDv7.generate(),
              test_case_run_id: test_case_run_id,
              repetition_number: Map.get(rep_attrs, :repetition_number),
              name: Map.get(rep_attrs, :name),
              status: Map.get(rep_attrs, :status),
              duration: Map.get(rep_attrs, :duration, 0),
              inserted_at: NaiveDateTime.utc_now()
            }
          end)

        {[test_case_run | runs_acc], test_case_failures ++ failures_acc, test_case_repetitions ++ reps_acc}
      end)

    IngestRepo.insert_all(TestCaseRun, test_case_runs)
    IngestRepo.insert_all(TestCaseFailure, all_failures)

    if Enum.any?(all_repetitions) do
      IngestRepo.insert_all(TestCaseRunRepetition, all_repetitions)
    end

    create_first_run_events(test_case_runs)

    test_case_ids_with_flaky_run
  end

  defp create_first_run_events(test_case_runs) do
    new_test_case_runs = Enum.filter(test_case_runs, & &1.is_new)

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

      IngestRepo.insert_all(TestCaseEvent, events)
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
  """
  def list_test_cases(project_id, attrs) do
    two_weeks_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -14, :day)

    latest_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        where: test_case.last_ran_at >= ^two_weeks_ago,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    base_query =
      from(test_case in TestCase,
        join: latest in subquery(latest_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at
      )

    Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCase)
  end

  @doc """
  Lists test cases that are marked as flaky for a project.
  Queries test_cases where is_flaky = true and joins with test_case_runs for aggregated stats.
  """
  def list_flaky_test_cases(project_id, attrs) do
    page = Map.get(attrs, :page, 1)
    page_size = Map.get(attrs, :page_size, 20)
    order_by = attrs |> Map.get(:order_by, [:flaky_runs_count]) |> List.first()
    order_direction = attrs |> Map.get(:order_directions, [:desc]) |> List.first()
    filters = Map.get(attrs, :filters, [])
    offset = (page - 1) * page_size

    search_term = extract_search_term(filters)

    results =
      project_id
      |> build_flaky_test_cases_query(search_term)
      |> apply_flaky_order(order_by, order_direction)
      |> from(limit: ^page_size, offset: ^offset)
      |> ClickHouseRepo.all()

    flaky_tests = Enum.map(results, &row_to_flaky_test_case/1)

    total_count =
      project_id
      |> build_flaky_test_cases_count_query(search_term)
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

  defp build_flaky_test_cases_query(project_id, search_term) do
    stats_subquery =
      from(test_case_run in TestCaseRun,
        where: test_case_run.project_id == ^project_id and test_case_run.is_flaky == true,
        group_by: test_case_run.test_case_id,
        select: %{
          test_case_id: test_case_run.test_case_id,
          flaky_runs_count: count(test_case_run.id),
          last_flaky_at: max(test_case_run.inserted_at),
          last_flaky_run_id: fragment("argMax(test_run_id, inserted_at)")
        }
      )

    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    base_query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        left_join: stats in subquery(stats_subquery),
        on: test_case.id == stats.test_case_id,
        where: test_case.is_flaky == true,
        select: %{
          id: test_case.id,
          name: test_case.name,
          module_name: test_case.module_name,
          suite_name: test_case.suite_name,
          flaky_runs_count: coalesce(stats.flaky_runs_count, 0),
          last_flaky_at: stats.last_flaky_at,
          last_flaky_run_id: stats.last_flaky_run_id
        }
      )

    apply_name_search(base_query, search_term)
  end

  defp build_flaky_test_cases_count_query(project_id, search_term) do
    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    base_query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        where: test_case.is_flaky == true,
        select: count(test_case.id)
      )

    apply_name_search(base_query, search_term)
  end

  defp apply_name_search(query, nil), do: query
  defp apply_name_search(query, term), do: from(q in query, where: ilike(q.name, ^"%#{term}%"))

  defp apply_flaky_order(query, :flaky_runs_count, :asc),
    do: from([tc, _latest, stats] in query, order_by: [asc: coalesce(stats.flaky_runs_count, 0)])

  defp apply_flaky_order(query, :last_flaky_at, :desc),
    do: from([tc, _latest, stats] in query, order_by: [desc: stats.last_flaky_at])

  defp apply_flaky_order(query, :last_flaky_at, :asc),
    do: from([tc, _latest, stats] in query, order_by: [asc: stats.last_flaky_at])

  defp apply_flaky_order(query, :name, :desc), do: from([tc, _latest, _stats] in query, order_by: [desc: tc.name])
  defp apply_flaky_order(query, :name, :asc), do: from([tc, _latest, _stats] in query, order_by: [asc: tc.name])

  defp apply_flaky_order(query, _, _),
    do: from([tc, _latest, stats] in query, order_by: [desc: coalesce(stats.flaky_runs_count, 0)])

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
  def list_quarantined_test_cases(project_id, attrs) do
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

    results =
      project_id
      |> build_quarantined_test_cases_query(search_term, quarantined_by_filter, module_name_filter, suite_name_filter)
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
        suite_name_filter
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

  defp build_quarantined_test_cases_query(
         project_id,
         search_term,
         quarantined_by_filter,
         module_name_filter,
         suite_name_filter
       ) do
    quarantined_ids_subquery =
      from(tc in TestCase,
        where: tc.project_id == ^project_id and tc.is_quarantined == true,
        group_by: tc.id,
        select: tc.id
      )

    last_run_subquery =
      from(test_case_run in TestCaseRun,
        where: test_case_run.test_case_id in subquery(quarantined_ids_subquery),
        group_by: test_case_run.test_case_id,
        select: %{
          test_case_id: test_case_run.test_case_id,
          last_ran_at: max(test_case_run.ran_at),
          last_run_id: fragment("argMax(test_run_id, ran_at)")
        }
      )

    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id and test_case.is_quarantined == true,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    latest_quarantine_event_subquery =
      from(e in TestCaseEvent,
        where: e.event_type == "quarantined",
        group_by: e.test_case_id,
        select: %{test_case_id: e.test_case_id, max_inserted_at: max(e.inserted_at)}
      )

    quarantine_info_subquery =
      from(e in TestCaseEvent,
        join: latest in subquery(latest_quarantine_event_subquery),
        on: e.test_case_id == latest.test_case_id and e.inserted_at == latest.max_inserted_at,
        select: %{test_case_id: e.test_case_id, actor_id: e.actor_id}
      )

    base_query =
      from(test_case in TestCase,
        as: :test_case,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        left_join: stats in subquery(last_run_subquery),
        as: :stats,
        on: test_case.id == stats.test_case_id,
        left_join: quarantine in subquery(quarantine_info_subquery),
        as: :quarantine,
        on: test_case.id == quarantine.test_case_id,
        where: test_case.is_quarantined == true,
        select: %{
          id: test_case.id,
          name: test_case.name,
          module_name: test_case.module_name,
          suite_name: test_case.suite_name,
          last_ran_at: coalesce(stats.last_ran_at, test_case.last_ran_at),
          last_run_id: stats.last_run_id
        }
      )

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
         suite_name_filter
       ) do
    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id and test_case.is_quarantined == true,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    latest_quarantine_event_subquery =
      from(e in TestCaseEvent,
        where: e.event_type == "quarantined",
        group_by: e.test_case_id,
        select: %{test_case_id: e.test_case_id, max_inserted_at: max(e.inserted_at)}
      )

    quarantine_info_subquery =
      from(e in TestCaseEvent,
        join: latest in subquery(latest_quarantine_event_subquery),
        on: e.test_case_id == latest.test_case_id and e.inserted_at == latest.max_inserted_at,
        select: %{test_case_id: e.test_case_id, actor_id: e.actor_id}
      )

    base_query =
      from(test_case in TestCase,
        as: :test_case,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        left_join: quarantine in subquery(quarantine_info_subquery),
        as: :quarantine,
        on: test_case.id == quarantine.test_case_id,
        where: test_case.is_quarantined == true,
        select: count(test_case.id)
      )

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
        where: tc.project_id == ^project_id and tc.is_quarantined == true,
        group_by: tc.id,
        select: tc.id
      )

    latest_quarantine_subquery =
      from(e in TestCaseEvent,
        where: e.test_case_id in subquery(quarantined_ids_subquery),
        where: e.event_type == "quarantined",
        group_by: e.test_case_id,
        select: %{test_case_id: e.test_case_id, max_inserted_at: max(e.inserted_at)}
      )

    actor_ids =
      ClickHouseRepo.all(
        from(e in TestCaseEvent,
          join: latest in subquery(latest_quarantine_subquery),
          on: e.test_case_id == latest.test_case_id and e.inserted_at == latest.max_inserted_at,
          where: not is_nil(e.actor_id),
          select: e.actor_id,
          distinct: true
        )
      )

    if Enum.any?(actor_ids) do
      Repo.all(from(a in Account, where: a.id in ^actor_ids))
    else
      []
    end
  end

  defp get_quarantine_info_for_test_cases([]), do: %{}

  defp get_quarantine_info_for_test_cases(test_case_ids) do
    latest_quarantine_subquery =
      from(e in TestCaseEvent,
        where: e.test_case_id in ^test_case_ids,
        where: e.event_type == "quarantined",
        group_by: e.test_case_id,
        select: %{test_case_id: e.test_case_id, max_inserted_at: max(e.inserted_at)}
      )

    query =
      from(e in TestCaseEvent,
        join: latest in subquery(latest_quarantine_subquery),
        on: e.test_case_id == latest.test_case_id and e.inserted_at == latest.max_inserted_at,
        select: %{test_case_id: e.test_case_id, actor_id: e.actor_id}
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

  defp apply_quarantined_order(query, :last_ran_at, :desc),
    do: from([test_case: tc, stats: stats] in query, order_by: [desc: coalesce(stats.last_ran_at, tc.last_ran_at)])

  defp apply_quarantined_order(query, :last_ran_at, :asc),
    do: from([test_case: tc, stats: stats] in query, order_by: [asc: coalesce(stats.last_ran_at, tc.last_ran_at)])

  defp apply_quarantined_order(query, :name, :desc), do: from([test_case: tc] in query, order_by: [desc: tc.name])

  defp apply_quarantined_order(query, :name, :asc), do: from([test_case: tc] in query, order_by: [asc: tc.name])

  defp apply_quarantined_order(query, _, _),
    do: from([test_case: tc, stats: stats] in query, order_by: [desc: coalesce(stats.last_ran_at, tc.last_ran_at)])

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
      last_run_id: row.last_run_id
    }
  end

  defp mark_test_case_runs_as_flaky(test_case_run_ids) when is_list(test_case_run_ids) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.id in ^test_case_run_ids
      )

    existing_runs = ClickHouseRepo.all(query)

    updated_runs =
      Enum.map(existing_runs, fn run ->
        run
        |> Map.from_struct()
        |> Map.drop([:__meta__, :ran_by_account])
        |> Map.merge(%{is_flaky: true, inserted_at: NaiveDateTime.utc_now()})
      end)

    if Enum.any?(updated_runs) do
      IngestRepo.insert_all(TestCaseRun, updated_runs)
    else
      :ok
    end
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
    flaky_runs_query =
      from(tcr in TestCaseRun,
        where: tcr.test_run_id == ^test_run_id,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at]
      )

    flaky_runs = ClickHouseRepo.all(flaky_runs_query)

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

  def get_failures_for_runs([]), do: []

  def get_failures_for_runs(run_ids) do
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

  def get_repetitions_for_runs([]), do: []

  def get_repetitions_for_runs(run_ids) do
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
  Clears stale flaky flags from test cases.

  A test case's is_flaky flag is considered stale if there have been no flaky
  test case runs for that test case in the last 14 days.

  Returns {:ok, count} where count is the number of test cases that had their
  is_flaky flag cleared.
  """
  def clear_stale_flaky_flags do
    fourteen_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -14, :day)

    recent_flaky_subquery =
      from(test_case_run in TestCaseRun,
        where: test_case_run.is_flaky == true and test_case_run.inserted_at >= ^fourteen_days_ago,
        group_by: test_case_run.test_case_id,
        select: test_case_run.test_case_id
      )

    latest_test_case_subquery =
      from(test_case in TestCase,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        where: test_case.is_flaky == true,
        where: test_case.id not in subquery(recent_flaky_subquery)
      )

    stale_test_cases = ClickHouseRepo.all(query)
    now = NaiveDateTime.utc_now()

    test_cases_to_update =
      Enum.map(stale_test_cases, fn test_case ->
        test_case
        |> Map.from_struct()
        |> Map.delete(:__meta__)
        |> Map.merge(%{is_flaky: false, inserted_at: now})
      end)

    IngestRepo.insert_all(TestCase, test_cases_to_update)

    if Enum.any?(stale_test_cases) do
      events =
        Enum.map(stale_test_cases, fn test_case ->
          %{
            id: UUIDv7.generate(),
            test_case_id: test_case.id,
            event_type: "unmarked_flaky",
            actor_id: nil,
            inserted_at: now
          }
        end)

      IngestRepo.insert_all(TestCaseEvent, events)
    end

    {:ok, length(test_cases_to_update)}
  end
end
