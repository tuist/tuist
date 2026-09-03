defmodule Tuist.Tests.StressNewTests do
  @moduledoc """
  Server half of the stress gate for newly added tests.

  The client runs the suite, sends the test cases that executed, and gets back
  the subset that has never run in CI on the project's default branch, each
  priced with the number of repetitions its own duration earns on the project's
  curve. The guards whose inputs only the server holds (the default branch and
  its history, the size of the project's inventory) are decided here and
  returned as a signal the client prints. The candidate cap is applied here too,
  so both clients only have to run what they are handed and stop at the
  wall-clock ceiling.

  The pass the client runs afterwards is recorded on the test run and in
  `test_run_stress_candidates`, never as `test_case_run_repetitions`, so the
  aggregates, auto-marking, cooldown and alerts that attribute flakiness to a
  test case never see a solicited repetition.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseBranchPresence
  alias Tuist.Tests.TestRunStressCandidate
  alias Tuist.Tests.TestRunStressRepetition

  @modes ~w(report enforce)
  @run_outcomes ~w(passed disagreed skipped no_candidates)
  @skip_reasons ~w(first_pass_failed no_default_branch no_default_branch_history bulk_change verdict_unavailable)
  @guard_kinds ~w(no_default_branch no_default_branch_history bulk_change)
  @excluded_reasons ~w(too_slow candidate_cap)

  @batch_size 2_000

  def modes, do: @modes
  def run_outcomes, do: @run_outcomes
  def skip_reasons, do: @skip_reasons
  def guard_kinds, do: @guard_kinds
  def excluded_reasons, do: @excluded_reasons

  def parameters(project) do
    %{
      repetition_curve:
        project.stress_new_tests_repetition_curve
        |> Enum.map(fn bucket ->
          %{
            max_duration_ms: fetch_bucket(bucket, :max_duration_ms),
            repetitions: fetch_bucket(bucket, :repetitions)
          }
        end)
        |> Enum.sort_by(& &1.max_duration_ms),
      candidate_cap: project.stress_new_tests_candidate_cap,
      wall_clock_ceiling_ms: project.stress_new_tests_wall_clock_ceiling_ms,
      bulk_change_ratio: project.stress_new_tests_bulk_change_ratio,
      bulk_change_floor: project.stress_new_tests_bulk_change_floor
    }
  end

  defp fetch_bucket(bucket, key), do: Map.get(bucket, key) || Map.fetch!(bucket, Atom.to_string(key))

  @doc """
  Decides which of `test_cases` (maps with `name`, `suite_name`, `module_name`
  and `duration` in milliseconds) the gate should stress for `project`.
  """
  def verdict(project, account, test_cases) do
    parameters = parameters(project)

    if FeatureFlags.stress_new_tests_enabled?(account) do
      project
      |> compute(dedupe(test_cases), parameters)
      |> Map.put(:enabled, true)
      |> Map.put(:parameters, parameters)
    else
      # inventory_count is required by the response schema and non-optional in the
      # generated client, so omitting it here turned "not entitled" into a decoding
      # failure and a spurious warning on every unentitled run.
      %{enabled: false, guard: nil, candidates: [], inventory_count: 0, parameters: parameters}
    end
  end

  defp compute(project, test_cases, parameters) do
    default_branch = project.default_branch

    if blank?(default_branch) do
      guard("no_default_branch", length(test_cases), 0)
    else
      inventory_count = default_branch_inventory_count(project.id, default_branch)

      if inventory_count == 0 do
        guard("no_default_branch_history", length(test_cases), 0)
      else
        new_test_cases = reject_known(project.id, default_branch, test_cases)
        new_count = length(new_test_cases)

        if new_count >= parameters.bulk_change_floor and
             new_count > parameters.bulk_change_ratio * inventory_count do
          guard("bulk_change", new_count, inventory_count)
        else
          %{guard: nil, candidates: price(new_test_cases, parameters), inventory_count: inventory_count}
        end
      end
    end
  end

  defp guard(kind, new_count, inventory_count) do
    %{
      guard: %{kind: kind, new_count: new_count, inventory_count: inventory_count},
      candidates: [],
      inventory_count: inventory_count
    }
  end

  defp dedupe(test_cases) do
    test_cases
    |> Enum.map(fn test_case ->
      %{
        name: Map.fetch!(test_case, :name),
        suite_name: Map.get(test_case, :suite_name) || "",
        module_name: Map.fetch!(test_case, :module_name),
        duration: Map.get(test_case, :duration) || 0
      }
    end)
    |> Enum.uniq_by(&identity/1)
  end

  defp identity(test_case), do: {test_case.module_name, test_case.suite_name, test_case.name}

  defp reject_known(project_id, default_branch, test_cases) do
    by_id =
      Map.new(test_cases, fn test_case ->
        {Tests.generate_test_case_id(project_id, test_case.name, test_case.module_name, test_case.suite_name), test_case}
      end)

    known =
      by_id
      |> Map.keys()
      |> Enum.chunk_every(@batch_size)
      |> Enum.flat_map(&known_test_case_ids(project_id, default_branch, &1))
      |> MapSet.new()

    by_id
    |> Enum.reject(fn {id, _} -> MapSet.member?(known, id) end)
    |> Enum.map(fn {_, test_case} -> test_case end)
  end

  # "Ever run in CI on the default branch", with no trailing window: selective
  # testing keeps unchanged targets off the default branch for as long as their
  # inputs are stable, so a window would read a dormant module as new. The
  # rows are retained indefinitely and the ids are bound as one `Array(UUID)`
  # so a large suite stays within ClickHouse's parameter limits.
  defp known_test_case_ids(project_id, default_branch, ids) do
    ClickHouseRepo.all(
      from(bp in TestCaseBranchPresence,
        where: bp.project_id == ^project_id,
        where: bp.git_branch == ^default_branch,
        where: bp.is_ci == true,
        where: fragment("? IN (?)", bp.test_case_id, type(^ids, {:array, Ecto.UUID})),
        distinct: true,
        select: bp.test_case_id
      ),
      multipart: true
    )
  end

  defp default_branch_inventory_count(project_id, default_branch) do
    ClickHouseRepo.one(
      from(bp in TestCaseBranchPresence,
        where: bp.project_id == ^project_id,
        where: bp.git_branch == ^default_branch,
        where: bp.is_ci == true,
        select: fragment("uniqExact(?)", bp.test_case_id)
      )
    ) || 0
  end

  defp price(new_test_cases, parameters) do
    {candidates, _stressed} =
      new_test_cases
      |> Enum.sort_by(&identity/1)
      |> Enum.map_reduce(0, fn test_case, stressed ->
        repetitions = repetitions_for(test_case.duration, parameters.repetition_curve)

        cond do
          repetitions == 0 ->
            {candidate(test_case, 0, "too_slow"), stressed}

          stressed >= parameters.candidate_cap ->
            {candidate(test_case, 0, "candidate_cap"), stressed}

          true ->
            {candidate(test_case, repetitions, nil), stressed + 1}
        end
      end)

    candidates
  end

  defp candidate(test_case, repetitions, excluded_reason) do
    test_case
    |> Map.take([:name, :suite_name, :module_name])
    |> Map.put(:repetitions, repetitions)
    |> Map.put(:excluded_reason, excluded_reason)
  end

  @doc """
  Repetitions a test case of `duration_ms` earns on `curve`, or 0 when it is
  slower than the curve's last bucket and is excluded.
  """
  def repetitions_for(duration_ms, curve) do
    duration_ms = duration_ms || 0

    case Enum.find(curve, &(duration_ms <= &1.max_duration_ms)) do
      nil -> 0
      bucket -> bucket.repetitions
    end
  end

  @doc """
  Maps the `stress_new_tests` block a client reports with a test run onto the
  `test_runs` columns.
  """
  def run_attrs(nil), do: %{}

  def run_attrs(stress) do
    %{
      stress_mode: Map.get(stress, :mode) || "",
      stress_outcome: Map.get(stress, :outcome) || "",
      stress_skip_reason: Map.get(stress, :skip_reason) || "",
      stress_new_count: Map.get(stress, :new_count) || 0,
      stress_stressed_count: Map.get(stress, :stressed_count) || 0,
      stress_excluded_count: Map.get(stress, :excluded_count) || 0,
      stress_inventory_count: Map.get(stress, :inventory_count) || 0
    }
  end

  @doc """
  Folds a shard's `stress_new_tests` block into the merged run. Shards
  partition the suite, so counts add up and the run takes the worst outcome
  any shard reported.
  """
  def merge_run_attrs(%Test{} = existing, nil), do: Map.take(existing, Map.keys(run_attrs(%{})))

  def merge_run_attrs(%Test{} = existing, stress) do
    incoming = run_attrs(stress)

    %{
      stress_mode: first_present(existing.stress_mode, incoming.stress_mode),
      stress_outcome: worst_outcome(existing.stress_outcome, incoming.stress_outcome),
      stress_skip_reason: first_present(existing.stress_skip_reason, incoming.stress_skip_reason),
      stress_new_count: existing.stress_new_count + incoming.stress_new_count,
      stress_stressed_count: existing.stress_stressed_count + incoming.stress_stressed_count,
      stress_excluded_count: existing.stress_excluded_count + incoming.stress_excluded_count,
      stress_inventory_count: max(existing.stress_inventory_count, incoming.stress_inventory_count)
    }
  end

  defp first_present(current, incoming) do
    if blank?(current), do: incoming, else: current
  end

  @outcome_severity %{"" => 0, "no_candidates" => 1, "passed" => 2, "skipped" => 3, "disagreed" => 4}

  defp worst_outcome(a, b) do
    Enum.max_by([a, b], &Map.get(@outcome_severity, &1, 0))
  end

  def insert_candidates(%Test{}, nil), do: :ok

  def insert_candidates(%Test{id: test_run_id, project_id: project_id}, stress) do
    now = NaiveDateTime.utc_now()
    test_cases = Map.get(stress, :test_cases, [])

    rows =
      Enum.map(test_cases, fn test_case ->
        name = Map.fetch!(test_case, :name)
        suite_name = Map.get(test_case, :suite_name) || ""
        module_name = Map.fetch!(test_case, :module_name)

        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          project_id: project_id,
          test_case_id: Tests.generate_test_case_id(project_id, name, module_name, suite_name),
          name: name,
          suite_name: suite_name,
          module_name: module_name,
          repetitions: Map.get(test_case, :repetitions) || 0,
          failed_repetitions: Map.get(test_case, :failed_repetitions) || 0,
          outcome: Map.fetch!(test_case, :outcome),
          is_quarantined: Map.get(test_case, :is_quarantined) || false,
          inserted_at: now
        }
      end)

    if rows != [] do
      IngestRepo.insert_all(TestRunStressCandidate, rows)
    end

    insert_repetitions(test_run_id, project_id, test_cases, now)

    :ok
  end

  defp insert_repetitions(test_run_id, project_id, test_cases, now) do
    rows =
      Enum.flat_map(test_cases, fn test_case ->
        test_case_id =
          Tests.generate_test_case_id(
            project_id,
            Map.fetch!(test_case, :name),
            Map.fetch!(test_case, :module_name),
            Map.get(test_case, :suite_name) || ""
          )

        test_case
        |> Map.get(:repetition_results, [])
        |> Enum.map(fn repetition ->
          failure = Map.get(repetition, :failure) || %{}

          %{
            id: UUIDv7.generate(),
            test_run_id: test_run_id,
            project_id: project_id,
            test_case_id: test_case_id,
            repetition_number: Map.fetch!(repetition, :repetition_number),
            status: Map.fetch!(repetition, :status),
            duration: Map.get(repetition, :duration) || 0,
            failure_message: Map.get(failure, :message) || "",
            failure_path: Map.get(failure, :path) || "",
            failure_line_number: Map.get(failure, :line_number) || 0,
            failure_issue_type: Map.get(failure, :issue_type) || "",
            inserted_at: now
          }
        end)
      end)

    if rows != [] do
      IngestRepo.insert_all(TestRunStressRepetition, rows)
    end
  end

  def list_candidates(test_run_id) do
    from(c in TestRunStressCandidate,
      where: c.test_run_id == ^test_run_id,
      order_by: [asc: c.module_name, asc: c.suite_name, asc: c.name, asc: c.inserted_at]
    )
    |> ClickHouseRepo.all()
    |> Enum.uniq_by(&{&1.module_name, &1.suite_name, &1.name})
  end

  @doc """
  Every repetition the gate ran for `test_run_id`, grouped by test case id and
  ordered, so a candidate can be rendered with its own pass/fail sequence.
  """
  def repetitions_by_test_case(test_run_id) do
    from(r in TestRunStressRepetition,
      where: r.test_run_id == ^test_run_id,
      order_by: [asc: r.test_case_id, asc: r.repetition_number, asc: r.inserted_at]
    )
    |> ClickHouseRepo.all()
    |> Enum.uniq_by(&{&1.test_case_id, &1.repetition_number})
    |> Enum.group_by(& &1.test_case_id)
  end

  @doc """
  The repetitions the gate ran for one test case in one test run, in order.
  """
  def repetitions_for_test_case(_test_run_id, nil), do: []

  def repetitions_for_test_case(test_run_id, test_case_id) do
    from(r in TestRunStressRepetition,
      where: r.test_run_id == ^test_run_id,
      where: r.test_case_id == ^test_case_id,
      order_by: [asc: r.repetition_number, asc: r.inserted_at]
    )
    |> ClickHouseRepo.all()
    |> Enum.uniq_by(& &1.repetition_number)
  end

  @doc """
  The candidates the gate holds against the run, with their repetitions attached,
  so the dashboard can render them beside the run's own failures.
  """
  def blocking_candidates_with_repetitions(test_run_id) do
    candidates = test_run_id |> list_candidates() |> Enum.filter(&blocking_candidate?/1)

    if candidates == [] do
      []
    else
      repetitions = repetitions_by_test_case(test_run_id)

      Enum.map(candidates, fn candidate ->
        Map.put(candidate, :stress_repetitions, Map.get(repetitions, candidate.test_case_id, []))
      end)
    end
  end

  @doc """
  Every candidate the gate examined for `test_run_id`, keyed by the identity the
  test case runs share, so a run's test case list can be badged without a join.
  """
  def candidates_by_identity(test_run_id) do
    test_run_id
    |> list_candidates()
    |> Map.new(&{{&1.module_name, &1.suite_name, &1.name}, &1})
  end

  @doc """
  Whether the recorded pass found a candidate the gate holds against the run:
  a disagreement on a test case that was not muted.
  """
  def blocking_candidate?(%TestRunStressCandidate{outcome: "disagreed", is_quarantined: false}), do: true
  def blocking_candidate?(_), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
