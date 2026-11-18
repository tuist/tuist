defmodule Tuist.Runners.APIJobsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.APIJobs
  alias Tuist.Runners.APIJobs.Job
  alias Tuist.Runners.JobReportToken
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Workers.ExpireAPIJobWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Webhooks
  alias Tuist.Webhooks.Workers.DeliveryWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.API.Spec, as: ApiSpec

  @sha "0123456789abcdef0123456789abcdef01234567"

  setup :verify_on_exit!

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
    stub(Allowance, :exhausted?, fn _ -> false end)
    {:ok, profile} = Profiles.create(account, %{name: "ci", platform: :linux, vcpus: 4, memory_gb: 16})
    %{account: account, profile: profile}
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        profile: "ci",
        repository_url: "https://git.example.com/acme/app.git",
        commit_sha: @sha,
        ref: "refs/heads/main",
        name: "test",
        script: "mise run test",
        env: %{"PLAIN" => "visible"},
        secrets: %{"API_TOKEN" => "secret-value"},
        clone_token: "clone-secret"
      },
      overrides
    )
  end

  defp delivered_events do
    Oban.Job
    |> where([j], j.worker == ^inspect(DeliveryWorker))
    |> Repo.all()
    |> Enum.map(& &1.args)
  end

  defp subscribe(account) do
    {:ok, _endpoint, _secret} =
      Webhooks.create_endpoint(account.id, %{
        "name" => "Forge",
        "url" => "https://forge.example.com/hook",
        "event_types" => ["runner_job.started", "runner_job.completed"]
      })
  end

  defp mark_running(job) do
    Repo.update_all(from(w in WorkflowJob, where: w.workflow_job_id == ^job.workflow_job_id),
      set: [status: "running", started_at: DateTime.utc_now()]
    )
  end

  describe "create_job/2" do
    test "queues the job on the profile's pool with an encrypted payload", %{account: account, profile: profile} do
      assert {:ok, job, :created} = APIJobs.create_job(account, attrs())

      assert job.workflow_job_id >= 4_000_000_000_000_000
      assert job.repository == "acme/app"

      row = Repo.get!(WorkflowJob, job.workflow_job_id)
      assert row.provider == "api"
      assert row.status == "queued"
      assert row.requested_dispatch_label == Profile.dispatch_label(profile)
      assert {row.platform, row.vcpus, row.memory_gb} == {"linux", 4, 16}
      assert {row.head_sha, row.head_branch, row.job_name} == {@sha, "main", "test"}

      %{rows: [[stored]]} =
        Repo.query!("SELECT payload FROM runner_api_jobs WHERE workflow_job_id = $1", [job.workflow_job_id])

      refute stored =~ "secret-value"
      refute stored =~ "clone-secret"
      refute inspect(job) =~ "secret-value"

      assert [%{args: %{"workflow_job_id" => id}}] =
               Repo.all(from(j in Oban.Job, where: j.worker == ^inspect(ExpireAPIJobWorker)))

      assert id == job.workflow_job_id
    end

    test "accepts the profile's runs-on label", %{account: account, profile: profile} do
      label = Profile.dispatch_label(profile)
      assert {:ok, job, :created} = APIJobs.create_job(account, attrs(%{profile: String.upcase(label)}))
      assert Repo.get!(WorkflowJob, job.workflow_job_id).requested_dispatch_label == label
    end

    test "returns the existing job for a reused idempotency key", %{account: account} do
      other = AccountsFixtures.organization_fixture(preload: [:account]).account
      {:ok, _} = Profiles.create(other, %{name: "ci", platform: :linux, vcpus: 4, memory_gb: 16})

      assert {:ok, first, :created} = APIJobs.create_job(account, attrs(%{idempotency_key: "app:abc:test"}))

      assert {:ok, again, :existing} =
               APIJobs.create_job(account, attrs(%{idempotency_key: "app:abc:test", script: "different"}))

      assert again.workflow_job_id == first.workflow_job_id
      assert Repo.aggregate(from(j in Job, where: j.account_id == ^account.id), :count) == 1

      # Keys are scoped to the account.
      assert {:ok, theirs, :created} = APIJobs.create_job(other, attrs(%{idempotency_key: "app:abc:test"}))
      refute theirs.workflow_job_id == first.workflow_job_id
    end

    test "rejects requests it cannot route or run", %{account: account} do
      assert {:error, :unknown_profile} = APIJobs.create_job(account, attrs(%{profile: "missing"}))
      assert {:error, {:invalid, "script"}} = APIJobs.create_job(account, attrs(%{script: ""}))
      assert {:error, {:invalid, "timeout_minutes"}} = APIJobs.create_job(account, attrs(%{timeout_minutes: 361}))
      assert {:error, {:invalid, "env"}} = APIJobs.create_job(account, attrs(%{env: %{"1BAD" => "x"}}))

      assert {:error, {:invalid, "secrets"}} =
               APIJobs.create_job(account, attrs(%{secrets: %{"TUIST_RUNNER_REPORT_TOKEN" => "x"}}))

      for url <- ["http://git.example.com/acme/app.git", "https://user:pass@git.example.com/acme/app.git"] do
        assert {:error, %Ecto.Changeset{} = changeset} = APIJobs.create_job(account, attrs(%{repository_url: url}))
        assert changeset.errors[:repository_url]
      end

      assert {:error, %Ecto.Changeset{} = changeset} = APIJobs.create_job(account, attrs(%{commit_sha: "abc1234"}))
      assert changeset.errors[:commit_sha]

      assert Repo.aggregate(WorkflowJob, :count) == 0
    end

    test "refuses new jobs once the allowance is exhausted", %{account: account} do
      stub(Allowance, :exhausted?, fn _ -> true end)
      assert {:error, :allowance_exhausted} = APIJobs.create_job(account, attrs())
    end
  end

  test "mint_acquisition/2 hands the claiming runner the job and a report token", %{account: account} do
    {:ok, job, :created} = APIJobs.create_job(account, attrs())

    assert {:ok, acquisition} = APIJobs.mint_acquisition(account.id, job.workflow_job_id)
    assert acquisition["script"] == "mise run test"
    assert acquisition["clone_token"] == "clone-secret"
    assert acquisition["secrets"] == %{"API_TOKEN" => "secret-value"}
    assert acquisition["timeout_seconds"] == 3600
    assert acquisition["commit_sha"] == @sha
    assert acquisition["repository_url"] == "https://git.example.com/acme/app.git"

    assert {:ok, %{workflow_job_id: id, account_id: account_id, provider: :api}} =
             JobReportToken.verify(acquisition["report_token"])

    assert {id, account_id} == {job.workflow_job_id, account.id}
    assert {:error, :not_found} = APIJobs.mint_acquisition(account.id + 1, job.workflow_job_id)
  end

  describe "cancel_job/2" do
    test "completes a queued job as cancelled, clears its payload and notifies", %{account: account} do
      subscribe(account)
      {:ok, job, :created} = APIJobs.create_job(account, attrs(%{idempotency_key: "k"}))

      assert {:ok, :cancelled} = APIJobs.cancel_job(account.id, job.workflow_job_id)

      row = Repo.get!(WorkflowJob, job.workflow_job_id)
      assert {row.status, row.conclusion} == {"cancelled", "cancelled"}
      assert is_nil(Repo.get!(Job, job.workflow_job_id).payload)
      assert {:error, :not_found} = APIJobs.mint_acquisition(account.id, job.workflow_job_id)

      assert [%{"event_type" => "runner_job.completed", "payload" => payload}] = delivered_events()
      assert payload["object"]["idempotency_key"] == "k"
      assert payload["object"]["conclusion"] == "cancelled"
      assert_matches_schema!(payload, "WebhookRunnerJobCompletedEvent")

      # A second cancellation is a no-op and does not notify again.
      assert {:ok, :completed} = APIJobs.cancel_job(account.id, job.workflow_job_id)
      assert length(delivered_events()) == 1
    end

    test "flags a running job for its executor", %{account: account} do
      {:ok, job, :created} = APIJobs.create_job(account, attrs())
      mark_running(job)
      refute APIJobs.cancel_requested?(job.workflow_job_id)

      assert {:ok, :cancel_requested} = APIJobs.cancel_job(account.id, job.workflow_job_id)

      assert APIJobs.cancel_requested?(job.workflow_job_id)
      assert Repo.get!(WorkflowJob, job.workflow_job_id).status == "running"
    end

    test "does not cancel another account's job", %{account: account} do
      other = AccountsFixtures.organization_fixture(preload: [:account]).account
      {:ok, job, :created} = APIJobs.create_job(account, attrs())

      assert {:error, :not_found} = APIJobs.cancel_job(other.id, job.workflow_job_id)
      assert Repo.get!(WorkflowJob, job.workflow_job_id).status == "queued"
    end
  end

  test "a reported finish completes the job, clears its payload and notifies", %{account: account} do
    subscribe(account)
    {:ok, job, :created} = APIJobs.create_job(account, attrs())
    mark_running(job)

    {:ok, _} =
      RunnerSessions.open(%{
        workflow_job_id: job.workflow_job_id,
        executed_workflow_job_id: job.workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        pod_name: "pod-api-1",
        runner_name: "runner-api-1",
        started_at: DateTime.utc_now()
      })

    assert :ok =
             APIJobs.record_job_finished("runner-api-1", account.id, %{
               workflow_job_id: job.workflow_job_id,
               conclusion: "failure"
             })

    row = Repo.get!(WorkflowJob, job.workflow_job_id)
    assert {row.status, row.conclusion} == {"completed", "failure"}
    assert is_nil(Repo.get!(Job, job.workflow_job_id).payload)
    assert [%{"event_type" => "runner_job.completed", "payload" => payload}] = delivered_events()
    assert payload["object"]["conclusion"] == "failure"
  end

  test "dispatch_started/1 sends runner_job.started", %{account: account} do
    subscribe(account)
    {:ok, job, :created} = APIJobs.create_job(account, attrs())
    mark_running(job)

    APIJobs.dispatch_started(job.workflow_job_id)

    assert [%{"event_type" => "runner_job.started", "payload" => payload}] = delivered_events()
    assert payload["object"]["status"] == "running"
    assert_matches_schema!(payload, "WebhookRunnerJobStartedEvent")
  end

  test "expire/1 cancels a job no runner picked up and leaves a running one", %{account: account} do
    {:ok, queued, :created} = APIJobs.create_job(account, attrs())
    {:ok, running, :created} = APIJobs.create_job(account, attrs())
    mark_running(running)

    assert :ok = APIJobs.expire(queued.workflow_job_id)
    assert :ok = APIJobs.expire(running.workflow_job_id)

    assert Repo.get!(WorkflowJob, queued.workflow_job_id).status == "cancelled"
    assert Repo.get!(WorkflowJob, running.workflow_job_id).status == "running"
    assert Repo.get!(Job, running.workflow_job_id).payload
  end

  test "orphan_status/2 fails a job whose Pod is gone and waits on a live one", %{account: account} do
    {:ok, job, :created} = APIJobs.create_job(account, attrs())

    assert {:ok, {"in_progress", ""}} = APIJobs.orphan_status(%{workflow_job_id: job.workflow_job_id}, :aged_out)
    assert Repo.get!(Job, job.workflow_job_id).payload

    assert {:ok, {"completed", "failure"}} =
             APIJobs.orphan_status(%{workflow_job_id: job.workflow_job_id}, :pod_stopped)

    assert is_nil(Repo.get!(Job, job.workflow_job_id).payload)
  end

  defp assert_matches_schema!(payload, schema_title) do
    spec = ApiSpec.spec()
    schema = Map.fetch!(spec.components.schemas, schema_title)

    case OpenApiSpex.cast_value(payload, schema, spec) do
      {:ok, _} ->
        :ok

      {:error, errors} ->
        flunk("#{schema_title}: #{inspect(Enum.map(List.wrap(errors), &OpenApiSpex.Cast.Error.message/1))}")
    end
  end
end
