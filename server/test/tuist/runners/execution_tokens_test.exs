defmodule Tuist.Runners.ExecutionTokensTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.FeatureFlags
  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.ExecutionTokens
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()
    minted = job(account, "org/repo")
    executed = job(account, "org/repo")

    session =
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: minted.workflow_job_id,
        fleet_name: "linux",
        pod_name: "runner-pod",
        node_name: "runner-node",
        runner_name: "runner-1",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: DateTime.utc_now()
      })

    params = %{"pod_name" => "runner-pod", "node_name" => "runner-node", "token" => "jwt"}
    %{account: account, executed: executed, session: session, params: params}
  end

  defp job(account, repository) do
    Repo.insert!(%WorkflowJob{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      provider: "github",
      status: "queued",
      fleet_name: "linux",
      repository: repository,
      enqueued_at: DateTime.utc_now()
    })
  end

  defp claims(job, overrides \\ %{}) do
    Map.merge(%{"check_run_id" => to_string(job.workflow_job_id), "repository" => job.repository}, overrides)
  end

  test "binds the pod's session to the job the token names and keeps its claims", %{
    executed: executed,
    session: session,
    params: params
  } do
    claims = claims(executed, %{"event_name" => "push", "ref" => "refs/heads/main", "sub" => "repo:org/repo"})
    expect(OIDC, :github_actions_claims, fn "jwt", "tuist-runner-cache" -> {:ok, claims} end)
    stub(FeatureFlags, :runner_oidc_execution_enabled?, fn _ -> true end)
    workflow_job_id = executed.workflow_job_id
    expect(Dispatch, :record_execution, fn "runner-1", ^workflow_job_id, _ -> {:ok, :mismatch} end)

    assert :ok = ExecutionTokens.prove(params)

    assert %{
             "workflow_job_id" => ^workflow_job_id,
             "repository" => "org/repo",
             "event_name" => "push",
             "ref" => "refs/heads/main"
           } = identity = Repo.get!(RunnerSession, session.id).execution_identity

    refute Map.has_key?(identity, "sub")
  end

  test "only logs the job without the flag", %{executed: executed, session: session, params: params} do
    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(executed)} end)
    stub(FeatureFlags, :runner_oidc_execution_enabled?, fn _ -> false end)
    reject(&Dispatch.record_execution/3)

    assert :ok = ExecutionTokens.prove(params)
    assert Repo.get!(RunnerSession, session.id).execution_identity == nil
  end

  test "rejects a token for a job the account was never told about", %{params: params} do
    expect(OIDC, :github_actions_claims, fn _, _ ->
      {:ok, %{"check_run_id" => "424242", "repository" => "org/repo"}}
    end)

    reject(&Dispatch.record_execution/3)

    assert {:error, :unverified} = ExecutionTokens.prove(params)
  end

  test "rejects a token whose repository is not the job's", %{executed: executed, params: params} do
    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(executed, %{"repository" => "org/other"})} end)
    reject(&Dispatch.record_execution/3)

    assert {:error, :unverified} = ExecutionTokens.prove(params)
  end

  test "rejects a job of another account", %{params: params} do
    other = job(AccountsFixtures.account_fixture(), "org/repo")
    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(other)} end)
    reject(&Dispatch.record_execution/3)

    assert {:error, :unverified} = ExecutionTokens.prove(params)
  end

  test "rejects a job another open session is already bound to", %{
    executed: executed,
    session: session,
    params: params
  } do
    Repo.insert!(%{
      session
      | id: nil,
        pod_name: "other-pod",
        runner_name: "runner-2",
        executed_workflow_job_id: executed.workflow_job_id
    })

    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(executed)} end)
    reject(&Dispatch.record_execution/3)

    assert {:error, :unverified} = ExecutionTokens.prove(params)
  end

  test "never overrides the job GitHub reported for the session", %{executed: executed, session: session, params: params} do
    reported = job(%{id: session.account_id}, "org/repo")
    Repo.update_all(RunnerSession, set: [executed_workflow_job_id: reported.workflow_job_id])
    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(executed)} end)
    stub(FeatureFlags, :runner_oidc_execution_enabled?, fn _ -> true end)
    reject(&Dispatch.record_execution/3)

    assert {:error, :unverified} = ExecutionTokens.prove(params)

    assert %{executed_workflow_job_id: reported_id, execution_identity: nil} = Repo.get!(RunnerSession, session.id)
    assert reported_id == reported.workflow_job_id
  end

  test "rejects a job an ended session was bound to, or one already completed", %{
    executed: executed,
    session: session,
    params: params
  } do
    stub(FeatureFlags, :runner_oidc_execution_enabled?, fn _ -> true end)
    reject(&Dispatch.record_execution/3)

    ended =
      Repo.insert!(%{
        session
        | id: nil,
          pod_name: "other-pod",
          runner_name: "runner-2",
          executed_workflow_job_id: executed.workflow_job_id,
          ended_at: DateTime.utc_now()
      })

    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(executed)} end)
    assert {:error, :unverified} = ExecutionTokens.prove(params)

    Repo.delete!(ended)
    Repo.update_all(WorkflowJob, set: [status: "completed"])
    expect(OIDC, :github_actions_claims, fn _, _ -> {:ok, claims(executed)} end)
    assert {:error, :unverified} = ExecutionTokens.prove(params)
  end

  test "rejects a token that does not verify", %{params: params} do
    expect(OIDC, :github_actions_claims, fn _, _ -> {:error, :invalid_audience} end)
    reject(&Dispatch.record_execution/3)

    assert {:error, :unverified} = ExecutionTokens.prove(params)
  end

  test "rejects a pod without an open session", %{params: params} do
    reject(&OIDC.github_actions_claims/2)

    assert {:error, :unverified} = ExecutionTokens.prove(%{params | "pod_name" => "unknown-pod"})
    assert {:error, :unverified} = ExecutionTokens.prove(%{"pod_name" => "runner-pod"})
  end
end
