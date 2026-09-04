defmodule Tuist.Runners.Buildkite.ReportToken do
  @moduledoc """
  The credential a running Buildkite job uses to hand its log and its
  outcome back to Tuist.

  A Buildkite job reports from inside itself: the agent writes the job's
  log to a file and a `pre-exit` hook posts it. That hook needs to
  authenticate, and the obvious candidate — the Pod's ServiceAccount
  token — is the one credential it must not use. On the Linux fleet the
  job container deliberately holds no SA token: the poller init
  container claims the job and hands the credential over on a shared
  volume, precisely so untrusted workflow code never sits next to a
  token that can claim more work. Reporting with the SA token would
  undo that.

  So dispatch mints this instead. It is signed, stateless, and names
  exactly one job. Everything it authorizes, that job could already do:
  write its own log, and declare its own exit status. It cannot claim
  work, read another account, or report for another job — so staging it
  into the job container leaves the isolation boundary where it was.

  The same token is used on macOS, where the VM is single-tenant and the
  SA token was previously readable from the job. Both fleets now report
  with a credential scoped to the job rather than to the machine.
  """

  alias Tuist.Runners.Buildkite.Job

  @salt "runner_buildkite_report"

  # Long enough to outlive any job the fleet will run — billing already
  # clamps a session at six hours — and short enough that a token
  # recovered from a build artifact later is inert. It is bound to one
  # job either way; the bound is defence in depth, not the control.
  @max_age_seconds 12 * 60 * 60

  @doc """
  Mints the report credential for one job.
  """
  def mint(%{workflow_job_id: workflow_job_id, account_id: account_id}) do
    Phoenix.Token.sign(TuistWeb.Endpoint, @salt, %{
      workflow_job_id: workflow_job_id,
      account_id: account_id
    })
  end

  @doc """
  Verifies a report credential, returning the job it names.

  Returns `{:error, :expired}` for a token past `max_age`, and
  `{:error, :invalid}` for anything else — a forged signature, a token
  minted with a different salt, or a payload that no longer maps to a
  Buildkite job.
  """
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TuistWeb.Endpoint, @salt, token, max_age: @max_age_seconds) do
      {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}} ->
        # The signature proves we minted the token; this proves the job it
        # names is still a Buildkite job of that account. Without it a
        # token would keep working after its row was deleted, and the
        # ingest path would write rows keyed on a job nothing owns.
        case Tuist.Repo.get_by(Job, workflow_job_id: workflow_job_id, account_id: account_id) do
          nil -> {:error, :invalid}
          _job -> {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}}
        end

      {:error, :expired} ->
        {:error, :expired}

      {:error, _reason} ->
        {:error, :invalid}
    end
  end

  def verify(_token), do: {:error, :invalid}
end
