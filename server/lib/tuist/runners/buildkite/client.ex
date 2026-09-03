defmodule Tuist.Runners.Buildkite.Client do
  @moduledoc """
  Buildkite Agent Stacks API client.

  Most of Buildkite's Agent API is reserved for the agent itself and
  carries no compatibility guarantee. The `/v3/stacks` family is the
  exception: it is documented for third parties building stack
  controllers on self-hosted queues, which is exactly what the runner
  fleet is. Nothing here may reach for an endpoint outside that family.

  The four calls that make up a dispatch:

    * `list_scheduled_jobs/4` — what is waiting on a queue.
    * `reserve/4` — take jobs off that list for a bounded window, so a
      second stack polling the same cluster cannot also schedule them.
    * `issue_acquisition_tokens/4` — mint the short-lived per-job
      credential a VM uses to register and take exactly one job. This is
      the Buildkite analogue of GitHub's JIT config, and a stricter one:
      GitHub binds a JIT config to a label set and picks the job itself,
      while a `bkjat_` token is bound to a single job UUID.
    * `finish_job/5` — fail a job we reserved but could not run, instead
      of leaving it to time out.

  Rate limits are per stack over a one-second sliding window: 10 rps for
  listing and reserving, 1000 rps for reading a single job. The poller
  paces itself against the listing limit, which is the binding one.
  """

  alias Tuist.Runners.Buildkite.Installation

  @base_url "https://agent.buildkite.com/v3"
  @request_timeout to_timeout(second: 15)

  @doc """
  Scheduled jobs on `queue_key`, oldest first.

  Returns `{:ok, %{jobs: [...], dispatch_paused: boolean}}`. A paused
  queue still lists its jobs; the flag is Buildkite telling us to leave
  them alone, and the caller must honour it.
  """
  def list_scheduled_jobs(%Installation{} = installation, queue_key, limit \\ 100) do
    installation
    |> request(:get, "/stacks/#{installation.stack_key}/scheduled-jobs", params: [queue_key: queue_key, limit: limit])
    |> case do
      {:ok, %{"jobs" => jobs} = body} ->
        {:ok,
         %{
           jobs: Enum.map(jobs, &normalize_job(&1, queue_key)),
           dispatch_paused: get_in(body, ["cluster_queue", "dispatch_paused"]) == true
         }}

      {:ok, _body} ->
        {:ok, %{jobs: [], dispatch_paused: false}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Reserves `job_uuids` for `expiry_seconds`, returning the subset
  Buildkite granted us.

  A UUID that comes back in `not_reserved` was taken by another stack, or
  cancelled between the list and the reserve. That is an ordinary race,
  not an error.
  """
  def reserve(%Installation{} = installation, job_uuids, expiry_seconds) when is_list(job_uuids) do
    installation
    |> request(:put, "/stacks/#{installation.stack_key}/scheduled-jobs/batch-reserve",
      json: %{job_uuids: job_uuids, reservation_expiry_seconds: expiry_seconds}
    )
    |> case do
      {:ok, %{"reserved" => reserved}} -> {:ok, reserved}
      {:ok, _body} -> {:ok, []}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Mints a single-job acquisition token. The job must already be reserved
  by this stack.

  Returns `{:ok, %{token: token, expires_at: expires_at}}`, or
  `{:error, :not_issued}` when Buildkite declines — the reservation
  lapsed, or the job is no longer schedulable.
  """
  def issue_acquisition_token(%Installation{} = installation, job_uuid, lifetime_seconds) do
    installation
    |> request(:post, "/stacks/#{installation.stack_key}/job-acquisition-tokens",
      json: %{job_uuids: [job_uuid], token_lifetime_seconds: lifetime_seconds}
    )
    |> case do
      {:ok, %{"job_acquisition_tokens" => [%{"job_acquisition_token" => token} = issued | _]}} ->
        {:ok, %{token: token, expires_at: Map.get(issued, "expires_at")}}

      {:ok, _body} ->
        {:error, :not_issued}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  The full job payload, including the environment Buildkite will hand the
  agent. The listing carries metadata only, and the fork check needs
  `BUILDKITE_PULL_REQUEST_REPO`, which lives here.
  """
  def get_job(%Installation{} = installation, job_uuid) do
    request(installation, :get, "/stacks/#{installation.stack_key}/jobs/#{job_uuid}")
  end

  @doc """
  Marks a reserved job finished without ever running it.

  The GitHub lane has no equivalent lever: a job we fail to provision
  sits queued until GitHub times it out, which reads to the customer as
  a capacity shortage. Here we can say so.
  """
  def finish_job(%Installation{} = installation, job_uuid, exit_status, detail) do
    request(installation, :post, "/stacks/#{installation.stack_key}/jobs/#{job_uuid}/finish",
      json: %{exit_status: exit_status, detail: detail}
    )
  end

  defp normalize_job(job, queue_key) do
    %{
      job_uuid: Map.get(job, "id"),
      priority: Map.get(job, "priority", 0),
      agent_query_rules: Map.get(job, "agent_query_rules", []),
      scheduled_at: parse_datetime(Map.get(job, "scheduled_at")),
      pipeline_slug: get_in(job, ["pipeline", "slug"]) || "",
      build_uuid: get_in(job, ["build", "uuid"]) || "",
      build_number: get_in(job, ["build", "number"]) || 0,
      build_branch: get_in(job, ["build", "branch"]) || "",
      step_key: get_in(job, ["step", "key"]) || "",
      queue_key: queue_key
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp request(%Installation{agent_token: token}, method, path, opts \\ []) do
    options =
      [
        method: method,
        url: @base_url <> path,
        headers: [
          {"authorization", "Token #{token}"},
          {"content-type", "application/json"},
          {"user-agent", "tuist-runners"}
        ],
        receive_timeout: @request_timeout,
        finch: Tuist.Finch
      ] ++ opts

    case Req.request(options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429, headers: headers}} ->
        {:error, {:rate_limited, retry_after(headers)}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, truncate(body)}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  defp retry_after(headers) do
    case headers |> Map.new() |> Map.get("ratelimit-reset") do
      [value | _] -> String.to_integer(value)
      value when is_binary(value) -> String.to_integer(value)
      _ -> 1
    end
  rescue
    _ -> 1
  end

  defp truncate(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp truncate(body), do: body |> inspect() |> String.slice(0, 500)
end
