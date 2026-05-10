defmodule Tuist.Runners.Dispatch do
  @moduledoc """
  Webhook handler for `workflow_job: queued` events from GitHub.

  The customer's pre-bound pool (sized by `min_warm`) handles
  the steady-state load — those Pods are already `online + idle`
  on GitHub, so GitHub's own dispatcher routes queued jobs to
  them autonomously and we never see a webhook for those slots.
  We only see `workflow_job: queued` events for jobs that GitHub
  *can't* dispatch immediately because every customer-labeled
  runner is busy. Those are the burst — and we serve them by
  writing a `RunnerAssignment` CR with `trigger: Burst`. The
  runners-controller picks it up and materializes a fresh Pod
  for the customer's pool.

  Lifecycle of a Burst Pod is identical to a pre-bound one
  (Pod boots → polls dispatch endpoint with its projected SA
  token → server mints a JIT → Pod registers with GitHub,
  runs one job, halts). The only difference is *when* the CR
  gets created: reactively here vs. proactively in the
  controller's RunnerPool reconciler.

  Trade-off: an on-demand burst pays ~30-90 s of clone+boot+
  register before the runner picks up the job. That's the
  default-tier cold-start every comparable CI provider walks; a
  generic shared pre-warm pool to absorb bursts without that tax
  is a Phase 2+ optimization.

  Returns `{:ok, :created}` on success, `:ignored` for events
  that don't target one of our pools, or `{:error, reason}`
  otherwise. The webhook handler returns 200 either way — GH
  retries on 5xx but our failure modes (pool-mismatch, controller
  unreachable) aren't ones GH retrying would help with; the
  controller's pre-bound refill closes the gap on its own.
  """

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.PoolConfig

  require Logger

  @doc """
  Handle a `workflow_job` webhook payload with `action: queued`.
  No-op for any other action (we drop `in_progress` / `completed`
  events on the floor; pod lifecycle is observed via the
  controller, not through GH events).
  """
  def handle_webhook(%{"action" => "queued"} = payload, installation_id) when is_integer(installation_id) do
    job = Map.get(payload, "workflow_job", %{})
    repo = Map.get(payload, "repository", %{})
    full_name = Map.get(repo, "full_name", "")
    {owner, _repo_name} = parse_full_name(full_name)
    requested = Map.get(job, "labels", [])

    case PoolConfig.match_for_dispatch(owner, requested, nil) do
      {:ok, pool} ->
        case Client.create_runner_assignment(namespace(), burst_manifest(pool)) do
          {:ok, %{"metadata" => %{"name" => name}}} ->
            Logger.info("runners: dispatched burst assignment",
              pool: pool.name,
              repo: full_name,
              assignment: name
            )

            {:ok, :created}

          {:error, reason} = err ->
            Logger.warning("runners: burst assignment create failed: #{inspect(reason)}",
              pool: pool.name,
              repo: full_name,
              requested_labels: requested
            )

            err
        end

      {:error, :no_match} ->
        # No pool matches this org + labels combo. Common case
        # for GH Apps installed across many orgs; not an error.
        :ignored
    end
  end

  def handle_webhook(_payload, _installation_id), do: :ignored

  defp burst_manifest(pool) do
    %{
      "apiVersion" => "tuist.dev/v1alpha1",
      "kind" => "RunnerAssignment",
      "metadata" => %{
        "generateName" => "#{pool.name}-burst-",
        "labels" => %{
          "tuist.dev/runner-pool" => pool.name,
          "tuist.dev/runner-pool-owner" => pool.owner
        }
      },
      "spec" => %{
        "poolRef" => %{"name" => pool.name},
        "trigger" => "Burst"
      }
    }
  end

  defp namespace, do: Environment.runners_namespace()

  defp parse_full_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"", ""}
    end
  end
end
