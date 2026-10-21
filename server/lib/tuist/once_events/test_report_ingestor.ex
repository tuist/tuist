defmodule Tuist.OnceEvents.TestReportIngestor do
  @moduledoc """
  Publishes a finished Once test run into the shared test store.

  Bazel receives one complete report at the end of a run and writes it
  straight through (`Tuist.Bazel.TestReportIngestor`). Once instead streams
  `TestSuiteStarted` / `TestCaseCompleted` as the run progresses, and
  `RunCompleted` carries only per-result counts, so the case detail exists
  nowhere but the `once_test_*` rows the projector has been accumulating.

  Those rows are therefore ingestion state, not a second product store: this
  module reads them once the run finalizes, assembles the same nested report
  Bazel builds, and hands it to `Tuist.Tests.create_test/1` with
  `build_system: "once"`. Everything downstream of the shared store (flaky
  detection, quarantine, history, the API) then works for Once without a
  parallel implementation.
  """
  import Ecto.Query

  alias Tuist.Ingestion.Capture
  alias Tuist.IngestRepo
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.TestReportPublication
  alias Tuist.OnceEvents.Workers.PublishTestReportWorker
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests

  require Logger

  @doc """
  Publish `run`'s test results. A no-op for runs that carried no test cases,
  which is every `once build`.
  """
  @lease_seconds 360

  # The stream commits intent, not remote I/O. A crash before enqueue is covered
  # by the terminal-run sweep; afterwards the durable intent/job survives. The
  # worker prepares the immutable snapshot without holding up the event stream.
  def enqueue(%Run{} = run) do
    Repo.transaction(fn ->
      %{rows: [[locked]]} =
        Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", ["once-test-report:" <> run.id])

      if locked do
        publication = Repo.get(TestReportPublication, run.id)

        cond do
          publication != nil ->
            queue_publication(publication)

          Repo.get!(Run, run.id).test_report_published_at != nil ->
            :already_published

          true ->
            reserve_publication(run)
        end
      else
        :in_progress
      end
    end)
  end

  def enqueue_safely(%Run{} = run) do
    case enqueue(run) do
      {:error, _} = error ->
        publication_event(:preparation_failed)
        Logger.error("Once report snapshot preparation failed", once_run_id: run.id)
        error

      result ->
        result
    end
  rescue
    _error ->
      publication_event(:preparation_failed)
      Logger.error("Once report snapshot preparation raised", once_run_id: run.id)
      {:error, :preparation_failed}
  end

  def publish(%Run{} = run) do
    with {:ok, %TestReportPublication{} = publication} <- enqueue(run) do
      publish_prepared(publication.id)
    end
  end

  defp reserve_publication(run) do
    if Repo.exists?(from(c in OnceEvents.TestCaseRun, where: c.once_run_id == ^run.id)) do
      # This old column is an admission fence for legacy writers, NOT completion.
      # The durable intent and job commit in the SAME transaction as the fence.
      {reserved, _} =
        Repo.update_all(from(r in Run, where: r.id == ^run.id and is_nil(r.test_report_published_at)),
          set: [test_report_published_at: DateTime.utc_now()]
        )

      if reserved == 1,
        do: %TestReportPublication{id: run.id} |> Repo.insert!() |> queue_publication(),
        else: :already_published
    else
      :no_test_cases
    end
  end

  @doc false
  def prepare_snapshot(id) do
    Repo.transaction(fn ->
      %{rows: [[locked]]} =
        Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", ["once-test-report:" <> id])

      if locked do
        publication = Repo.get!(TestReportPublication, id)

        if publication.state == "preparing" do
          run = Repo.get!(Run, id)
          build_publication(publication, run, OnceEvents.list_test_case_runs(run))
        else
          publication
        end
      else
        :in_progress
      end
    end)
  end

  defp build_publication(publication, run, case_runs) do
    project = Projects.get_project_by_id(run.project_id) || Repo.rollback(:project_not_found)
    {{:ok, test}, rows, effects} = Capture.run(fn -> Tests.create_test(test_attributes(project, run, case_runs)) end)
    chunks = chunk_plan(rows)
    payload = :erlang.term_to_binary(%{version: 2, test: test, chunks: chunks, effects: effects}, compressed: 6)
    if byte_size(payload) > 64 * 1_024 * 1_024, do: Repo.rollback(:report_too_large)
    publication |> Ecto.Changeset.change(payload: payload, state: "pending") |> Repo.update!()
  end

  defp queue_publication(%TestReportPublication{state: "published"}), do: :already_published
  defp queue_publication(%TestReportPublication{state: "uncertain"}), do: :publication_uncertain

  defp queue_publication(publication) do
    %{run_id: publication.id, phase: "publish"} |> PublishTestReportWorker.new() |> Oban.insert!()
    publication
  end

  @doc false
  def publish_prepared(id) do
    with {:ok, %TestReportPublication{} = publication} <- prepare_snapshot(id) do
      publish_snapshot(publication)
    end
  end

  defp publish_snapshot(publication) do
    owner = Ecto.UUID.generate()
    {:ok, claim} = Repo.transaction(fn -> claim_publication(publication.id, owner) end)

    case claim do
      {:claimed, current} ->
        %{version: 2, test: test, chunks: chunks} = :erlang.binary_to_term(current.payload, [:safe])
        write_chunks(current.id, owner, test, chunks, current.next_chunk)

      result ->
        result
    end
  end

  defp claim_publication(id, owner) do
    current = Repo.one!(from(p in TestReportPublication, where: p.id == ^id, lock: "FOR UPDATE"))
    now = DateTime.truncate(DateTime.utc_now(), :second)
    expired = DateTime.diff(now, current.updated_at) >= @lease_seconds

    cond do
      current.state == "published" ->
        {:ok, :already_published}

      current.state == "uncertain" ->
        {:error, :publication_uncertain}

      current.state == "publishing" and not expired ->
        {:ok, :in_progress}

      current.in_flight_chunk != nil ->
        mark_uncertain(id, current.owner)
        {:error, :publication_uncertain}

      true ->
        updated =
          Repo.update!(
            Ecto.Changeset.change(current,
              state: "publishing",
              owner: owner,
              first_attempt_at: current.first_attempt_at || now
            )
          )

        {:claimed, updated}
    end
  end

  defp chunk_plan(rows) do
    rows
    |> Enum.sort_by(fn {schema, _} -> {schema == Tests.Test, schema} end)
    |> Enum.flat_map(fn {schema, values} ->
      values
      |> Enum.group_by(fn row ->
        case Map.get(row, :inserted_at) do
          %{year: year, month: month} -> {year, month}
          _ -> :unpartitioned
        end
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_, partition} ->
        partition
        |> Enum.chunk_every(1_000)
        |> Enum.map(fn chunk ->
          token = :sha256 |> :crypto.hash(:erlang.term_to_binary({schema, chunk})) |> Base.encode16(case: :lower)
          {schema, chunk, token}
        end)
      end)
    end)
  end

  defp write_chunks(id, owner, test, chunks, index) do
    case Enum.at(chunks, index) do
      nil ->
        complete_publication(id, owner, test, length(chunks))

      {schema, rows, token} ->
        query =
          from(p in TestReportPublication,
            where:
              p.id == ^id and p.owner == ^owner and p.state == "publishing" and p.next_chunk == ^index and
                is_nil(p.in_flight_chunk)
          )

        case Repo.update_all(query, set: [in_flight_chunk: index, updated_at: DateTime.utc_now()]) do
          {1, _} -> insert_and_checkpoint(id, owner, test, chunks, index, schema, rows, token)
          _ -> {:ok, :in_progress}
        end
    end
  end

  defp insert_and_checkpoint(id, owner, test, chunks, index, schema, rows, token) do
    query =
      from(p in TestReportPublication,
        where: p.id == ^id and p.owner == ^owner and p.state == "publishing" and p.in_flight_chunk == ^index
      )

    case insert_chunk(schema, rows, token) do
      :acknowledged ->
        case Repo.update_all(query, set: [next_chunk: index + 1, in_flight_chunk: nil, updated_at: DateTime.utc_now()]) do
          {1, _} -> write_chunks(id, owner, test, chunks, index + 1)
          _ -> {:ok, :in_progress}
        end

      :not_sent ->
        Repo.update_all(query, set: [state: "pending", in_flight_chunk: nil, updated_at: DateTime.utc_now()])
        {:error, :publication_checkout_timeout}

      :uncertain ->
        mark_uncertain(id, owner)
        {:error, :publication_uncertain}
    end
  end

  defp insert_chunk(schema, rows, token) do
    # Persisted tokens are defense in depth. Disable the repo's generic retries:
    # it otherwise resends transport timeouts before this writer can see them.
    case IngestRepo.insert_all(schema, rows,
           retry: false,
           checkout_retries: 0,
           timeout: 30_000,
           settings: [
             async_insert: 0,
             insert_deduplication_token: "once-report:" <> token,
             insert_deduplicate: 1,
             deduplicate_blocks_in_dependent_materialized_views: 1
           ]
         ) do
      {count, nil} when is_integer(count) and count >= 0 -> :acknowledged
      _ -> :uncertain
    end
  rescue
    error in DBConnection.ConnectionError ->
      if error.reason == :queue_timeout, do: :not_sent, else: :uncertain

    _error ->
      :uncertain
  end

  defp mark_uncertain(id, owner) do
    {changed, _} =
      Repo.update_all(
        from(p in TestReportPublication,
          where: p.id == ^id and p.owner == ^owner and p.state == "publishing" and not is_nil(p.in_flight_chunk)
        ),
        set: [state: "uncertain", updated_at: DateTime.utc_now()]
      )

    if changed == 1 do
      publication_event(:uncertain)

      Logger.error("Once test publication has an uncertain ClickHouse write; manual reconciliation required",
        once_run_id: id
      )
    end
  end

  defp complete_publication(id, owner, test, count) do
    Repo.transaction(fn ->
      now = DateTime.truncate(DateTime.utc_now(), :second)

      query =
        from(p in TestReportPublication,
          where:
            p.id == ^id and p.owner == ^owner and p.state == "publishing" and p.next_chunk == ^count and
              is_nil(p.in_flight_chunk)
        )

      case Repo.update_all(query, set: [state: "published", updated_at: now]) do
        {1, _} ->
          Repo.update_all(from(r in Run, where: r.id == ^id), set: [test_report_published_at: now])
          %{run_id: id, phase: "followups"} |> PublishTestReportWorker.new() |> Oban.insert!()
          test

        _ ->
          :in_progress
      end
    end)
  end

  @doc """
  Maintenance-only reconciliation after independently proving the old worker AND
  its ClickHouse query have stopped, and checking this exact chunk on all storage
  replicas. `:present` requires every row and its payload to match; `:absent`
  requires no rows. Partial/mismatched/unknown results MUST NOT call this function.
  It deliberately does not guess absence from a potentially lagging read.
  """
  def reconcile_chunk(id, owner, index, outcome) when outcome in [:present, :absent] do
    Repo.transaction(fn ->
      query =
        from(p in TestReportPublication,
          where:
            p.id == ^id and p.owner == ^owner and p.state == "uncertain" and p.in_flight_chunk == ^index and
              p.next_chunk == ^index
        )

      next = if outcome == :present, do: index + 1, else: index

      case Repo.update_all(query,
             set: [state: "pending", owner: nil, next_chunk: next, in_flight_chunk: nil, updated_at: DateTime.utc_now()]
           ) do
        {1, _} -> %{run_id: id, phase: "publish"} |> PublishTestReportWorker.new() |> Oban.insert!()
        _ -> Repo.rollback(:stale_reconciliation)
      end
    end)
  end

  def recover_recent(within_seconds \\ 7_200) do
    recover_publications(nil)
    cutoff = DateTime.add(DateTime.utc_now(), -within_seconds, :second)

    query =
      from(r in Run,
        where:
          r.finalization == "finalized" and r.finalized_at >= ^cutoff and
            is_nil(r.test_report_published_at) and r.test_case_count > 0,
        order_by: r.id,
        limit: 100
      )

    recover_page(query, nil)
  end

  # admin / cross-tenant: durable publication recovery is independent of run age.
  defp recover_publications(cursor) do
    cutoff = DateTime.add(DateTime.utc_now(), -@lease_seconds, :second)

    query =
      from(p in TestReportPublication,
        where: p.state in ["preparing", "pending"] or (p.state == "publishing" and p.updated_at < ^cutoff),
        order_by: p.id,
        limit: 100
      )

    page = Repo.all(if cursor, do: where(query, [p], p.id > ^cursor), else: query)
    Enum.each(page, &queue_publication/1)
    if page != [], do: recover_publications(List.last(page).id)
    :ok
  end

  defp recover_page(query, cursor) do
    page = Repo.all(if cursor, do: where(query, [r], r.id > ^cursor), else: query)
    Enum.each(page, &enqueue_safely/1)
    if page != [], do: recover_page(query, List.last(page).id)
    :ok
  end

  defp publication_event(outcome) do
    :telemetry.execute([:tuist, :once_events, :test_report_publication], %{publications: 1}, %{outcome: outcome})
  end

  defp test_attributes(project, %Run{} = run, case_runs) do
    test_modules = case_runs |> test_modules() |> mark_quarantined_cases(project, run)

    %{
      # Derived from the run rather than generated, so republishing the same
      # run targets the same shared row instead of creating a second one.
      id: test_run_id(run),
      project_id: project.id,
      account_id: project.account_id,
      duration: bounded_duration(run.wall_ms),
      status: test_status(run.exit_status, test_modules),
      scheme: String.slice(run.command_display || "", 0, 1_024),
      model_identifier: "",
      macos_version: "",
      xcode_version: "",
      git_branch: run.git_branch || "",
      git_ref: git_ref(run.git_branch),
      git_commit_sha: run.git_rev || "",
      ran_at: run.finalized_at || run.started_at,
      is_ci: run.is_ci || false,
      build_system: "once",
      once_run_id: run.run_id,
      test_modules: test_modules
    }
  end

  defp test_modules(case_runs) do
    case_runs
    |> Enum.group_by(& &1.target_execution_id)
    |> Enum.map(fn {target, target_cases} ->
      test_cases = aggregate_test_cases(target_cases)

      %{
        name: target,
        status: aggregate_status(test_cases),
        duration: Enum.sum(Enum.map(test_cases, & &1.duration)),
        test_suites: suites_from_cases(test_cases),
        test_cases: test_cases
      }
    end)
  end

  # One entry per case, carrying every attempt as a repetition. Once retries a
  # failing case in place and reports each attempt as its own event, so
  # collapsing them to the last one would throw away the only evidence of
  # flakiness: `Tuist.Tests` decides a case is flaky when its repetitions hold
  # both a success and a failure.
  defp aggregate_test_cases(case_runs) do
    case_runs
    |> Enum.group_by(&{&1.suite_id || &1.target_execution_id, &1.case_id || &1.name})
    |> Enum.map(fn {_identity, attempts} ->
      attempts = Enum.sort_by(attempts, &(&1.attempt || 1))
      last = List.last(attempts)

      %{
        name: last.name || last.case_id,
        test_suite_name: last.suite_id || last.target_execution_id,
        # The verdict is the final attempt's: a case that passed on retry
        # passed, and is recorded as flaky through its repetitions instead.
        status: shared_status(last.result),
        duration: Enum.sum(Enum.map(attempts, &(&1.duration_ms || 0))),
        repetitions: repetitions(attempts)
      }
    end)
  end

  defp repetitions(attempts) do
    attempts
    |> Enum.with_index(1)
    |> Enum.map(fn {attempt, number} ->
      %{
        name: "Attempt #{number}",
        repetition_number: number,
        status: shared_status(attempt.result),
        duration: attempt.duration_ms || 0
      }
    end)
  end

  # Without this a quarantined case keeps failing runs for Once, because the
  # shared store only knows a case is quarantined if the report says so. The
  # state is read as of the run's start so a case quarantined afterwards does
  # not retroactively change a finished run.
  defp mark_quarantined_cases(test_modules, project, %Run{} = run) do
    identities =
      for module <- test_modules, test_case <- module.test_cases do
        Tests.generate_test_case_id(project.id, test_case.name, module.name, test_case.test_suite_name)
      end

    states = Tests.get_test_case_states_at(project.id, identities, run.started_at || run.finalized_at)

    Enum.map(test_modules, fn module ->
      Map.update!(module, :test_cases, fn cases ->
        Enum.map(cases, fn test_case ->
          id = Tests.generate_test_case_id(project.id, test_case.name, module.name, test_case.test_suite_name)
          Map.put(test_case, :is_quarantined, states[id].state in Tests.active_quarantine_states())
        end)
      end)
    end)
  end

  defp suites_from_cases(test_cases) do
    test_cases
    |> Enum.group_by(& &1.test_suite_name)
    |> Enum.map(fn {name, cases} ->
      %{
        name: name,
        status: aggregate_status(cases),
        duration: Enum.sum(Enum.map(cases, & &1.duration))
      }
    end)
  end

  # The shared column is `Enum8('success', 'failure', 'skipped')`, so an
  # unmapped Once result is a write error rather than a silent coercion.
  # Once reports eight.
  #
  # `errored` and `timed_out` are verdicts against the test, so they fail.
  # `cancelled`, `unknown` and anything unspecified never reached a verdict:
  # counting those as failures would manufacture failure and flakiness signals
  # out of an interrupted run, so they are skipped instead. The original Once
  # result stays on the `once_test_case_runs` row either way.
  defp shared_status("passed"), do: "success"
  defp shared_status("failed"), do: "failure"
  defp shared_status("errored"), do: "failure"
  defp shared_status("timed_out"), do: "failure"
  defp shared_status(_no_verdict), do: "skipped"

  defp aggregate_status(items) do
    cond do
      Enum.any?(items, &(&1.status == "failure")) -> "failure"
      items != [] and Enum.all?(items, &(&1.status == "skipped")) -> "skipped"
      true -> "success"
    end
  end

  # A failed case makes the run a failure even when the client reported a
  # zero exit status. The shared store feeds flaky detection, so a report
  # claiming success while carrying a failed case would poison it.
  defp test_status(exit_status, test_modules) do
    cond do
      exit_status not in [0, nil] -> "failure"
      Enum.any?(test_modules, &(&1.status == "failure")) -> "failure"
      test_modules != [] and Enum.all?(test_modules, &(&1.status == "skipped")) -> "skipped"
      true -> "success"
    end
  end

  defp git_ref(branch) when is_binary(branch) and branch != "", do: "refs/heads/#{branch}"
  defp git_ref(_blank), do: ""

  defp bounded_duration(nil), do: 0
  defp bounded_duration(duration) when duration < 0, do: 0
  defp bounded_duration(duration), do: duration

  # A Once run id is client-minted and only unique within its project, so the
  # shared row's UUID is derived from both.
  defp test_run_id(%Run{} = run) do
    OnceEvents.uuid_from_seed("once-test-run\0#{run.project_id}\0#{run.run_id}")
  end
end
