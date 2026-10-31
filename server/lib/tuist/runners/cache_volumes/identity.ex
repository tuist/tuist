defmodule Tuist.Runners.CacheVolumes.Identity do
  @moduledoc "Verified CI identity for a running pod's cache-volume allocation."

  import Ecto.Query

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.GitLab.Cache, as: GitLabCache
  alias Tuist.Runners.GitLab.Client, as: GitLabClient
  alias Tuist.Runners.RunnerSession
  alias Tuist.VCS

  @default_branch_ttl to_timeout(hour: 1)

  def resolve(%{provider: "github"} = job) do
    case execution_identity(job) do
      %{} = claims -> claimed_identity(job, claims)
      nil -> github_api_identity(job)
    end
  end

  def resolve(%{provider: "buildkite", account_id: account_id} = job) do
    with %Buildkite.Job{account_id: ^account_id, cache_volume_identity: identity} <-
           Buildkite.get_job(job.workflow_job_id),
         %Buildkite.Installation{enabled: true} <- Buildkite.get_installation(account_id),
         %{"provider" => "buildkite", "provider_instance" => instance, "scope_id" => scope, "trusted" => trusted} <-
           identity,
         true <- is_binary(instance) and is_binary(scope) and is_boolean(trusted) do
      {:ok,
       %{
         provider: "buildkite",
         provider_instance: instance,
         scope_id: scope,
         repository_id: nil,
         trusted: trusted,
         writer_branch: buildkite_stored_writer_branch(identity["writer_branch"])
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def resolve(%{provider: "gitlab", account_id: account_id} = job) do
    case GitLab.get_job(job.workflow_job_id) do
      %GitLab.Job{account_id: ^account_id, cache_volume_identity: %{} = identity} ->
        stored_gitlab_identity(identity)

      %GitLab.Job{account_id: ^account_id} = assigned ->
        live_gitlab_identity(assigned)

      _ ->
        {:error, :unavailable}
    end
  end

  def resolve(_), do: {:error, :unavailable}

  @doc """
  Resolves and stores a GitLab job's cache volume identity when the job is
  acquired, while its job token is fresh, so allocation does not call GitLab.
  A failed lookup stores nothing and allocation resolves it live instead.
  """
  def capture_gitlab(%GitLab.Job{} = assigned) do
    case live_gitlab_identity(assigned) do
      {:ok, identity} ->
        stored = Map.new(identity, fn {key, value} -> {Atom.to_string(key), value} end)
        GitLab.store_cache_volume_identity(assigned, stored)

      _ ->
        :ok
    end
  end

  defp live_gitlab_identity(%GitLab.Job{} = assigned) do
    with {:ok, payload} <- decode_assignment(assigned.payload),
         {:ok, remote} <- GitLabClient.get_running_job(assigned.url, payload["token"]),
         {:ok, identity} <- gitlab_identity(assigned, payload, remote),
         {:ok, branches} <-
           GitLabClient.cache_branches(assigned.url, payload["token"], identity.repository_id, remote["ref"]) do
      writer_branch = gitlab_writer_branch(remote) || gitlab_merge_request_writer_branch(assigned, identity, remote)
      {:ok, Map.merge(identity, %{trusted: gitlab_writer?(remote, branches), writer_branch: writer_branch})}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp stored_gitlab_identity(
         %{
           "provider" => "gitlab",
           "provider_instance" => instance,
           "scope_id" => scope,
           "repository_id" => repository_id,
           "trusted" => trusted
         } = identity
       )
       when is_binary(instance) and is_binary(scope) and is_integer(repository_id) and is_boolean(trusted) do
    writer_branch = identity["writer_branch"]

    {:ok,
     %{
       provider: "gitlab",
       provider_instance: instance,
       scope_id: scope,
       repository_id: repository_id,
       trusted: trusted,
       writer_branch: if(is_binary(writer_branch) and writer_branch != "", do: writer_branch)
     }}
  end

  defp stored_gitlab_identity(_identity), do: {:error, :unavailable}

  # The claims of the GitHub OIDC token that bound the job's session
  # (`Tuist.Runners.ExecutionTokens`), when that token named this job.
  defp execution_identity(job) do
    Repo.one(
      from(s in RunnerSession,
        where:
          s.account_id == ^job.account_id and s.executed_workflow_job_id == ^job.workflow_job_id and
            not is_nil(s.execution_identity),
        order_by: [desc: s.started_at],
        limit: 1,
        select: s.execution_identity
      )
    )
  end

  # Push, schedule and workflow_dispatch runs are runs of the repository itself,
  # so the token's claims settle their identity; only the default branch, which
  # no claim carries, comes from GitHub. A pull request still needs the run to
  # tell a fork from the repository itself; when GitHub cannot answer, the job
  # reads its repository's volumes and saves nothing.
  defp claimed_identity(job, claims) do
    with true <- claims["workflow_job_id"] == job.workflow_job_id,
         {:ok, repository_id} <- claimed_integer(claims["repository_id"]),
         true <- claims["repository"] == job.repository,
         true <- claimed_integer(claims["run_id"]) == {:ok, job.workflow_run_id},
         true <- claimed_integer(claims["run_attempt"]) == {:ok, job.run_attempt} do
      branch = claimed_branch(claims)

      if claims["event_name"] in ["push", "schedule", "workflow_dispatch"] and branch do
        case default_branch(job, repository_id) do
          {:ok, default} ->
            {:ok,
             %{
               repository_id: repository_id,
               trusted: branch == default,
               same_repository: true,
               default_branch: default,
               writer_branch: branch
             }}

          :error ->
            github_api_identity(job, read_only(repository_id, true))
        end
      else
        github_api_identity(job, read_only(repository_id, false))
      end
    else
      _ -> github_api_identity(job)
    end
  end

  defp read_only(repository_id, same_repository),
    do: {:ok, %{repository_id: repository_id, trusted: false, same_repository: same_repository, writer_branch: nil}}

  defp claimed_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp claimed_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> :error
    end
  end

  defp claimed_integer(_value), do: :error

  defp claimed_branch(%{"ref" => "refs/heads/" <> branch}) when branch != "", do: branch
  defp claimed_branch(%{"ref" => "refs/tags/" <> tag}) when tag != "", do: tag
  defp claimed_branch(_claims), do: nil

  # GitHub's answer, cached for an hour; when GitHub cannot answer, the default
  # branch the repository's volumes last recorded.
  defp default_branch(job, repository_id) do
    fetched =
      KeyValueStore.get_or_update(
        ["runners", "github_default_branch", job.account_id, repository_id],
        [ttl: @default_branch_ttl, cache_errors: false],
        fn ->
          with {:ok, installation} <- VCS.get_github_app_installation_for_account(job.account_id),
               {:ok, %{"id" => ^repository_id, "default_branch" => default}} when is_binary(default) <-
                 GitHubClient.get_repository(installation, job.repository) do
            {:ok, default}
          else
            _ -> {:error, :unavailable}
          end
        end
      )

    case fetched do
      {:ok, default} -> {:ok, default}
      _ -> recorded_default_branch(job.account_id, repository_id)
    end
  end

  defp recorded_default_branch(account_id, repository_id) do
    Repo.one(
      from(v in Volume,
        where:
          v.account_id == ^account_id and v.provider == "github" and v.repository_id == ^repository_id and
            not is_nil(v.default_branch),
        order_by: [desc: v.updated_at],
        limit: 1,
        select: v.default_branch
      )
    )
    |> case do
      default when is_binary(default) -> {:ok, default}
      nil -> :error
    end
  end

  # The run and repository read through the installation; `fallback` is the
  # identity to use when GitHub cannot answer.
  defp github_api_identity(job, fallback \\ {:error, :unavailable}) do
    with {:ok, installation} <- VCS.get_github_app_installation_for_account(job.account_id),
         {:ok, run} <-
           GitHubClient.get_workflow_run(%{
             repository_full_handle: job.repository,
             installation: installation,
             run_id: job.workflow_run_id
           }),
         {:ok, repository} <- GitHubClient.get_repository(installation, job.repository),
         true <- repository["id"] == get_in(run, ["repository", "id"]) do
      case github_identity(job, Map.put(run, "repository", repository)) do
        {:ok, identity} -> {:ok, identity}
        _ -> fallback
      end
    else
      _ -> fallback
    end
  end

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

      {:ok,
       %{
         repository_id: id,
         trusted: trusted,
         same_repository: same_repository,
         default_branch: default,
         writer_branch: github_writer_branch(run, id, same_repository)
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  # The branch a runner profile's writer patterns are matched against. Use
  # provider-fetched repository IDs and PR head metadata: a workflow cannot grant
  # itself publication by supplying a branch name or commit input. Forks,
  # pull_request_target and other events never qualify. On push and dispatch
  # runs head_branch can also be a tag name, as for the default-branch check.
  defp github_writer_branch(run, repository_id, true) do
    branch = run["head_branch"]

    case run["event"] do
      "pull_request" ->
        case run["pull_requests"] do
          [%{"head" => %{"repo" => %{"id" => ^repository_id}, "ref" => ^branch}} | _] -> branch
          _ -> nil
        end

      event when event in ["push", "schedule", "workflow_dispatch"] ->
        branch

      _ ->
        nil
    end
  end

  defp github_writer_branch(_, _, _), do: nil

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
         trusted: buildkite_writer?(env),
         writer_branch: buildkite_writer_branch(env, repository)
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

  # The branch a runner profile's writer patterns are matched against. Webhook
  # and schedule builds of the pipeline's repository qualify, including pull
  # requests whose head is that repository. Fork pull requests, tags, and API or
  # manually triggered builds, which can build any commit, never do.
  defp buildkite_writer_branch(env, repository) do
    branch = env["BUILDKITE_BRANCH"]

    with true <- is_binary(branch) and branch != "",
         true <- env["BUILDKITE_TAG"] in [nil, ""],
         true <- env["BUILDKITE_SOURCE"] in ["webhook", "schedule"],
         true <- buildkite_same_repository_build?(env, repository) do
      branch
    else
      _ -> nil
    end
  end

  defp buildkite_same_repository_build?(%{"BUILDKITE_PULL_REQUEST" => "false"}, _repository), do: true

  defp buildkite_same_repository_build?(%{"BUILDKITE_PULL_REQUEST_REPO" => pull_request_repository}, repository)
       when is_binary(pull_request_repository) and pull_request_repository != "",
       do: Buildkite.same_repository?(pull_request_repository, repository)

  defp buildkite_same_repository_build?(_env, _repository), do: false

  defp buildkite_stored_writer_branch(branch) when is_binary(branch) and branch != "", do: branch
  defp buildkite_stored_writer_branch(_), do: nil

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

  # The branch a runner profile's writer patterns are matched against. Only
  # branch pipelines of the project qualify: creating one takes push access or a
  # project member. Merge request pipelines never do, because the job token
  # can't tell whether a merge request comes from a fork.
  def gitlab_writer_branch(%{"tag" => false, "ref" => ref} = remote) when is_binary(ref) and ref != "" do
    if gitlab_pipeline_source(remote) in ["push", "schedule", "web"], do: ref
  end

  def gitlab_writer_branch(_), do: nil

  # A merge request pipeline saves under its source branch when the connection's
  # API token shows the merge request comes from the project itself. GitLab sets
  # the ref, so the merge request number can't be supplied by the pipeline. A
  # missing token or a failed lookup leaves the job read-only.
  defp gitlab_merge_request_writer_branch(assigned, identity, remote) do
    with %GitLab.Connection{account_id: account_id, url: url, api_token: api_token} <-
           assigned.connection_id && GitLab.get_connection(assigned.connection_id),
         true <- account_id == assigned.account_id and url == assigned.url and is_binary(api_token) and api_token != "",
         {:ok, iid} <- gitlab_merge_request_iid(remote),
         {:ok, merge_request} <- GitLabClient.get_merge_request(url, api_token, identity.repository_id, iid) do
      gitlab_merge_request_source_branch(merge_request, identity.repository_id, iid)
    else
      _ -> nil
    end
  end

  def gitlab_merge_request_iid(%{"tag" => false, "ref" => ref} = remote) when is_binary(ref) do
    with "merge_request_event" <- gitlab_pipeline_source(remote),
         [_, iid] <- Regex.run(~r/\Arefs\/merge-requests\/([1-9][0-9]{0,9})\/(?:head|merge|train)\z/, ref) do
      {:ok, String.to_integer(iid)}
    else
      _ -> :error
    end
  end

  def gitlab_merge_request_iid(_), do: :error

  def gitlab_merge_request_source_branch(
        %{"iid" => iid, "project_id" => project_id, "source_project_id" => project_id, "source_branch" => branch},
        project_id,
        iid
      )
      when is_binary(branch) and branch != "", do: branch

  def gitlab_merge_request_source_branch(_, _, _), do: nil

  defp gitlab_pipeline_source(%{"pipeline" => %{"source" => source}}), do: source
  defp gitlab_pipeline_source(remote), do: remote["source"]
end
