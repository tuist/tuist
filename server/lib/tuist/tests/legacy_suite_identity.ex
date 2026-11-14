defmodule Tuist.Tests.LegacySuiteIdentity do
  @moduledoc """
  Carries nested Swift Testing suites over to the identity they have now.

  A test in a nested suite is reported as `Outer/Inner/test()`. Reports used to
  keep only `Inner` as its suite, which xcodebuild's `-skip-testing` and
  `-only-testing` never match, so a quarantined test in a nested suite kept
  running. Recording the whole `Outer/Inner` path fixes that, but the suite is
  part of the test case ID (`Tuist.Tests.generate_test_case_id/4`), so these
  tests get a new ID.

  Which old ID belongs to which new one is only known once a report names the
  whole path, so the move happens then: the first time a test case is ingested
  under a nested suite, the ledgers its state is derived from (`test_case_events`
  and `automation_alert_events`) are copied from the old ID, keeping their
  timestamps. Its mute, skip, flaky flag and automation status then resolve
  exactly as they did. So are its coverage versions (`coverage_test_sources`),
  which coverage carry and test selection look up by ID: without them the test
  would have no evidence until a run recorded it again. Run history stays on
  the old ID.

  The old ID's rows are left as they are: CLIs older than this change still
  parse results locally under the innermost suite and match muted tests by it.
  """
  import Ecto.Query

  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.CoverageTestSource
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseEvent

  # One query parameter is capped at 128 KiB, about 3,000 UUIDs, so a module
  # with thousands of new nested tests is read in chunks.
  @lookup_batch_size 2_000

  # Test names are free text, so successor lookups bind fewer of them per query
  # than UUIDs. The test cases endpoint returns at most 500 per page, so a
  # page's candidates are still read in one pass over their modules: smaller
  # batches would read the same granules once per batch.
  @successor_batch_size 500

  @doc """
  Adapts muted Xcode `test_cases` (with `:id`, `:name`, `:module_name`,
  `:suite_name` and `:state`) for a CLI that parses results itself and names a
  nested suite by its innermost name, as every CLI before the whole path was
  recorded does. Such a CLI tolerates a muted test's failure only when the
  suite it gets back is the one it parsed, `Inner`, while skipping works with
  the whole `Outer/Inner` path it passes to `-skip-testing`.

  So a muted test in a nested suite is named by its innermost suite, and a
  muted legacy test case is left out once its test has a test case under the
  whole path: that one's state is the test's now, and unmuting it has to stop
  the CLI tolerating the failure. Two nested suites with the same innermost
  name and test look the same to these CLIs, as they always did. Test cases in
  any other state are returned as they are.
  """
  def for_innermost_suite_clients(project_id, test_cases) do
    superseded = superseded_legacy_ids(project_id, Enum.filter(test_cases, &legacy_candidate?/1))

    test_cases
    |> Enum.reject(&MapSet.member?(superseded, &1.id))
    |> Enum.map(fn
      %{state: "muted", suite_name: suite_name} = test_case when is_binary(suite_name) ->
        %{test_case | suite_name: suite_name |> String.split("/") |> List.last()}

      test_case ->
        test_case
    end)
  end

  defp legacy_candidate?(%{state: "muted", suite_name: suite_name}) when is_binary(suite_name),
    do: suite_name != "" and not String.contains?(suite_name, "/")

  defp legacy_candidate?(_test_case), do: false

  # The test cases under a whole path whose innermost suite, module and name
  # are a candidate's. The sorting key leads with the module, so only the
  # candidates' modules are read.
  defp superseded_legacy_ids(_project_id, []), do: MapSet.new()

  defp superseded_legacy_ids(project_id, candidates) do
    candidate_ids = MapSet.new(candidates, & &1.id)

    candidates
    |> Enum.chunk_every(@successor_batch_size)
    |> Enum.flat_map(fn chunk ->
      modules = chunk |> Enum.map(& &1.module_name) |> Enum.uniq()
      names = chunk |> Enum.map(& &1.name) |> Enum.uniq()

      ClickHouseRepo.all(
        from(test_case in TestCase,
          where: test_case.project_id == ^project_id,
          where: test_case.module_name in ^modules,
          where: test_case.name in ^names,
          where: fragment("position(?, '/') > 0", test_case.suite_name),
          distinct: true,
          select: {test_case.name, test_case.module_name, test_case.suite_name}
        ),
        multipart: true
      )
    end)
    |> MapSet.new(fn {name, module_name, suite_name} ->
      legacy_test_case_id(project_id, "xcode", name, module_name, suite_name)
    end)
    |> MapSet.intersection(candidate_ids)
  end

  @doc """
  The ID a test case had before nested suites were recorded whole, or `nil` when
  its suite isn't nested and the ID never changed. Only Xcode suites were ever
  truncated: other build systems report a `/` in their suite names as they always
  did (ExUnit describes such as `create_order/2`, Once and Bazel paths), so their
  IDs never changed.
  """
  def legacy_test_case_id(project_id, "xcode", name, module_name, suite_name) do
    case String.split(suite_name || "", "/") do
      [_not_nested] -> nil
      components -> Tests.generate_test_case_id(project_id, name, module_name, List.last(components))
    end
  end

  def legacy_test_case_id(_project_id, _build_system, _name, _module_name, _suite_name), do: nil

  @doc """
  Copies the state ledgers of the legacy IDs of `test_cases` (maps with `:id`,
  `:name`, `:module_name` and `:suite_name`, all ingested for the first time) to
  their new IDs, for a run of `build_system`. Returns the IDs that inherited a
  ledger.
  """
  def carry_over(_project_id, _build_system, []), do: MapSet.new()

  def carry_over(project_id, build_system, test_cases) do
    legacy_to_new =
      Enum.reduce(test_cases, %{}, fn test_case, acc ->
        case legacy_test_case_id(project_id, build_system, test_case.name, test_case.module_name, test_case.suite_name) do
          nil -> acc
          legacy_id -> Map.update(acc, legacy_id, [test_case.id], &[test_case.id | &1])
        end
      end)

    if map_size(legacy_to_new) == 0 do
      MapSet.new()
    else
      legacy_ids = Map.keys(legacy_to_new)
      events = copy_test_case_events(project_id, legacy_ids, legacy_to_new)
      alert_events = copy_alert_events(legacy_ids, legacy_to_new)
      copy_coverage_versions(project_id, legacy_ids, legacy_to_new)
      MapSet.union(events, alert_events)
    end
  end

  # A version is keyed by its test case and fingerprint and keeps its latest
  # run, so a copy written twice, or beside a version a newer run recorded for
  # the new ID, collapses into one row.
  defp copy_coverage_versions(project_id, legacy_ids, legacy_to_new) do
    rows =
      all_in_chunks(legacy_ids, fn ids ->
        from(s in CoverageTestSource,
          where: s.project_id == ^project_id,
          where: fragment("? IN (?)", s.test_case_id, type(^ids, {:array, Ecto.UUID})),
          select: %{
            project_id: s.project_id,
            git_repository_id: s.git_repository_id,
            test_case_id: s.test_case_id,
            fingerprint: s.fingerprint,
            paths: s.paths,
            unlined_paths: s.unlined_paths,
            passed: s.passed,
            test_run_id: s.test_run_id,
            git_commit_sha: s.git_commit_sha,
            ran_at: s.ran_at,
            inserted_at: s.inserted_at
          }
        )
      end)

    copies =
      for row <- rows, new_id <- Map.fetch!(legacy_to_new, row.test_case_id) do
        %{row | test_case_id: new_id}
      end

    copies
    |> Enum.chunk_every(2_000)
    |> Enum.each(&IngestRepo.insert_all(CoverageTestSource, &1))
  end

  defp copy_test_case_events(project_id, legacy_ids, legacy_to_new) do
    rows =
      all_in_chunks(legacy_ids, fn ids ->
        from(e in TestCaseEvent,
          where: e.project_id == ^project_id,
          where: fragment("? IN (?)", e.test_case_id, type(^ids, {:array, Ecto.UUID})),
          select: %{
            id: e.id,
            test_case_id: e.test_case_id,
            event_type: e.event_type,
            actor_id: e.actor_id,
            alert_id: e.alert_id,
            inserted_at: e.inserted_at
          }
        )
      end)

    copies =
      for row <- Enum.uniq_by(rows, & &1.id), new_id <- Map.fetch!(legacy_to_new, row.test_case_id) do
        Map.put(%{row | id: copied_id(row.inserted_at, row.id, new_id), test_case_id: new_id}, :project_id, project_id)
      end

    if copies != [], do: IngestRepo.insert_all(TestCaseEvent, copies)
    MapSet.new(copies, & &1.test_case_id)
  end

  defp copy_alert_events(legacy_ids, legacy_to_new) do
    rows =
      all_in_chunks(legacy_ids, fn ids ->
        from(e in AlertEvent,
          where: fragment("? IN (?)", e.test_case_id, type(^ids, {:array, Ecto.UUID})),
          select: %{
            id: e.id,
            alert_id: e.alert_id,
            baseline_generation: e.baseline_generation,
            test_case_id: e.test_case_id,
            status: e.status,
            triggered_at: e.triggered_at,
            recovered_at: e.recovered_at,
            inserted_at: e.inserted_at
          }
        )
      end)

    copies =
      for row <- Enum.uniq_by(rows, & &1.id), new_id <- Map.fetch!(legacy_to_new, row.test_case_id) do
        %{row | id: copied_id(row.inserted_at, row.id, new_id), test_case_id: new_id}
      end

    if copies != [], do: IngestRepo.insert_all(AlertEvent, copies)
    MapSet.new(copies, & &1.test_case_id)
  end

  defp all_in_chunks(ids, query_fun) do
    ids
    |> Enum.chunk_every(@lookup_batch_size)
    |> Enum.flat_map(&ClickHouseRepo.all(query_fun.(&1), multipart: true))
  end

  # Deterministic, so a report ingested twice (a retry, or two pods racing on
  # the same new test case) writes the same rows and `test_case_events`'
  # ReplacingMergeTree collapses them.
  defp copied_id(inserted_at, legacy_event_id, new_test_case_id) do
    Tuist.UUIDv7.deterministic(inserted_at, {:legacy_suite_identity, legacy_event_id, new_test_case_id})
  end
end
