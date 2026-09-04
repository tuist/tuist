defmodule Tuist.Bazel do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.InvocationLog
  alias Tuist.Bazel.TestArtifactReceipt
  alias Tuist.Bazel.TestReportIngestor
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache
  alias Tuist.Repo

  @credential_pattern ~r/(?i)\b(authorization|token|api[_-]?key|password|secret)\b\s*(?:=|:)\s*(?:bearer\s+)?[^\s'"]+/
  @url_credentials_pattern ~r/([A-Za-z][A-Za-z0-9+.-]*:\/\/)[^\s\/:@]+:[^\s@\/]+@/
  @local_path_pattern ~r{(?:~|/(?:Users|home|private|var/folders|tmp))(?:/[^\s'"]*)?}
  @ansi_escape_pattern ~r/\e\[[0-?]*[ -\/]*[@-~]/

  def ingest_test_report(project, invocation, test_result, report) do
    TestReportIngestor.ingest(project, invocation, test_result, report)
  end

  def sanitize_log_message(message) when is_binary(message) do
    message
    |> then(&Regex.replace(@ansi_escape_pattern, &1, ""))
    |> then(&Regex.replace(@url_credentials_pattern, &1, "\\1<REDACTED>@"))
    |> then(&Regex.replace(@credential_pattern, &1, "\\1=<REDACTED>"))
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

  def create_invocation_logs([]), do: {:ok, 0}

  def create_invocation_logs(logs) when is_list(logs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(logs, fn log ->
        %{
          id: UUIDv7.generate(),
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

  def claim_test_artifact_receipt(attrs) when is_map(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _rows} =
      Repo.insert_all(
        TestArtifactReceipt,
        [
          %{
            id: UUIDv7.generate(),
            project_id: attrs.project_id,
            invocation_id: attrs.invocation_id,
            target_label: attrs.target_label,
            action_digest: attrs.action_digest,
            artifact_kind: attrs.artifact_kind,
            artifact_digest: attrs.artifact_digest,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [
          :project_id,
          :invocation_id,
          :target_label,
          :action_digest,
          :artifact_kind,
          :artifact_digest
        ]
      )

    if count == 1, do: :claimed, else: :already_claimed
  end

  def delete_test_artifact_receipt(attrs) when is_map(attrs) do
    Repo.delete_all(
      from(receipt in TestArtifactReceipt,
        where:
          receipt.project_id == ^attrs.project_id and receipt.invocation_id == ^attrs.invocation_id and
            receipt.target_label == ^attrs.target_label and receipt.action_digest == ^attrs.action_digest and
            receipt.artifact_kind == ^attrs.artifact_kind and receipt.artifact_digest == ^attrs.artifact_digest
      )
    )

    :ok
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
