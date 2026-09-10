defmodule Tuist.Runners.GitLabTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.GitLab.Client
  alias Tuist.Runners.GitLab.Job
  alias Tuist.Runners.JobReportToken
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
    stub(FeatureFlags, :runners_enabled?, fn _ -> true end)
    stub(Allowance, :exhausted?, fn _ -> false end)

    stub(Dispatch, :resolve_dispatch_target, fn _, [label] ->
      {:ok, %{pool_name: "pool-macos", requested_dispatch_label: label, platform: :macos, vcpus: 4, memory_gb: 16}}
    end)

    {:ok, connection} =
      GitLab.save_connection(account.id, %{
        url: "https://gitlab.com",
        runner_token: "glrt-secret"
      })

    reject(&Req.request/1)
    stub(Client, :update_job, fn _, _, _, _ -> {:ok, %{}} end)
    %{account: account, connection: connection}
  end

  defp payload do
    %{
      "id" => System.unique_integer([:positive]),
      "token" => "job-secret",
      "job_info" => %{"name" => "test", "project_id" => 123},
      "git_info" => %{
        "repo_url" => "https://gitlab-ci-token:job-secret@gitlab.com/acme/mobile.git",
        "sha" => "abc",
        "ref" => "main"
      },
      "variables" => [
        %{"key" => "CI_PIPELINE_ID", "value" => "42"},
        %{"key" => "CI_JOB_TAGS", "value" => ~s(["tuist-macos"])},
        %{"key" => "SECRET", "value" => "private-value", "masked" => true}
      ]
    }
  end

  test "encrypts reusable tokens and preserves them on blank rotation", %{account: account, connection: connection} do
    assert {:ok, updated} = GitLab.save_connection(account.id, %{url: "https://gitlab.com/", runner_token: ""})
    assert updated.runner_token == "glrt-secret"
    assert updated.id == connection.id
    %{rows: [[stored]]} = Repo.query!("SELECT runner_token FROM runner_gitlab_connections WHERE id = $1", [connection.id])
    refute stored =~ "glrt-secret"
    refute inspect(updated) =~ "glrt-secret"
  end

  test "maps and encrypts exactly the acquired job in one transaction", %{connection: connection, account: account} do
    payload = payload()
    expect(Client, :request_job, fn ^connection -> {:ok, payload} end)
    assert {:ok, 1} = GitLab.poll(connection)
    job = Repo.one!(Job)
    assert job.workflow_job_id >= 2_000_000_000_000_000
    assert job.job_id == payload["id"]
    assert job.account_id == account.id
    assert job.project_path == "acme/mobile"
    assert JSON.decode!(job.payload) == payload
    assert Repo.get!(WorkflowJob, job.workflow_job_id).provider == "gitlab"

    %{rows: [[encrypted]]} =
      Repo.query!("SELECT payload FROM runner_gitlab_jobs WHERE workflow_job_id = $1", [job.workflow_job_id])

    refute encrypted =~ "job-secret"
    refute inspect(job) =~ "private-value"
    assert {:ok, acquisition} = GitLab.mint_acquisition(account.id, job.workflow_job_id)
    refute inspect(acquisition) =~ "glrt-secret"
    assert {:ok, %{workflow_job_id: id}} = JobReportToken.verify(acquisition.report_token)
    assert id == job.workflow_job_id
    assert {:error, :not_found} = GitLab.mint_acquisition(account.id + 1, id)
  end

  test "does not acquire jobs when access or allowance is disabled", %{connection: connection} do
    reject(&Client.request_job/1)
    stub(FeatureFlags, :runners_enabled?, fn _ -> false end)
    assert {:ok, 0} = GitLab.poll(connection)
    stub(FeatureFlags, :runners_enabled?, fn _ -> true end)
    stub(Allowance, :exhausted?, fn _ -> true end)
    assert {:ok, 0} = GitLab.poll(connection)
  end

  test "one connection routes each job using its own tags", %{connection: connection, account: account} do
    for platform <- [:linux, :macos] do
      label = "tuist-#{platform}"

      payload =
        put_in(payload(), ["variables"], [
          %{"key" => "CI_JOB_TAGS", "value" => JSON.encode!(["ci", label])},
          %{"key" => "CI_RUNNER_TAGS", "value" => ~s(["tuist-linux","tuist-macos"])}
        ])

      expect(Client, :request_job, fn ^connection -> {:ok, payload} end)

      expect(Dispatch, :resolve_dispatch_target, fn %{id: id}, [^label] ->
        assert id == account.id

        {:ok,
         %{pool_name: "pool-#{platform}", requested_dispatch_label: label, platform: platform, vcpus: 4, memory_gb: 16}}
      end)

      assert {:ok, 1} = GitLab.poll(connection)
      job = Repo.get_by!(Job, job_id: payload["id"])
      workflow = Repo.get!(WorkflowJob, job.workflow_job_id)
      assert workflow.platform == Atom.to_string(platform)
      assert workflow.requested_dispatch_label == label
    end
  end

  test "rejects missing, malformed, ambiguous and unknown job tags without dispatch", %{connection: connection} do
    reject(&Dispatch.resolve_dispatch_target/2)

    for tags <- [
          nil,
          "not-json",
          "{}",
          ~s([1]),
          "[]",
          ~s(["ci"]),
          ~s(["tuist-linux","tuist-macos"]),
          ~s(["tuist-does-not-exist"])
        ] do
      payload =
        put_in(payload(), ["variables"], [
          %{"key" => "CI_JOB_TAGS", "value" => tags},
          %{"key" => "CI_RUNNER_TAGS", "value" => ~s(["tuist-macos"])}
        ])

      expect(Client, :request_job, fn _ -> {:ok, payload} end)

      expect(Client, :reject_job, fn "https://gitlab.com", ^payload, message ->
        assert message =~ "tags: [tuist-macos]"
        {:ok, nil}
      end)

      assert {:error, :invalid_job_tags} = GitLab.poll(connection)
      job = Repo.get_by!(Job, job_id: payload["id"])
      assert is_nil(job.payload)
      assert is_nil(Repo.get(WorkflowJob, job.workflow_job_id))
    end
  end

  test "rejects a profile belonging to another account", %{connection: connection} do
    %{account: other} = AccountsFixtures.organization_fixture(preload: [:account])

    Repo.insert!(%Tuist.Runners.Profile{
      account_id: other.id,
      name: "other-only",
      platform: :linux,
      vcpus: 4,
      memory_gb: 16
    })

    payload = put_in(payload(), ["variables"], [%{"key" => "CI_JOB_TAGS", "value" => ~s(["tuist-other-only"])}])
    expect(Client, :request_job, fn _ -> {:ok, payload} end)
    expect(Client, :reject_job, fn _, ^payload, _ -> {:ok, nil} end)
    reject(&Dispatch.resolve_dispatch_target/2)
    assert {:error, :invalid_job_tags} = GitLab.poll(connection)
  end

  test "retains rejected assignments until GitLab acknowledges their failure", %{connection: connection, account: account} do
    payload = put_in(payload(), ["variables"], [])
    expect(Client, :request_job, fn _ -> {:ok, payload} end)
    expect(Client, :reject_job, fn _, ^payload, _ -> {:error, :transport} end)
    assert {:error, :invalid_job_tags} = GitLab.poll(connection)
    job = Repo.one!(Job)
    assert job.payload

    expect(Client, :reject_job, fn _, ^payload, _ -> {:error, :transport} end)
    assert :ok = GitLab.delete_connection(account.id, connection.id)
    refute GitLab.get_connection(connection.id).enabled

    expect(Client, :reject_job, fn _, ^payload, _ -> {:ok, nil} end)
    reject(&Client.request_job/1)
    assert {:ok, 0} = GitLab.poll(connection)
    assert is_nil(GitLab.get_job(job.workflow_job_id).payload)
    assert is_nil(GitLab.get_connection(connection.id))
  end

  test "connection updates are account scoped", %{connection: connection, account: account} do
    assert {:error, :not_found} = GitLab.save_connection(account.id + 1, %{id: connection.id, runner_token: "glrt-other"})
    assert GitLab.get_connection(connection.id).runner_token == "glrt-secret"
  end

  test "fails an acquired job if the lifecycle transaction fails", %{connection: connection} do
    payload = payload()
    expect(Client, :request_job, fn _ -> {:ok, payload} end)
    expect(WorkflowJobs, :enqueue_many_if_missing, fn _ -> raise "database unavailable" end)
    expect(Client, :update_job, fn _, ^payload, "failed", "runner_system_failure" -> {:ok, %{}} end)
    assert {:error, :persistence_failed} = GitLab.poll(connection)
    assert Repo.aggregate(Job, :count) == 0
  end

  test "caps waiting assignments and keeps them alive", %{connection: connection} do
    stub(Client, :request_job, fn _ -> {:ok, payload()} end)
    for _ <- 1..5, do: assert({:ok, 1} = GitLab.poll(connection))
    reject(&Client.request_job/1)
    assert {:ok, 0} = GitLab.poll(connection)
  end

  test "expires an assignment that cannot get a machine", %{connection: connection} do
    expect(Client, :request_job, fn _ -> {:ok, payload()} end)
    assert {:ok, 1} = GitLab.poll(connection)
    job = Repo.one!(Job)
    Repo.update_all(Job, set: [inserted_at: DateTime.utc_now() |> DateTime.add(-700) |> DateTime.truncate(:second)])
    expect(Client, :update_job, fn _, _, "failed", "runner_system_failure" -> {:ok, %{}} end)
    expect(Client, :request_job, fn _ -> {:ok, nil} end)
    assert {:ok, 0} = GitLab.poll(connection)
    assert Repo.get!(WorkflowJob, job.workflow_job_id).status == "completed"
    assert is_nil(GitLab.get_job(job.workflow_job_id).payload)
  end

  test "fails a lost machine through GitLab without requeueing its assignment", %{connection: connection} do
    expect(Client, :request_job, fn _ -> {:ok, payload()} end)
    assert {:ok, 1} = GitLab.poll(connection)
    job = Repo.one!(Job)
    expect(Client, :update_job, fn _, _, "failed", "runner_system_failure" -> {:ok, %{}} end)
    assert {:ok, {"completed", "failure"}} = GitLab.orphan_status(job, :pod_stopped)
    assert is_nil(GitLab.get_job(job.workflow_job_id).payload)
  end

  test "disconnect is account scoped and fails waiting jobs", %{account: account, connection: connection} do
    expect(Client, :request_job, fn _ -> {:ok, payload()} end)
    assert {:ok, 1} = GitLab.poll(connection)
    job = Repo.one!(Job)
    assert :ok = GitLab.delete_connection(account.id + 1, connection.id)
    assert GitLab.get_connection(connection.id)
    expect(Client, :update_job, fn _, _, "failed", "runner_system_failure" -> {:ok, %{}} end)
    assert :ok = GitLab.delete_connection(account.id, connection.id)
    assert is_nil(GitLab.get_connection(connection.id))
    assert is_nil(GitLab.get_job(job.workflow_job_id).payload)
  end

  test "report tokens cannot outlive their job mapping", %{connection: connection} do
    expect(Client, :request_job, fn _ -> {:ok, payload()} end)
    assert {:ok, 1} = GitLab.poll(connection)
    job = Repo.one!(Job)
    token = JobReportToken.mint(job)
    assert {:ok, _} = JobReportToken.verify(token)
    assert {:error, :invalid} = JobReportToken.verify(token <> "x")
    Repo.delete!(job)
    assert {:error, :invalid} = JobReportToken.verify(token)
  end

  test "disconnection during a long poll cannot enqueue the returned assignment", %{
    account: account,
    connection: connection
  } do
    payload = payload()

    expect(Client, :request_job, fn _ ->
      :ok = GitLab.delete_connection(account.id, connection.id)
      {:ok, payload}
    end)

    expect(Client, :update_job, fn _, ^payload, "failed", "runner_system_failure" -> {:ok, %{}} end)
    assert {:error, :persistence_failed} = GitLab.poll(connection)
    assert Repo.aggregate(Job, :count) == 0
  end

  test "disconnect retains a disabled connection while GitLab is unavailable", %{account: account, connection: connection} do
    expect(Client, :request_job, fn _ -> {:ok, payload()} end)
    assert {:ok, 1} = GitLab.poll(connection)
    expect(Client, :update_job, fn _, _, "failed", "runner_system_failure" -> {:error, :transport} end)
    assert :ok = GitLab.delete_connection(account.id, connection.id)
    refute GitLab.get_connection(connection.id).enabled
    reject(&Client.request_job/1)
    expect(Client, :update_job, fn _, _, "failed", "runner_system_failure" -> {:ok, %{}} end)
    assert {:ok, 0} = GitLab.poll(connection)
    assert is_nil(GitLab.get_connection(connection.id))
  end

  test "expired payloads are erased independently of connection lifetime", %{connection: connection} do
    expect(Client, :request_job, fn _ -> {:ok, payload()} end)
    assert {:ok, 1} = GitLab.poll(connection)
    job = Repo.one!(Job)

    Repo.update_all(Job,
      set: [inserted_at: DateTime.utc_now() |> DateTime.add(-13 * 60 * 60) |> DateTime.truncate(:second)]
    )

    assert :ok = GitLab.purge_expired_payloads()
    assert is_nil(GitLab.get_job(job.workflow_job_id).payload)
    assert GitLab.get_job(job.workflow_job_id).project_path == "acme/mobile"
  end
end
