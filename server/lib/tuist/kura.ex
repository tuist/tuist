defmodule Tuist.Kura do
  @moduledoc """
  Per-account Kura mesh management.

  Three responsibilities:

    * **Versions** — `record_version/2` and `latest_versions/1` cache
      published Kura tags discovered by
      `Tuist.Kura.Workers.PollVersionsWorker`.
    * **Deployments** — `create_deployment/1` inserts a deployment row
      and enqueues `Tuist.Kura.Workers.RolloutWorker` to execute it.
      The worker updates status as it progresses.
    * **Logs** — `append_log_lines/2` writes per-line stdout/stderr to
      ClickHouse. `list_log_lines/2` reads them back for the live tail
      in the /ops UI.

  Endpoint binding (which clusters serve which accounts) is owned by
  `Tuist.Accounts.create_account_cache_endpoint/2` with
  `technology: :kura`. This context only handles the rollout side.
  """

  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.Kura.Clusters
  alias Tuist.Kura.DeploymentLogLine
  alias Tuist.Kura.KuraDeployment
  alias Tuist.Kura.KuraVersion
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo

  ## Versions

  @doc "Inserts a version row if not already present. Idempotent."
  def record_version(version, %DateTime{} = released_at) when is_binary(version) do
    %{version: version, released_at: released_at}
    |> KuraVersion.changeset()
    |> Repo.insert(on_conflict: :nothing, conflict_target: :version)
  end

  @doc "Returns the most recently released versions, newest first."
  def latest_versions(limit \\ 20) when is_integer(limit) do
    KuraVersion
    |> order_by([v], desc: v.released_at)
    |> limit(^limit)
    |> Repo.all()
  end

  ## Deployments

  @doc """
  Inserts a `KuraDeployment` and enqueues the rollout worker.

  Validates that the cluster exists in `Tuist.Kura.Clusters.all/0` and
  that the image tag looks like a semver. Returns `{:ok, deployment}`
  with the Oban job ID stamped onto the row, or `{:error, changeset}`.
  """
  def create_deployment(attrs) do
    Repo.transaction(fn ->
      with {:ok, deployment} <- attrs |> KuraDeployment.create_changeset() |> Repo.insert(),
           {:ok, job} <- enqueue_rollout(deployment),
           {:ok, deployment} <- stamp_job_id(deployment, job.id) do
        deployment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp enqueue_rollout(%KuraDeployment{id: id}) do
    %{deployment_id: id}
    |> RolloutWorker.new()
    |> Oban.insert()
  end

  defp stamp_job_id(deployment, job_id) do
    deployment
    |> KuraDeployment.status_changeset(%{oban_job_id: job_id, status: :pending})
    |> Repo.update()
  end

  @doc "Returns deployments for the account, newest first."
  def list_deployments_for_account(account_id, limit \\ 50) do
    KuraDeployment
    |> where([d], d.account_id == ^account_id)
    |> order_by([d], desc: d.inserted_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Fetches a deployment, scoped to the given account so URLs cannot enumerate."
  def get_deployment(account_id, deployment_id) do
    Repo.get_by(KuraDeployment, id: deployment_id, account_id: account_id)
  end

  @doc "Marks a deployment as running and records the start time."
  def mark_running(%KuraDeployment{} = deployment) do
    deployment
    |> KuraDeployment.status_changeset(%{
      status: :running,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Marks a deployment as succeeded with the finish time."
  def mark_succeeded(%KuraDeployment{} = deployment) do
    # Clearing error_message guards against a race where another worker
    # raced ahead and stamped a transient error onto the row before this
    # worker's success update lands.
    deployment
    |> KuraDeployment.status_changeset(%{
      status: :succeeded,
      error_message: nil,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Marks a deployment as failed and records the error message."
  def mark_failed(%KuraDeployment{} = deployment, message) when is_binary(message) do
    deployment
    |> KuraDeployment.status_changeset(%{
      status: :failed,
      error_message: message,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  ## Logs (ClickHouse)

  @doc """
  Appends a batch of log lines for a deployment.

  Each entry is `{sequence, stream, line}` where `stream` is `:stdout`
  or `:stderr`. The worker assigns sequence numbers as it reads from the
  Port so ordering is stable across ClickHouse parts.
  """
  def append_log_lines(_deployment_id, []), do: {:ok, 0}

  def append_log_lines(deployment_id, lines) when is_list(lines) do
    rows =
      Enum.map(lines, fn {seq, stream, line} ->
        [
          deployment_id: deployment_id,
          sequence: seq,
          stream: stream_to_string(stream),
          line: line
        ]
      end)

    {count, _} = IngestRepo.insert_all(DeploymentLogLine, rows)
    {:ok, count}
  end

  @doc "Returns log lines for a deployment, oldest first, capped at `limit`."
  def list_log_lines(deployment_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1_000)
    after_sequence = Keyword.get(opts, :after_sequence, -1)

    query = """
    SELECT sequence, stream, line, inserted_at
    FROM kura_deployment_log_lines
    WHERE deployment_id = {deployment_id:UUID}
      AND sequence > {after_sequence:UInt64}
    ORDER BY sequence ASC
    LIMIT {limit:UInt32}
    """

    case IngestRepo.query(query, %{
           "deployment_id" => deployment_id,
           "after_sequence" => max(after_sequence, -1),
           "limit" => limit
         }) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [seq, stream, line, inserted_at] ->
          %{
            sequence: seq,
            stream: string_to_stream(stream),
            line: line,
            inserted_at: inserted_at
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  defp stream_to_string(:stdout), do: "stdout"
  defp stream_to_string(:stderr), do: "stderr"

  defp string_to_stream("stdout"), do: :stdout
  defp string_to_stream("stderr"), do: :stderr
  defp string_to_stream(other), do: other

  ## Cluster catalog (re-exported for convenience)

  defdelegate clusters, to: Clusters, as: :all
  defdelegate cluster(id), to: Clusters, as: :get
  defdelegate public_url(handle, cluster), to: Clusters
  defdelegate release_name(handle, cluster), to: Clusters
end
