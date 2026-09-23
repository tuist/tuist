defmodule Tuist.Runners.CacheVolumes.Identity do
  @moduledoc "Verified CI identity for a running pod's cache-volume allocation."

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.Client, as: BuildkiteClient
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.GitLab.Cache, as: GitLabCache
  alias Tuist.Runners.GitLab.Client, as: GitLabClient
  alias Tuist.VCS

  def resolve(%{provider: "github"} = job) do
    with {:ok, installation} <- VCS.get_github_app_installation_for_account(job.account_id),
         {:ok, run} <-
           GitHubClient.get_workflow_run(%{
             repository_full_handle: job.repository,
             installation: installation,
             run_id: job.workflow_run_id
           }),
         {:ok, repository} <- GitHubClient.get_repository(installation, job.repository),
         true <- repository["id"] == get_in(run, ["repository", "id"]) do
      github_identity(job, Map.put(run, "repository", repository))
    else
      _ -> {:error, :unavailable}
    end
  end

  def resolve(%{provider: "buildkite", account_id: account_id} = job) do
    with %Buildkite.Job{account_id: ^account_id} = assigned <- Buildkite.get_job(job.workflow_job_id),
         %Buildkite.Installation{enabled: true} = installation <- Buildkite.get_installation(account_id),
         {:ok, payload} <-
           BuildkiteClient.get_job(
             installation,
             Buildkite.stack_key_for(installation, assigned.queue_key),
             assigned.job_uuid
           ) do
      buildkite_identity(assigned, payload)
    else
      _ -> {:error, :unavailable}
    end
  end

  def resolve(%{provider: "gitlab", account_id: account_id} = job) do
    with %GitLab.Job{account_id: ^account_id, payload: encoded} = assigned <- GitLab.get_job(job.workflow_job_id),
         {:ok, payload} <- decode_assignment(encoded),
         {:ok, remote} <- GitLabClient.get_running_job(assigned.url, payload["token"]),
         {:ok, identity} <- gitlab_identity(assigned, payload, remote),
         {:ok, branches} <-
           GitLabClient.cache_branches(assigned.url, payload["token"], identity.repository_id, remote["ref"]) do
      trusted = gitlab_writer?(remote, branches)
      {:ok, Map.put(identity, :trusted, trusted)}
    else
      _ -> {:error, :unavailable}
    end
  end

  def resolve(_), do: {:error, :unavailable}

  def storage_scope(identity) do
    Map.merge(
      %{provider: "github", provider_instance: "github.com", scope_id: to_string(identity.repository_id)},
      identity
    )
  end

  defp decode_assignment(encoded) when is_binary(encoded) do
    case JSON.decode(encoded) do
      {:ok, %{"token" => token} = payload} when is_binary(token) and token != "" -> {:ok, payload}
      _ -> {:error, :unavailable}
    end
  end

  defp decode_assignment(_), do: {:error, :unavailable}

  def github_identity(job, run) do
    with %{"id" => id, "full_name" => repository, "default_branch" => default} <- run["repository"],
         true <- is_integer(id) and id > 0,
         true <- repository == job.repository and run["id"] == job.workflow_run_id,
         true <- run["run_attempt"] == job.run_attempt,
         branch when is_binary(branch) and branch != "" <- run["head_branch"],
         event when is_binary(event) <- run["event"] do
      same_repository = get_in(run, ["head_repository", "id"]) == id
      trusted = same_repository and branch == default and event in ["push", "schedule", "workflow_dispatch"]
      {:ok, %{repository_id: id, trusted: trusted, same_repository: same_repository}}
    else
      _ -> {:error, :unavailable}
    end
  end

  def buildkite_identity(assigned, %{"id" => id, "env" => env}) when is_map(env) do
    with true <- id == assigned.job_uuid,
         true <- env["BUILDKITE_JOB_ID"] == id,
         true <- env["BUILDKITE_BUILD_ID"] == assigned.build_uuid,
         true <- env["BUILDKITE_BUILD_NUMBER"] == to_string(assigned.build_number),
         true <- env["BUILDKITE_ORGANIZATION_SLUG"] == assigned.organization_slug,
         true <- env["BUILDKITE_PIPELINE_SLUG"] == assigned.pipeline_slug,
         {:ok, org} <- Ecto.UUID.cast(env["BUILDKITE_ORGANIZATION_ID"]),
         {:ok, pipeline} <- Ecto.UUID.cast(env["BUILDKITE_PIPELINE_ID"]),
         repository when is_binary(repository) and repository != "" <- env["BUILDKITE_REPO"] do
      # Use only the server-fetched protected fields, never the plugin's environment.
      repository_hash = :sha256 |> :crypto.hash(repository) |> Base.encode16(case: :lower)

      {:ok,
       %{
         provider: "buildkite",
         provider_instance: org,
         scope_id: pipeline <> ":" <> repository_hash,
         repository_id: nil,
         trusted: buildkite_writer?(env)
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def buildkite_identity(_, _), do: {:error, :unavailable}

  defp buildkite_writer?(env) do
    default = env["BUILDKITE_PIPELINE_DEFAULT_BRANCH"]

    is_binary(default) and default != "" and env["BUILDKITE_BRANCH"] == default and
      env["BUILDKITE_PULL_REQUEST"] == "false" and env["BUILDKITE_TAG"] in [nil, ""] and
      env["BUILDKITE_SOURCE"] in ["webhook", "schedule"]
  end

  def gitlab_identity(assigned, payload, remote) when is_map(payload) and is_map(remote) do
    project_id = get_in(payload, ["job_info", "project_id"])
    sha = get_in(payload, ["git_info", "sha"])

    with true <- is_integer(project_id) and project_id > 0,
         true <- payload["id"] == assigned.job_id and remote["id"] == assigned.job_id,
         %{"project_id" => ^project_id} <- remote["pipeline"],
         true <- remote["status"] == "running",
         true <- is_binary(sha) and sha != "" and get_in(remote, ["commit", "id"]) == sha,
         ref when is_binary(ref) and ref != "" <- remote["ref"] do
      {:ok,
       %{
         provider: "gitlab",
         provider_instance: GitLabCache.instance_id(assigned.url),
         scope_id: to_string(project_id),
         repository_id: project_id,
         trusted: false
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def gitlab_identity(_, _, _), do: {:error, :unavailable}

  def gitlab_writer?(remote, branches) when is_list(branches) do
    remote["tag"] == false and gitlab_pipeline_source(remote) in ["push", "schedule", "web"] and
      Enum.any?(branches, fn
        %{"name" => name, "default" => true} -> name == remote["ref"]
        _ -> false
      end)
  end

  def gitlab_writer?(_, _), do: false

  defp gitlab_pipeline_source(%{"pipeline" => %{"source" => source}}), do: source
  defp gitlab_pipeline_source(remote), do: remote["source"]
end
