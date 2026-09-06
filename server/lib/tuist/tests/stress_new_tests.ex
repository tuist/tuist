defmodule Tuist.Tests.StressNewTests do
  @moduledoc """
  Server half of the stress gate for newly added tests.

  The client runs the suite, sends the test cases that executed, and gets back
  the subset that has not run in CI on the project's default branch in the
  trailing ninety days, each priced with the number of repetitions its own
  duration earns on the repetition curve. The guards whose inputs only the
  server holds (the default branch and its history, how many test cases the
  default branch already knows) are decided here and returned as a signal the client prints. The
  candidate cap is applied here too, so both clients only have to run what they
  are handed and stop at the wall-clock ceiling.

  The gate's verdict per candidate is recorded in `test_run_stress_candidates`.
  The reruns themselves are executions of the test case like any other, so they
  land in `test_case_run_repetitions` tagged `stress`, which is what lets the
  dashboard say which executions were solicited.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseBranchPresence
  alias Tuist.Tests.TestRunStressCandidate

  @modes ~w(report enforce)
  @run_outcomes ~w(passed disagreed skipped no_candidates)
  @skip_reasons ~w(first_pass_failed no_default_branch no_default_branch_history bulk_change plan_unavailable)
  @guard_kinds ~w(no_default_branch no_default_branch_history bulk_change)
  @excluded_reasons ~w(too_slow candidate_cap)

  @batch_size 2_000

  # Trailing window of default-branch CI history a test case is looked up in.
  @window_days 90

  # The curve is ordered ascending: the first bucket a duration fits wins, and a
  # test case slower than the last bucket is excluded.
  @parameters %{
    repetition_curve: [
      %{max_duration_ms: 5_000, repetitions: 10},
      %{max_duration_ms: 10_000, repetitions: 5},
      %{max_duration_ms: 30_000, repetitions: 3},
      %{max_duration_ms: 300_000, repetitions: 2}
    ],
    candidate_cap: 200,
    wall_clock_ceiling_ms: 600_000,
    bulk_change_ratio: 0.3,
    bulk_change_floor: 50
  }

  def modes, do: @modes
  def run_outcomes, do: @run_outcomes
  def skip_reasons, do: @skip_reasons
  def guard_kinds, do: @guard_kinds
  def excluded_reasons, do: @excluded_reasons

  def parameters, do: @parameters

  @doc """
  Decides which of `test_cases` (maps with `name`, `suite_name`, `module_name`
  and `duration` in milliseconds) the gate should stress for `project`.
  """
  def plan(project, test_cases) do
    parameters = parameters()

    project
    |> compute(dedupe(test_cases), parameters)
    |> Map.put(:parameters, parameters)
  end

  defp compute(project, test_cases, parameters) do
    default_branch = project.default_branch

    if blank?(default_branch) do
      guard("no_default_branch", length(test_cases), 0)
    else
      known_count = known_test_case_count(project.id, default_branch)

      if known_count == 0 do
        guard("no_default_branch_history", length(test_cases), 0)
      else
        new_test_cases = reject_known(project.id, default_branch, test_cases)
        new_count = length(new_test_cases)

        if new_count >= parameters.bulk_change_floor and
             new_count > parameters.bulk_change_ratio * known_count do
          guard("bulk_change", new_count, known_count)
        else
          %{guard: nil, candidates: price(new_test_cases, parameters), known_count: known_count}
        end
      end
    end
  end

  defp guard(kind, new_count, known_count) do
    %{
      guard: %{kind: kind, new_count: new_count, known_count: known_count},
      candidates: [],
      known_count: known_count
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

  # The window matches the one `Tuist.Tests.check_new_test_cases/3` reads, so the
  # gate and the new-test badge answer the same question. Selective testing keeps
  # an unchanged target off the default branch for as long as its inputs are
  # stable, so a module dormant for longer than the window reads as new and is
  # stressed again. The ids are bound as one `Array(UUID)` so a large suite stays
  # within ClickHouse's parameter limits.
  defp known_test_case_ids(project_id, default_branch, ids) do
    ClickHouseRepo.all(
      from(bp in TestCaseBranchPresence,
        where: bp.project_id == ^project_id,
        where: bp.git_branch == ^default_branch,
        where: bp.is_ci == true,
        where: bp.ran_at >= ^window_start(),
        where: fragment("? IN (?)", bp.test_case_id, type(^ids, {:array, Ecto.UUID})),
        distinct: true,
        select: bp.test_case_id
      ),
      multipart: true
    )
  end

  # Counted over the same window as the newness lookup above. A test case that
  # falls out of the window leaves both sides at once, which is what keeps the
  # bulk-change ratio comparing two halves of one population.
  defp known_test_case_count(project_id, default_branch) do
    ClickHouseRepo.one(
      from(bp in TestCaseBranchPresence,
        where: bp.project_id == ^project_id,
        where: bp.git_branch == ^default_branch,
        where: bp.is_ci == true,
        where: bp.ran_at >= ^window_start(),
        select: fragment("uniqExact(?)", bp.test_case_id)
      )
    ) || 0
  end

  defp window_start, do: NaiveDateTime.add(NaiveDateTime.utc_now(), -@window_days, :day)

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
      stress_known_count: Map.get(stress, :known_count) || 0
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
      stress_known_count: max(existing.stress_known_count, incoming.stress_known_count)
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

    :ok
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
