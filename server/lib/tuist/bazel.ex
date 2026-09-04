defmodule Tuist.Bazel do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.InvocationLog
  alias Tuist.Bazel.TestInvocation
  alias Tuist.Bazel.TestReportIngestor
  alias Tuist.Bazel.TestResult
  alias Tuist.Bazel.TestSummary
  alias Tuist.Bazel.Workers.ProcessTestInvocationWorker
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache
  alias Tuist.Repo

  @authorization_pattern ~r/(?i)(\bauthorization\b\s*(?:=|:)\s*)(?:bearer\s+)?(?:"[^"]*"|'[^']*'|\S+)/
  @named_credential_pattern ~r/(?i)(\b(?:[A-Za-z0-9_-]+[_-]token|api[_-]?key|password|secret)\b\s*(?:=|:)\s*)(?:"[^"]*"|'[^']*'|\S+)/
  @token_assignment_pattern ~r/(?i)(\btoken\b\s*=\s*)(?:"[^"]*"|'[^']*'|\S+)/
  @credential_flag_pattern ~r/(?i)(--(?:token|api[_-]?key|password|secret)(?:=|\s+))(?:"[^"]*"|'[^']*'|\S+)/
  @bearer_pattern ~r/(?i)(\bbearer\s+)[A-Za-z0-9._~+\/=:-]+/
  @url_credentials_pattern ~r/([A-Za-z][A-Za-z0-9+.-]*:\/\/)[^\s\/:@]+:[^\s@\/]+@/
  @local_path_pattern ~r{(?:~/[^\s'"]*|/(?:Users|home|private|var/folders|tmp)(?:/[^\s'"]*)?)(?=$|[\s'"])}
  @ansi_escape_pattern ~r/\e\[[0-?]*[ -\/]*[@-~]/

  def ingest_test_report(project, invocation, test_results, test_summaries) do
    TestReportIngestor.ingest(project, invocation, test_results, test_summaries)
  end

  def sanitize_log_message(message) when is_binary(message) do
    message
    |> then(&Regex.replace(@ansi_escape_pattern, &1, ""))
    |> then(&Regex.replace(@url_credentials_pattern, &1, "\\1<REDACTED>@"))
    |> then(&Regex.replace(@authorization_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@named_credential_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@token_assignment_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@credential_flag_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@bearer_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@local_path_pattern, &1, "<LOCAL_PATH>"))
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  def sanitize_log_message(_), do: ""

  def create_invocations([]), do: {0, nil}

  def create_invocations(invocations) when is_list(invocations) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(invocations, fn invocation ->
        %{
          id: UUIDv7.generate(),
          invocation_id: invocation.invocation_id,
          command: invocation.command,
          target_patterns: Map.get(invocation, :target_patterns, []),
          git_branch: Map.get(invocation, :git_branch, ""),
          git_commit_sha: Map.get(invocation, :git_commit_sha, ""),
          is_ci: Map.get(invocation, :is_ci, false),
          status: invocation.status,
          exit_code: invocation.exit_code,
          started_at: invocation.started_at,
          finished_at: invocation.finished_at,
          duration_ms: invocation.duration_ms,
          project_id: invocation.project_id,
          account_handle: invocation.account_handle,
          project_handle: invocation.project_handle,
          cache_endpoint: invocation.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(Invocation, entries)
  end

  def create_invocation_logs([]), do: {0, nil}

  def create_invocation_logs(logs) when is_list(logs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(logs, fn log ->
        %{
          id: Map.get(log, :id) || UUIDv7.generate(),
          invocation_id: log.invocation_id,
          sequence_number: log.sequence_number,
          stream: log.stream,
          message: log.message,
          project_id: log.project_id,
          observed_at: log.observed_at,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(InvocationLog, entries)
  end

  def upsert_test_result(attrs) when is_map(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entry =
      attrs
      |> Map.take([
        :project_id,
        :invocation_id,
        :target_label,
        :run,
        :shard,
        :attempt,
        :status,
        :duration_ms,
        :started_at,
        :cached,
        :is_ci,
        :sequence_number,
        :junit_digest,
        :junit_content,
        :log_digest,
        :log_content
      ])
      |> Map.merge(%{id: UUIDv7.generate(), inserted_at: now, updated_at: now})

    Repo.insert_all(
      TestResult,
      [entry],
      on_conflict:
        {:replace,
         [
           :status,
           :duration_ms,
           :started_at,
           :cached,
           :is_ci,
           :sequence_number,
           :junit_digest,
           :junit_content,
           :log_digest,
           :log_content,
           :updated_at
         ]},
      conflict_target: [:project_id, :invocation_id, :target_label, :run, :shard, :attempt]
    )

    :ok
  end

  def upsert_test_summary(attrs) when is_map(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entry =
      attrs
      |> Map.take([
        :project_id,
        :invocation_id,
        :target_label,
        :status,
        :total_run_count,
        :total_num_cached,
        :duration_ms,
        :started_at,
        :finished_at
      ])
      |> Map.merge(%{id: UUIDv7.generate(), inserted_at: now, updated_at: now})

    Repo.insert_all(
      TestSummary,
      [entry],
      on_conflict:
        {:replace,
         [
           :status,
           :total_run_count,
           :total_num_cached,
           :duration_ms,
           :started_at,
           :finished_at,
           :updated_at
         ]},
      conflict_target: [:project_id, :invocation_id, :target_label]
    )

    :ok
  end

  def record_test_invocation_event(project_id, invocation_id) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    test_run_id = UUIDv7.generate()

    Repo.insert_all(
      TestInvocation,
      [
        %{
          id: UUIDv7.generate(),
          project_id: project_id,
          invocation_id: invocation_id,
          state: "collecting",
          test_run_id: test_run_id,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:project_id, :invocation_id]
    )

    :ok
  end

  def complete_test_invocation(project_id, invocation_id) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(
      TestInvocation,
      [
        %{
          id: UUIDv7.generate(),
          project_id: project_id,
          invocation_id: invocation_id,
          state: "pending",
          test_run_id: UUIDv7.generate(),
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:state, :updated_at]},
      conflict_target: [:project_id, :invocation_id]
    )

    %{"project_id" => project_id, "invocation_id" => invocation_id}
    |> ProcessTestInvocationWorker.new()
    |> Oban.insert()
  end

  def get_test_invocation(project_id, invocation_id) do
    Repo.one(
      from(test_invocation in TestInvocation,
        where: test_invocation.project_id == ^project_id and test_invocation.invocation_id == ^invocation_id
      )
    )
  end

  def list_test_results(project_id, invocation_id) do
    Repo.all(
      from(test_result in TestResult,
        where: test_result.project_id == ^project_id and test_result.invocation_id == ^invocation_id,
        order_by: [asc: test_result.sequence_number, asc: test_result.target_label]
      )
    )
  end

  def list_test_summaries(project_id, invocation_id) do
    Repo.all(
      from(test_summary in TestSummary,
        where: test_summary.project_id == ^project_id and test_summary.invocation_id == ^invocation_id,
        order_by: [asc: test_summary.target_label]
      )
    )
  end

  def mark_test_invocation_processed(test_invocation) do
    test_invocation
    |> Ecto.Changeset.change(%{state: "processed"})
    |> Repo.update()
  end

  def delete_test_results(project_id, invocation_id) do
    Repo.delete_all(
      from(test_result in TestResult,
        where: test_result.project_id == ^project_id and test_result.invocation_id == ^invocation_id
      )
    )
  end

  def delete_test_summaries(project_id, invocation_id) do
    Repo.delete_all(
      from(test_summary in TestSummary,
        where: test_summary.project_id == ^project_id and test_summary.invocation_id == ^invocation_id
      )
    )
  end

  def delete_expired_test_ingestion_records(before) do
    {results, _} = Repo.delete_all(from(result in TestResult, where: result.inserted_at < ^before))
    {summaries, _} = Repo.delete_all(from(summary in TestSummary, where: summary.inserted_at < ^before))
    {invocations, _} = Repo.delete_all(from(invocation in TestInvocation, where: invocation.inserted_at < ^before))
    results + summaries + invocations
  end

  def list_invocations(project_id, flop_params \\ %{}) do
    {invocations, meta} =
      from(invocation in Invocation, hints: ["FINAL"])
      |> where([invocation], invocation.project_id == ^project_id)
      |> ClickHouseFlop.validate_and_run!(flop_params, for: Invocation)

    with_cache_summaries(project_id, invocations, meta)
  end

  def get_invocation(project_id, invocation_id) do
    invocation =
      ClickHouseRepo.one(
        from(invocation in Invocation,
          hints: ["FINAL"],
          where: invocation.project_id == ^project_id and invocation.invocation_id == ^invocation_id,
          order_by: [desc: invocation.inserted_at],
          limit: 1
        )
      )

    case invocation do
      nil -> {:error, :not_found}
      invocation -> {:ok, Map.put(invocation, :cache, ReapiCache.invocation_summary(project_id, invocation_id))}
    end
  end

  def list_invocation_logs(project_id, invocation_id, flop_params \\ %{}) do
    ClickHouseFlop.validate_and_run!(
      from(log in InvocationLog,
        hints: ["FINAL"],
        where: log.project_id == ^project_id and log.invocation_id == ^invocation_id
      ),
      flop_params,
      for: InvocationLog
    )
  end

  def get_invocation_log(project_id, invocation_id, log_id) do
    with {:ok, log_id} <- Ecto.UUID.cast(log_id),
         %InvocationLog{} = log <-
           ClickHouseRepo.one(
             from(log in InvocationLog,
               hints: ["FINAL"],
               where:
                 log.project_id == ^project_id and log.invocation_id == ^invocation_id and
                   log.id == type(^log_id, Ecto.UUID),
               limit: 1
             )
           ) do
      {:ok, log}
    else
      _ -> {:error, :not_found}
    end
  end

  def summary(project_id) do
    result =
      ClickHouseRepo.one(
        from(invocation in Invocation,
          hints: ["FINAL"],
          where: invocation.project_id == ^project_id,
          select: %{
            total: count(invocation.id),
            successful: coalesce(sum(fragment("if(? = 'success', 1, 0)", invocation.status)), 0),
            median_duration_ms: fragment("quantileOrNull(0.5)(?)", invocation.duration_ms),
            p90_duration_ms: fragment("quantileOrNull(0.9)(?)", invocation.duration_ms)
          }
        )
      )

    result || %{total: 0, successful: 0, median_duration_ms: 0, p90_duration_ms: 0}
  end

  defp with_cache_summaries(_project_id, [], meta), do: {[], meta}

  defp with_cache_summaries(project_id, invocations, meta) do
    invocation_ids = Enum.map(invocations, & &1.invocation_id)
    summaries = ReapiCache.invocation_summaries(project_id, invocation_ids)

    invocations =
      Enum.map(invocations, fn invocation ->
        Map.put(invocation, :cache, Map.get(summaries, invocation.invocation_id, ReapiCache.empty_summary()))
      end)

    {invocations, meta}
  end
end
