defmodule Tuist.Runners.Bitrise.ReportToken do
  @moduledoc """
  The credential a runner VM's build start hook uses to tell Tuist which
  Bitrise build its agent took.

  It names the build the runner claimed, which is not necessarily the one
  the agent runs: Bitrise hands any build of the pool to any of its agents.
  It authorizes only that report, scoped to the claiming account, so a build
  that reads it can at most misattribute a build of its own account.
  """

  alias Tuist.Repo
  alias Tuist.Runners.Bitrise.Build

  @salt "runner_bitrise_report"
  @max_age_seconds 12 * 60 * 60

  def mint(%{workflow_job_id: workflow_job_id, account_id: account_id}) do
    Phoenix.Token.sign(TuistWeb.Endpoint, @salt, %{workflow_job_id: workflow_job_id, account_id: account_id})
  end

  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TuistWeb.Endpoint, @salt, token, max_age: @max_age_seconds) do
      {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}} ->
        case Repo.get_by(Build, workflow_job_id: workflow_job_id, account_id: account_id) do
          nil -> {:error, :invalid}
          _build -> {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}}
        end

      {:error, :expired} ->
        {:error, :expired}

      {:error, _reason} ->
        {:error, :invalid}
    end
  end

  def verify(_token), do: {:error, :invalid}
end
