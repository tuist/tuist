defmodule Tuist.Runners.Dispatch do
  @moduledoc """
  Dispatches a queued GitHub Actions job to an idle runner Pod
  from the shared pool.

  Driven by the `workflow_job: queued` webhook event. For each
  queued job:

  1. Resolve the pool config from `repository.owner` +
     `runs-on` labels via `Tuist.Runners.PoolConfig.match_for_dispatch/3`.
     Pools are org-scoped; repo-level scoping is the GitHub
     runner group's job, so we don't reimplement it here.
  2. Resolve the GitHub App installation for the org.
  3. Atomically claim an idle Pod with
     `Tuist.Runners.claim_idle_for_dispatch/0`.
  4. Mint a JIT config for the runner with the pool's labels.
  5. UPDATE the assignment row — the polling Pod's next
     `dispatch` request returns the JIT.

  Returns `{:ok, assignment}` on success or `{:error, reason}` for
  caller-visible failure modes (no pool match, no idle Pod, GH
  API failure). The webhook handler logs and returns 200 either
  way — GH retries on 5xx but a "no idle Pod" condition isn't a
  bug we want GH to retry; the next reconcile tick will close the
  gap and the same workflow_job will sit in GH's queue until a
  runner picks it up (GH's own queue retains queued jobs).
  """

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners
  alias Tuist.Runners.PoolConfig

  require Logger

  @doc """
  Handle a `workflow_job` webhook payload with `action: queued`.
  No-op for any other action (we drop `in_progress` / `completed`
  events on the floor; pod lifecycle is observed via the cluster,
  not GH).
  """
  def handle_webhook(%{"action" => "queued"} = payload, installation_id) when is_integer(installation_id) do
    job = Map.get(payload, "workflow_job", %{})
    repo = Map.get(payload, "repository", %{})
    full_name = Map.get(repo, "full_name", "")
    {owner, repo_name} = parse_full_name(full_name)
    requested = Map.get(job, "labels", [])

    with {:ok, pool} <- PoolConfig.match_for_dispatch(owner, requested, nil),
         {:ok, idle} <- Runners.claim_idle_for_dispatch(),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation_id, pool.owner, jit_attrs(pool, idle)),
         {:ok, dispatched} <-
           Runners.dispatch_assignment(idle, %{
             pool_name: pool.name,
             jit_config: jit,
             owner: pool.owner,
             # Repo of the job that consumed this runner. Recorded
             # for analytics / debugging only — pool selection
             # already happened by `owner`, and GitHub enforces the
             # runner group's allowlist independently.
             repo: repo_name,
             account_id: pool.account_id
           }) do
      Logger.info("runners: dispatched",
        pod_uid: dispatched.pod_uid,
        pool: pool.name,
        runner_name: runner_name,
        repo: full_name
      )

      {:ok, dispatched}
    else
      {:error, :no_match} ->
        # No pool matches this org + labels combo. Common case
        # for GH Apps installed across many orgs; not an error.
        :ignored

      {:error, :no_idle_pod} ->
        Logger.warning("runners: queued job with no idle Pod available",
          repo: full_name,
          requested_labels: requested
        )

        {:error, :no_idle_pod}

      {:error, reason} ->
        Logger.warning("runners: dispatch failed: #{inspect(reason)}",
          repo: full_name,
          requested_labels: requested
        )

        {:error, reason}
    end
  end

  def handle_webhook(_payload, _installation_id), do: :ignored

  defp parse_full_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"", ""}
    end
  end

  # GH's runner-name uniqueness is per repo. Embed the Pod's UID
  # short prefix so a re-dispatch (next reconcile cycle) doesn't
  # collide with a still-pending registration.
  defp jit_runner_name(pool, %{pod_uid: uid}) do
    short = uid |> String.replace("-", "") |> binary_part(0, 8)
    "tuist-#{pool.name}-#{short}"
  end

  defp jit_attrs(pool, idle) do
    base = %{name: jit_runner_name(pool, idle), labels: pool.labels}

    case Map.get(pool, :runner_group_id) do
      nil -> base
      id when is_integer(id) -> Map.put(base, :runner_group_id, id)
    end
  end
end
