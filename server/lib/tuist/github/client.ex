defmodule Tuist.GitHub.Client do
  @moduledoc """
  A module to interact with the GitHub API authenticated as the Tuist GitHub app.

  Functions that target a specific installation accept an `:installation`
  field — any struct or map carrying `:installation_id` and `:client_url`.
  The host of the GitHub instance (github.com or a self-hosted GitHub
  Enterprise Server) is derived from `:client_url`.
  """

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Retry
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.VCS.Repositories.Content
  alias Tuist.VCS.Repositories.Tag

  @doc """
  Lists repositories for a GitHub app installation with pagination support.
  Returns {:ok, %{meta: %{next_url: ...}, repositories: [...]}} format similar to Flop.
  """
  def list_installation_repositories(installation, opts \\ []) do
    api_url = installation_api_url(installation)

    url =
      Keyword.get(
        opts,
        :next_url,
        "#{api_url}/installation/repositories?per_page=100"
      )

    with {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          headers: default_headers(token)
        ] ++ ssrf_opts ++ Retry.retry_options()

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"repositories" => repositories}, headers: headers}} ->
          formatted_repos =
            Enum.map(repositories, fn repo ->
              %{
                id: repo["id"],
                name: repo["name"],
                full_name: repo["full_name"],
                private: repo["private"],
                default_branch: repo["default_branch"]
              }
            end)

          next_url = extract_next_url(headers)
          meta = %{next_url: next_url}

          {:ok, %{meta: meta, repositories: formatted_repos}}

        {:ok, %{status: _status, body: _body}} ->
          {:error, "Failed to fetch repositories"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  defp extract_next_url(headers) do
    Enum.find_value(headers, fn
      {"link", [link_header | _]} ->
        parse_link_header(link_header)

      _ ->
        nil
    end)
  end

  defp parse_link_header(link_header) do
    # Parse GitHub's Link header format: <url>; rel="next"
    case Regex.run(~r/<([^>]+)>;\s*rel="next"/, link_header) do
      [_, next_url] -> next_url
      _ -> nil
    end
  end

  def get_user_by_id(%{id: github_id, installation: installation}) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/user/#{github_id}"

    case github_request(&Req.get/1, url: url, installation: installation, api_url: api_url) do
      {:ok, user} ->
        {:ok, %VCS.User{username: user["login"]}}

      response ->
        response
    end
  end

  def get_comments(%{repository_full_handle: repository_full_handle, issue_id: issue_id, installation: installation}) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    case github_request(&Req.get/1, url: url, installation: installation, api_url: api_url) do
      {:ok, comments} ->
        {:ok,
         Enum.map(comments, fn comment ->
           client_id =
             if is_nil(comment["performed_via_github_app"]) do
               nil
             else
               comment["performed_via_github_app"]["client_id"]
             end

           %Comment{id: comment["id"], client_id: client_id, body: comment["body"]}
         end)}

      response ->
        response
    end
  end

  def create_comment(%{
        repository_full_handle: repository_full_handle,
        issue_id: issue_id,
        body: body,
        installation: installation
      }) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    github_request(&Req.post/1,
      url: url,
      installation: installation,
      api_url: api_url,
      json: %{body: body}
    )
  end

  def update_comment(%{
        repository_full_handle: repository_full_handle,
        comment_id: comment_id,
        body: body,
        installation: installation
      }) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/issues/comments/#{comment_id}"

    github_request(&Req.patch/1,
      url: url,
      installation: installation,
      api_url: api_url,
      json: %{body: body}
    )
  end

  def get_source_archive_by_tag_and_repository_full_handle(%{
        repository_full_handle: repository_full_handle,
        tag: tag,
        token: token
      }) do
    {:ok, path} = Briefly.create()

    case TuistCommon.GitHub.download_zipball(
           repository_full_handle,
           token,
           tag,
           path,
           finch_opts()
         ) do
      :ok ->
        {:ok, path}

      {:error, {:http_error, status}} ->
        {:error,
         "Unexpected status code #{status} when downloading #{repository_full_handle} repository's source archive for #{tag} tag."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_repository_content(%{repository_full_handle: repository_full_handle, token: token}, opts \\ []) do
    path = Keyword.get(opts, :path, "")
    reference = Keyword.get(opts, :reference, "HEAD")

    case TuistCommon.GitHub.get_repository_content(
           repository_full_handle,
           token,
           path,
           reference,
           finch_opts()
         ) do
      {:ok, {:file, content}} ->
        {:ok, %Content{path: path, content: content}}

      {:ok, {:directory, directory_contents}} ->
        {:ok, Enum.map(directory_contents, &%Content{path: &1["path"]})}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, {:http_error, status}} ->
        {:error, "Unexpected status code: #{status} when getting contents."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_request(method, attrs) do
    installation = Keyword.get(attrs, :installation)
    api_url = Keyword.get(attrs, :api_url, VCS.api_url(:github, nil))
    url = Keyword.fetch!(attrs, :url)

    with {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, pinned_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      attrs_with_headers =
        attrs
        |> Keyword.put(:url, pinned_url)
        |> Keyword.put(:headers, [
          {"Accept", "application/vnd.github.v3+json"},
          {"Authorization", "token #{token}"}
        ])
        |> Keyword.merge(ssrf_opts)
        |> Keyword.merge(Retry.retry_options())
        |> Keyword.delete(:installation)
        |> Keyword.delete(:api_url)

      attrs_with_headers |> method.() |> handle_github_response(method, attrs)
    end
  end

  defp handle_github_response({:ok, %{status: 200, body: body}}, _action, _attrs) do
    {:ok, body}
  end

  defp handle_github_response({:ok, %{status: 201, body: ""}}, _action, _attrs) do
    :ok
  end

  defp handle_github_response({:ok, %{status: 201, body: body}}, _action, _attrs) do
    {:ok, body}
  end

  defp handle_github_response({:ok, %{status: 201}}, _action, _attrs) do
    :ok
  end

  defp handle_github_response({:ok, %{status: 401}}, action, attrs) do
    App.clear_token()
    github_request(action, attrs)
  end

  defp handle_github_response({:ok, %Req.Response{status: status, body: body}}, _action, _attrs) do
    {:error, "Unexpected status code: #{status}. Body: #{JSON.encode!(body)}"}
  end

  defp handle_github_response({:error, reason}, _action, _attrs) do
    {:error, "Request failed: #{inspect(reason)}"}
  end

  def get_pull_request(%{
        repository_full_handle: repository_full_handle,
        installation: installation,
        pr_number: pr_number
      }) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/pulls/#{pr_number}"

    github_request(&Req.get/1,
      url: url,
      installation: installation,
      api_url: api_url
    )
  end

  def create_check_run(%{repository_full_handle: repository_full_handle, installation: installation} = params) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/check-runs"

    json =
      params
      |> Map.take([:name, :head_sha, :status, :conclusion, :output, :actions, :details_url])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    github_request(&Req.post/1,
      url: url,
      installation: installation,
      api_url: api_url,
      json: json
    )
  end

  def update_check_run(
        %{repository_full_handle: repository_full_handle, check_run_id: check_run_id, installation: installation} = params
      ) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/check-runs/#{check_run_id}"

    json =
      params
      |> Map.take([:status, :conclusion, :output, :actions])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    github_request(&Req.patch/1,
      url: url,
      installation: installation,
      api_url: api_url,
      json: json
    )
  end

  def get_tags(%{repository_full_handle: repository_full_handle, token: token}, _opts \\ []) do
    case TuistCommon.GitHub.list_tags(repository_full_handle, token, finch_opts()) do
      {:ok, tags} ->
        Enum.map(tags, &%Tag{name: &1})

      {:error, _reason} = error ->
        error
    end
  end

  defp finch_opts do
    [finch: Tuist.Finch] ++ Retry.retry_options()
  end

  defp default_headers(token) do
    [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "Bearer #{token}"}
    ]
  end

  @doc """
  Generates a just-in-time runner configuration for an ephemeral
  GitHub Actions self-hosted runner registered at the org level.
  The returned `encoded_jit_config` is what the in-VM
  `./run.sh --jitconfig` consumes; runners registered this way
  are single-shot and auto-cleaned by GitHub after they exit.

  Org-scoped (vs. repo-scoped) intentionally — the repo-scoped
  endpoint requires the GH App to hold `administration: write`
  on the repo, which grants access to settings, secrets,
  collaborators, and many other unrelated capabilities. The
  org-scoped endpoint requires only
  `organization_self_hosted_runners: write`, a targeted scope
  that does only what the name implies.

  Runners registered at the org level are usable by any repo in
  the org subject to the runner-group's repo allowlist. The
  default group ID is 1; pass a different `:runner_group_id` in
  `attrs` to register the runner into a restricted group.

  See: https://docs.github.com/en/rest/actions/self-hosted-runners#create-configuration-for-a-just-in-time-runner-for-an-organization
  """
  def generate_jit_config(installation, org, attrs) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/orgs/#{org}/actions/runners/generate-jitconfig"

    body = %{
      "name" => Map.fetch!(attrs, :name),
      "runner_group_id" => Map.get(attrs, :runner_group_id, 1),
      "labels" => Map.fetch!(attrs, :labels),
      "work_folder" => Map.get(attrs, :work_folder, "_work")
    }

    with {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          json: body,
          headers: default_headers(token)
        ] ++ ssrf_opts ++ Retry.retry_options()

      case Req.post(req_opts) do
        {:ok, %{status: 201, body: %{"encoded_jit_config" => jit, "runner" => runner}}} ->
          {:ok, %{encoded_jit_config: jit, runner_id: runner["id"], runner_name: runner["name"]}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  GETs a single `workflow_job` and returns the GitHub-side status
  (`"queued"` / `"in_progress"` / `"completed"`). Used by
  `OrphanedRunnersWorker` to detect rows we transitioned to
  `running` locally but whose JIT was never consumed by an
  actually-registered runner on the GH side — the GitHub view of
  the job is the only authoritative signal for "did the Pod
  successfully come up".

  `repository_full_handle` is the standard `<owner>/<repo>` form
  GitHub uses everywhere.

  See: https://docs.github.com/en/rest/actions/workflow-jobs#get-a-job-for-a-workflow-run
  """
  def get_workflow_job(installation, repository_full_handle, workflow_job_id)
      when is_binary(repository_full_handle) and is_integer(workflow_job_id) do
    api_url = installation_api_url(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/actions/jobs/#{workflow_job_id}"

    with {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          headers: default_headers(token)
        ] ++ ssrf_opts ++ Retry.retry_options()

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"status" => status} = job}} when is_binary(status) ->
          {:ok, %{status: status, conclusion: Map.get(job, "conclusion"), runner_name: Map.get(job, "runner_name")}}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  Lists `workflow_run`s for a repository, filtered by `status`. Used
  by `Tuist.Runners.Workers.MissedQueuedWorker` to enumerate runs
  that might contain queued workflow_jobs whose `workflow_job.queued`
  webhooks were never delivered.

  Pass `:created_after` (a `DateTime`) to cap the API result size via
  GitHub's `created=>=...` filter. The caller is responsible for any
  pagination — when `meta.next_url` is non-nil, pass it as `:next_url`
  on the next call to fetch the subsequent page.

  Returns `{:ok, %{meta: %{next_url}, runs: [...]}}`.

  See: https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository
  """
  def list_workflow_runs(installation, repository_full_handle, status, opts \\ [])
      when is_binary(repository_full_handle) and is_binary(status) do
    api_url = installation_api_url(installation)

    url =
      Keyword.get(
        opts,
        :next_url,
        "#{api_url}/repos/#{repository_full_handle}/actions/runs?#{build_runs_query(status, opts)}"
      )

    with {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          headers: default_headers(token)
        ] ++ ssrf_opts ++ Retry.retry_options()

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"workflow_runs" => runs}, headers: headers}} when is_list(runs) ->
          {:ok, %{meta: %{next_url: extract_next_url(headers)}, runs: Enum.map(runs, &format_workflow_run/1)}}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  defp build_runs_query(status, opts) do
    base = [{"status", status}, {"per_page", "100"}]

    base =
      case Keyword.get(opts, :created_after) do
        %DateTime{} = ts -> base ++ [{"created", ">=" <> DateTime.to_iso8601(ts)}]
        _ -> base
      end

    URI.encode_query(base)
  end

  defp format_workflow_run(run) do
    %{
      id: run["id"],
      name: run["name"] || "",
      head_branch: run["head_branch"] || "",
      head_sha: run["head_sha"] || "",
      run_attempt: run["run_attempt"] || 1
    }
  end

  @doc """
  Lists ALL `workflow_job`s for a `workflow_run`, paginating
  internally through GitHub's `Link: rel="next"` header. Matrix
  workflows can expand to hundreds of jobs; returning only the first
  page would silently drop the rest, defeating recovery for any
  missed webhook on page 2+.

  `filter` controls which run attempts GitHub returns:
    * `"latest"` (default) — only the most recent attempt's jobs.
    * `"all"` — every attempt's jobs.

  See: https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run
  """
  def list_workflow_run_jobs(installation, repository_full_handle, run_id, opts \\ [])
      when is_binary(repository_full_handle) and is_integer(run_id) do
    api_url = installation_api_url(installation)
    filter = Keyword.get(opts, :filter, "latest")
    url = "#{api_url}/repos/#{repository_full_handle}/actions/runs/#{run_id}/jobs?filter=#{filter}&per_page=100"

    fetch_jobs_pages(installation, api_url, url, [])
  end

  defp fetch_jobs_pages(_installation, _api_url, nil, acc), do: {:ok, acc}

  defp fetch_jobs_pages(installation, api_url, url, acc) do
    with {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          headers: default_headers(token)
        ] ++ ssrf_opts ++ Retry.retry_options()

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"jobs" => jobs}, headers: headers}} when is_list(jobs) ->
          next_url = extract_next_url(headers)
          fetch_jobs_pages(installation, api_url, next_url, acc ++ Enum.map(jobs, &format_workflow_job/1))

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  defp format_workflow_job(job) do
    %{
      id: job["id"],
      run_id: job["run_id"],
      run_attempt: job["run_attempt"] || 1,
      name: job["name"] || "",
      status: job["status"] || "",
      labels: List.wrap(job["labels"]),
      head_branch: job["head_branch"] || "",
      head_sha: job["head_sha"] || "",
      created_at: parse_iso8601(job["created_at"])
    }
  end

  defp parse_iso8601(nil), do: nil

  defp parse_iso8601(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_iso8601(_), do: nil

  defp installation_api_url(%{client_url: client_url}), do: VCS.api_url(:github, client_url)
  defp installation_api_url(_), do: VCS.api_url(:github, nil)

  # Pin GHES URLs to a public IP to defend against DNS rebinding /
  # SSRF; github.com is treated as a known public host and skips the pin.
  #
  # github.com uses the shared `Tuist.Finch` pool. GHES uses Req's default
  # pool because the per-host `:connect_options` (SNI / cert hostname) are
  # mutually exclusive with a user-supplied `:finch` pool.
  defp pin_ghes_url(url, "https://api.github.com"), do: {:ok, url, [finch: Tuist.Finch]}

  defp pin_ghes_url(url, _api_url) do
    case SSRFGuard.pin(url) do
      {:ok, pinned_url, hostname} ->
        {:ok, pinned_url, [connect_options: SSRFGuard.connect_options(hostname)]}

      {:error, reason} ->
        {:error, "GitHub Enterprise Server host failed SSRF check: #{inspect(reason)}"}
    end
  end
end
