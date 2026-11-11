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
  exactly as they did. Run history stays on the old ID.

  The old ID's rows are left as they are: CLIs older than this change still
  parse results locally under the innermost suite and match muted tests by it.
  """
  import Ecto.Query

  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseEvent

  @doc """
  The ID a test case had before nested suites were recorded whole, or `nil` when
  its suite isn't nested and the ID never changed.
  """
  def legacy_test_case_id(project_id, name, module_name, suite_name) do
    case String.split(suite_name || "", "/") do
      [_not_nested] -> nil
      components -> Tests.generate_test_case_id(project_id, name, module_name, List.last(components))
    end
  end

  @doc """
  Copies the state ledgers of the legacy IDs of `test_cases` (maps with `:id`,
  `:name`, `:module_name` and `:suite_name`, all ingested for the first time) to
  their new IDs. Returns the IDs that inherited a ledger.
  """
  def carry_over(_project_id, []), do: MapSet.new()

  def carry_over(project_id, test_cases) do
    legacy_to_new =
      Enum.reduce(test_cases, %{}, fn test_case, acc ->
        case legacy_test_case_id(project_id, test_case.name, test_case.module_name, test_case.suite_name) do
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
      MapSet.union(events, alert_events)
    end
  end

  defp copy_test_case_events(project_id, legacy_ids, legacy_to_new) do
    rows =
      ClickHouseRepo.all(
        from(e in TestCaseEvent,
          where: e.project_id == ^project_id,
          where: fragment("? IN (?)", e.test_case_id, type(^legacy_ids, {:array, Ecto.UUID})),
          select: %{
            id: e.id,
            test_case_id: e.test_case_id,
            event_type: e.event_type,
            actor_id: e.actor_id,
            alert_id: e.alert_id,
            inserted_at: e.inserted_at
          }
        ),
        multipart: true
      )

    copies =
      for row <- Enum.uniq_by(rows, & &1.id), new_id <- Map.fetch!(legacy_to_new, row.test_case_id) do
        Map.put(%{row | id: copied_id(row.inserted_at, row.id, new_id), test_case_id: new_id}, :project_id, project_id)
      end

    if copies != [], do: IngestRepo.insert_all(TestCaseEvent, copies)
    MapSet.new(copies, & &1.test_case_id)
  end

  defp copy_alert_events(legacy_ids, legacy_to_new) do
    rows =
      ClickHouseRepo.all(
        from(e in AlertEvent,
          where: fragment("? IN (?)", e.test_case_id, type(^legacy_ids, {:array, Ecto.UUID})),
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
        ),
        multipart: true
      )

    copies =
      for row <- Enum.uniq_by(rows, & &1.id), new_id <- Map.fetch!(legacy_to_new, row.test_case_id) do
        %{row | id: copied_id(row.inserted_at, row.id, new_id), test_case_id: new_id}
      end

    if copies != [], do: IngestRepo.insert_all(AlertEvent, copies)
    MapSet.new(copies, & &1.test_case_id)
  end

  # Deterministic, so a report ingested twice (a retry, or two pods racing on
  # the same new test case) writes the same rows and `test_case_events`'
  # ReplacingMergeTree collapses them.
  defp copied_id(inserted_at, legacy_event_id, new_test_case_id) do
    Tuist.UUIDv7.deterministic(inserted_at, {:legacy_suite_identity, legacy_event_id, new_test_case_id})
  end
end
