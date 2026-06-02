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
  Lists the App's recent webhook deliveries (the App's central
  delivery log — App-wide, not per-installation). Used by
  `Tuist.Runners.Workers.WebhookRedeliveryWorker` to discover
  `workflow_job` deliveries we never processed.

  Options:
    * `:credentials` — App credentials map (defaults to global
      env-configured github.com App). Pass per-installation creds
      from `Tuist.VCS.list_github_apps/0` to query a GHES App's log.
    * `:api_url` — host root (defaults to api.github.com). Goes
      with `:credentials` for GHES Apps.
    * `:next_url` — opaque cursor from a previous call's `meta.next_url`
      for paginating to the next page.

  No status filter is applied. GitHub does support `?status=failure`
  server-side, but a successful redelivery from a previous cycle
  carries the same `guid` as the original failure with `status="OK"`
  — filtering to failures hides that and breaks GUID-based dedup.
  The documented recovery pattern lists ALL deliveries and groups
  locally.

  Returns `{:ok, %{meta: %{next_url}, deliveries: [...]}}`. Each
  delivery carries only metadata (no payload).

  Auth: App JWT (NOT installation token).

  See: https://docs.github.com/en/rest/apps/webhooks#list-deliveries-for-an-app-webhook
  """
  def list_app_hook_deliveries(opts \\ []) do
    api_url = Keyword.get(opts, :api_url, VCS.api_url(:github, nil))

    url =
      Keyword.get(
        opts,
        :next_url,
        "#{api_url}/app/hook/deliveries?per_page=100"
      )

    with {:ok, jwt} <- App.get_jwt(opts) do
      req_opts =
        [
          url: url,
          headers: app_jwt_headers(jwt),
          finch: Tuist.Finch
        ] ++ Retry.retry_options()

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: deliveries, headers: headers}} when is_list(deliveries) ->
          {:ok, %{meta: %{next_url: extract_next_url(headers)}, deliveries: Enum.map(deliveries, &format_delivery/1)}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  Asks GitHub to redeliver a previous webhook delivery to the App's
  configured webhook URL. GitHub re-fires through the normal
  delivery path — same signature, same handler, same idempotency
  guarantees. Used by the recovery worker after a failed delivery is
  discovered.

  Options `:credentials` and `:api_url` work the same as in
  `list_app_hook_deliveries/1` — pass the App that owns the
  `delivery_id` you're redelivering.

  Returns `:ok` on the documented 202 Accepted response.

  See: https://docs.github.com/en/rest/apps/webhooks#redeliver-a-delivery-for-an-app-webhook
  """
  def redeliver_app_hook_delivery(delivery_id, opts \\ []) when is_integer(delivery_id) do
    api_url = Keyword.get(opts, :api_url, VCS.api_url(:github, nil))
    url = "#{api_url}/app/hook/deliveries/#{delivery_id}/attempts"

    with {:ok, jwt} <- App.get_jwt(opts) do
      req_opts =
        [
          url: url,
          headers: app_jwt_headers(jwt),
          finch: Tuist.Finch
        ] ++ Retry.retry_options()

      case Req.post(req_opts) do
        {:ok, %{status: 202}} ->
          :ok

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  defp format_delivery(d) do
    %{
      id: d["id"],
      guid: d["guid"],
      delivered_at: parse_iso8601(d["delivered_at"]),
      redelivery: d["redelivery"] || false,
      status: d["status"] || "",
      status_code: d["status_code"],
      event: d["event"] || "",
      action: d["action"] || "",
      installation_id: d["installation_id"],
      repository_id: d["repository_id"]
    }
  end

  defp app_jwt_headers(jwt) do
    [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
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
