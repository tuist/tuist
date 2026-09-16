defmodule Tuist.Runners.JobReportToken do
  @moduledoc "Job-scoped reporting credentials for GitLab, with compatibility for existing Buildkite agents."
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.GitLab.Job

  @salt "runner_gitlab_report"
  @max_age 12 * 60 * 60

  def mint(job, payload \\ nil)

  def mint(%Job{workflow_job_id: id, account_id: account_id}, payload) do
    claims = Map.merge(%{workflow_job_id: id, account_id: account_id}, cache_scope(payload))
    Phoenix.Token.sign(TuistWeb.Endpoint, @salt, claims)
  end

  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TuistWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, %{workflow_job_id: id, account_id: account_id} = identity} ->
        if Repo.exists?(from(j in Job, where: j.workflow_job_id == ^id and j.account_id == ^account_id)),
          do: {:ok, Map.put(identity, :provider, :gitlab)},
          else: {:error, :invalid}

      {:error, :expired} ->
        {:error, :expired}

      _ ->
        ReportToken.verify(token)
    end
  end

  def verify(_), do: {:error, :invalid}

  # The coordinator sets both fields in the job response; CI variables cannot
  # override them. A job without them gets no remote cache scope.
  defp cache_scope(%{"job_info" => %{"project_id" => project_id}, "git_info" => git_info})
       when is_integer(project_id) and is_map(git_info) do
    %{gitlab_project_id: project_id, ref_protected: Map.get(git_info, "protected") == true}
  end

  defp cache_scope(_payload), do: %{}
end
