defmodule Tuist.Runners.Buildkite.ReportTokenTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.Buildkite.ReportToken

  setup do
    %{account: account} = organization_fixture(preload: [:account])

    {:ok, job} =
      %Job{}
      |> Job.changeset(%{
        job_uuid: Ecto.UUID.generate(),
        account_id: account.id,
        organization_slug: "acme"
      })
      |> Repo.insert(returning: true)

    %{account: account, job: job}
  end

  test "round-trips the job it was minted for", %{account: account, job: job} do
    token = ReportToken.mint(%{workflow_job_id: job.workflow_job_id, account_id: account.id})

    assert {:ok, claims} = ReportToken.verify(token)
    assert claims.workflow_job_id == job.workflow_job_id
    assert claims.account_id == account.id
  end

  test "refuses a token that was not minted by us" do
    assert {:error, :invalid} = ReportToken.verify("clearly-not-a-token")
  end

  test "refuses a token minted for a different purpose", %{account: account, job: job} do
    # Same payload, different salt. Without the salt check, any signed
    # token in the system would double as a report credential.
    foreign =
      Phoenix.Token.sign(TuistWeb.Endpoint, "some_other_salt", %{
        workflow_job_id: job.workflow_job_id,
        account_id: account.id
      })

    assert {:error, :invalid} = ReportToken.verify(foreign)
  end

  test "refuses a token naming a job that does not exist", %{account: account} do
    token = ReportToken.mint(%{workflow_job_id: 1_000_000_000_000_999, account_id: account.id})

    assert {:error, :invalid} = ReportToken.verify(token)
  end

  test "refuses a token whose account does not own the job", %{job: job} do
    %{account: other_account} = organization_fixture(preload: [:account])

    token =
      ReportToken.mint(%{workflow_job_id: job.workflow_job_id, account_id: other_account.id})

    assert {:error, :invalid} = ReportToken.verify(token)
  end

  test "refuses a token for a job that has been deleted", %{account: account, job: job} do
    token = ReportToken.mint(%{workflow_job_id: job.workflow_job_id, account_id: account.id})
    Repo.delete!(job)

    assert {:error, :invalid} = ReportToken.verify(token)
  end

  test "refuses anything that is not a token" do
    assert {:error, :invalid} = ReportToken.verify(nil)
    assert {:error, :invalid} = ReportToken.verify(123)
  end
end
