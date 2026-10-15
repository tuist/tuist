defmodule Tuist.Origin.RunnerCheckout do
  @moduledoc "Job-bound, read-only Origin checkout credentials for Tuist's Buildkite fleet."

  alias Tuist.Origin
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Repo
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.WorkflowJob

  @salt "origin_runner_checkout"
  @max_age 12 * 60 * 60

  def grant(job, %{"id" => id, "env" => env}) when is_map(env) do
    remote = env["BUILDKITE_REPO"]

    if id == job.job_uuid and env["BUILDKITE_JOB_ID"] == id and
         env["BUILDKITE_ORGANIZATION_SLUG"] == job.organization_slug and origin_remote?(remote) do
      with %Installation{suspended: false} = installation <- Origin.installation_for_account(job.account_id),
           {:ok, repositories} <- Client.repositories(installation),
           %{"id" => repository_id} <- Enum.find(repositories, &matches_repository?(&1, remote)) do
        {:ok,
         Phoenix.Token.sign(TuistWeb.Endpoint, @salt, %{
           workflow_job_id: job.workflow_job_id,
           account_id: job.account_id,
           installation_id: installation.id,
           repository_id: repository_id,
           remote: remote
         })}
      else
        {:error, _} = error -> error
        _ -> {:error, :origin_repository_not_accessible}
      end
    else
      {:ok, nil}
    end
  end

  def grant(_, _), do: {:ok, nil}

  def credentials(token, remote) do
    with {:ok, %{remote: ^remote} = claims} <- Phoenix.Token.verify(TuistWeb.Endpoint, @salt, token, max_age: @max_age),
         %Job{} <- Repo.get_by(Job, workflow_job_id: claims.workflow_job_id, account_id: claims.account_id),
         %WorkflowJob{provider: "buildkite", status: status} when status in ["claimed", "running"] <-
           Repo.get_by(WorkflowJob, workflow_job_id: claims.workflow_job_id, account_id: claims.account_id),
         %Installation{suspended: false} = installation <-
           Repo.get_by(Installation, id: claims.installation_id, account_id: claims.account_id),
         {:ok, repositories} <- Client.repositories(installation),
         true <- Enum.any?(repositories, &(&1["id"] == claims.repository_id and is_nil(&1["mirror"]))),
         {:ok, access_token} <-
           Client.get_installation_token(installation.installation_id, %{
             scopes: ["repository:contents:read"],
             repositoryIds: [claims.repository_id]
           }) do
      {:ok, access_token}
    else
      {:error, {:http, status}} when status >= 500 -> {:error, :unavailable}
      {:error, :transport} -> {:error, :unavailable}
      _ -> {:error, :forbidden}
    end
  end

  defp origin_remote?(remote) when is_binary(remote) do
    match?(%URI{scheme: "https", host: "origin.cursor.com", port: 443, path: "/" <> _, userinfo: nil}, URI.parse(remote))
  end

  defp origin_remote?(_), do: false

  defp matches_repository?(%{"fullName" => handle} = repository, remote) do
    is_nil(repository["mirror"]) and
      String.trim_trailing(URI.parse(remote).path, ".git") in ["/git/" <> handle, "/" <> handle]
  end
end
