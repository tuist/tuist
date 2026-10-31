defmodule Tuist.Runners.ExecutionTokens do
  @moduledoc """
  Binds a runner session to the GitHub job it runs from a GitHub Actions OIDC
  token the job minted for itself, instead of waiting for the
  `workflow_job.in_progress` webhook or `ExecutionLookupWorker`.

  The runner's job-started hook requests the token when the workflow grants
  `id-token: write`, and the node agent forwards it with the pod it came from.
  GitHub signs the token for one job, whose id is its `check_run_id`, so it is
  the one job-supplied input that may bind a session: whoever presents it
  already runs code in that job. The token's job must be one the account's
  `queued` webhook reported, in the same repository, and no other open session
  may already be bound to it.

  Binding goes through `Dispatch.record_execution/3`, as the webhook does, for
  accounts with `FeatureFlags.runner_oidc_execution_enabled?/1`, and the
  session keeps the token's claims (`execution_identity`), from which cache
  volume allocation takes the job's identity. For the others
  the job the token names is only logged, next to the binding the session has
  so far, so the two sources can be compared before the token binds anything.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.FeatureFlags
  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob

  require Logger

  @audience "tuist-runner-cache"

  def audience, do: @audience

  def prove(%{"pod_name" => pod, "node_name" => node, "token" => token})
      when is_binary(pod) and pod != "" and is_binary(node) and node != "" and is_binary(token) do
    with %RunnerSession{runner_name: runner_name} = session when runner_name != "" <- open_session(pod, node),
         {:ok, claims} <- OIDC.github_actions_claims(token, @audience),
         {:ok, workflow_job_id} <- check_run_id(claims),
         %WorkflowJob{} = job <-
           Repo.get_by(WorkflowJob, workflow_job_id: workflow_job_id, account_id: session.account_id, provider: "github"),
         true <- same_repository?(job.repository, claims["repository"]),
         false <- bound_elsewhere?(session, workflow_job_id) do
      record(session, workflow_job_id, claims)
    else
      {:error, reason} ->
        Logger.info("runners: execution token rejected", pod: pod, reason: inspect(reason))
        {:error, :unverified}

      _ ->
        {:error, :unverified}
    end
  end

  def prove(_params), do: {:error, :unverified}

  defp record(%RunnerSession{} = session, workflow_job_id, claims) do
    if session.executed_workflow_job_id not in [nil, workflow_job_id] do
      Logger.warning("runners: execution token disagrees with the recorded execution",
        runner_name: session.runner_name,
        workflow_job_id: workflow_job_id,
        recorded_workflow_job_id: session.executed_workflow_job_id
      )
    end

    if FeatureFlags.runner_oidc_execution_enabled?(%Account{id: session.account_id}) do
      outcome = Dispatch.record_execution(session.runner_name, workflow_job_id, session.account_id)

      Repo.update_all(from(s in RunnerSession, where: s.id == ^session.id),
        set: [execution_identity: execution_identity(workflow_job_id, claims)]
      )

      Logger.info("runners: recorded execution from execution token (#{inspect(outcome)})",
        runner_name: session.runner_name,
        workflow_job_id: workflow_job_id
      )
    else
      Logger.info("runners: execution token names a job (not binding)",
        runner_name: session.runner_name,
        workflow_job_id: workflow_job_id,
        recorded_workflow_job_id: session.executed_workflow_job_id
      )
    end

    :ok
  end

  # The claims cache volume identity reads (`CacheVolumes.Identity.resolve/1`),
  # tied to the job the token named.
  defp execution_identity(workflow_job_id, claims) do
    claims
    |> Map.take(~w(repository_id repository ref ref_type event_name head_ref base_ref run_id run_attempt))
    |> Map.put("workflow_job_id", workflow_job_id)
  end

  defp open_session(pod, node) do
    Repo.one(
      from(s in RunnerSession,
        where: s.pod_name == ^pod and s.node_name == ^node and is_nil(s.ended_at) and s.platform in [:linux, :macos],
        order_by: [desc: s.started_at],
        limit: 1
      )
    )
  end

  # GitHub's claims are strings; the job id is the job's check run id.
  defp check_run_id(%{"check_run_id" => id}) when is_integer(id) and id > 0, do: {:ok, id}

  defp check_run_id(%{"check_run_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_check_run_id}
    end
  end

  defp check_run_id(_claims), do: {:error, :missing_check_run_id}

  defp same_repository?(repository, claimed) when is_binary(repository) and is_binary(claimed),
    do: repository != "" and String.downcase(repository) == String.downcase(claimed)

  defp same_repository?(_repository, _claimed), do: false

  defp bound_elsewhere?(%RunnerSession{id: id, account_id: account_id}, workflow_job_id) do
    Repo.exists?(
      from(s in RunnerSession,
        where:
          s.account_id == ^account_id and s.executed_workflow_job_id == ^workflow_job_id and s.id != ^id and
            is_nil(s.ended_at)
      )
    )
  end
end
