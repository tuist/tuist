defmodule Tuist.Runners.Buildkite.CacheVolumeIdentityTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Repo
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.Client
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    account = AccountsFixtures.account_fixture()

    installation =
      Repo.insert!(%Buildkite.Installation{
        account_id: account.id,
        organization_slug: "org",
        stack_key: "volume-#{account.id}",
        agent_token: "bkct_test"
      })

    job =
      Repo.insert!(%Buildkite.Job{
        account_id: account.id,
        job_uuid: Ecto.UUID.generate(),
        workflow_job_id: System.unique_integer([:positive]),
        build_uuid: Ecto.UUID.generate(),
        build_number: 42,
        organization_slug: "org",
        pipeline_slug: "pipeline",
        queue_key: "queue"
      })

    stub(Client, :issue_acquisition_token, fn _, _, _, _ -> {:ok, %{token: "bkjat_test"}} end)
    %{account: account, installation: installation, job: job}
  end

  test "captures only normalized identity before handing the job to its agent", %{account: account, job: job} do
    env = %{
      "BUILDKITE_JOB_ID" => job.job_uuid,
      "BUILDKITE_BUILD_ID" => job.build_uuid,
      "BUILDKITE_BUILD_NUMBER" => "42",
      "BUILDKITE_ORGANIZATION_SLUG" => "org",
      "BUILDKITE_ORGANIZATION_ID" => Ecto.UUID.generate(),
      "BUILDKITE_PIPELINE_ID" => Ecto.UUID.generate(),
      "BUILDKITE_PIPELINE_SLUG" => "pipeline",
      "BUILDKITE_REPO" => "https://github.com/org/repo",
      "BUILDKITE_BRANCH" => "main",
      "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
      "BUILDKITE_PULL_REQUEST" => "false",
      "BUILDKITE_SOURCE" => "schedule",
      "SECRET" => "never store this"
    }

    expect(Client, :get_job, fn _, _, _ -> {:ok, %{"id" => job.job_uuid, "env" => env, "command" => "private script"}} end)

    assert {:ok, _} = Buildkite.mint_acquisition(account.id, job.workflow_job_id)
    identity = Repo.reload!(job).cache_volume_identity
    assert identity["trusted"]
    assert identity["provider_instance"] == env["BUILDKITE_ORGANIZATION_ID"]
    assert Enum.sort(Map.keys(identity)) == ~w(provider provider_instance repository_id scope_id trusted)
    refute JSON.encode!(identity) =~ "never store this"
  end

  test "a failed identity refresh clears earlier authority without preventing the job", %{account: account, job: job} do
    job |> Ecto.Changeset.change(cache_volume_identity: %{"trusted" => true}) |> Repo.update!()
    expect(Client, :get_job, fn _, _, _ -> {:error, :not_found} end)
    assert {:ok, _} = Buildkite.mint_acquisition(account.id, job.workflow_job_id)
    assert Repo.reload!(job).cache_volume_identity == nil
  end

  test "another account cannot mint a job credential", %{account: account, job: job} do
    assert {:error, :not_found} = Buildkite.mint_acquisition(account.id + 1, job.workflow_job_id)
    assert Repo.reload!(job).cache_volume_identity == nil
  end
end
