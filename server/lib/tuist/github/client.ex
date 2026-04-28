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

  @default_api_url "https://api.github.com"

  @doc """
  Lists repositories for a GitHub app installation with pagination support.
  Returns {:ok, %{meta: %{next_url: ...}, repositories: [...]}} format similar to Flop.
  """
  def list_installation_repositories(installation, opts \\ []) do
    {installation_id, api_url} = resolve_installation(installation)

    url =
      Keyword.get(
        opts,
        :next_url,
        "#{api_url}/installation/repositories?per_page=100"
      )

    with {:ok, %{token: token}} <- App.get_installation_token(installation_id, api_url: api_url),
         {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          headers: default_headers(token),
          finch: Tuist.Finch
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
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/user/#{github_id}"

    case github_request(&Req.get/1, url: url, installation_id: installation_id, api_url: api_url) do
      {:ok, user} ->
        {:ok, %VCS.User{username: user["login"]}}

      response ->
        response
    end
  end

  def get_comments(%{repository_full_handle: repository_full_handle, issue_id: issue_id, installation: installation}) do
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    case github_request(&Req.get/1, url: url, installation_id: installation_id, api_url: api_url) do
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
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    github_request(&Req.post/1,
      url: url,
      installation_id: installation_id,
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
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/issues/comments/#{comment_id}"

    github_request(&Req.patch/1,
      url: url,
      installation_id: installation_id,
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
    installation_id = Keyword.get(attrs, :installation_id)
    api_url = Keyword.get(attrs, :api_url, VCS.api_url(:github, nil))
    url = Keyword.fetch!(attrs, :url)

    with {:ok, %{token: token}} <- App.get_installation_token(installation_id, api_url: api_url),
         {:ok, pinned_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      attrs_with_headers =
        attrs
        |> Keyword.put(:url, pinned_url)
        |> Keyword.put(:headers, [
          {"Accept", "application/vnd.github.v3+json"},
          {"Authorization", "token #{token}"}
        ])
        |> Keyword.put(:finch, Tuist.Finch)
        |> Keyword.merge(ssrf_opts)
        |> Keyword.merge(Retry.retry_options())
        |> Keyword.delete(:installation_id)
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
    {:error, "Unexpected status code: #{status}. Body: #{Jason.encode!(body)}"}
  end

  defp handle_github_response({:error, reason}, _action, _attrs) do
    {:error, "Request failed: #{inspect(reason)}"}
  end

  def get_pull_request(%{
        repository_full_handle: repository_full_handle,
        installation: installation,
        pr_number: pr_number
      }) do
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/pulls/#{pr_number}"

    github_request(&Req.get/1,
      url: url,
      installation_id: installation_id,
      api_url: api_url
    )
  end

  def create_check_run(%{repository_full_handle: repository_full_handle, installation: installation} = params) do
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/check-runs"

    json =
      params
      |> Map.take([:name, :head_sha, :status, :conclusion, :output, :actions, :details_url])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    github_request(&Req.post/1,
      url: url,
      installation_id: installation_id,
      api_url: api_url,
      json: json
    )
  end

  def update_check_run(
        %{repository_full_handle: repository_full_handle, check_run_id: check_run_id, installation: installation} = params
      ) do
    {installation_id, api_url} = resolve_installation(installation)
    url = "#{api_url}/repos/#{repository_full_handle}/check-runs/#{check_run_id}"

    json =
      params
      |> Map.take([:status, :conclusion, :output, :actions])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    github_request(&Req.patch/1,
      url: url,
      installation_id: installation_id,
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

  defp resolve_installation(%{installation_id: id, client_url: client_url}), do: {id, VCS.api_url(:github, client_url)}

  defp resolve_installation(%{installation_id: id}), do: {id, VCS.api_url(:github, nil)}

  # Pin GHES URLs to a public IP to defend against DNS rebinding /
  # SSRF; github.com is treated as a known public host and skips the pin.
  defp pin_ghes_url(url, @default_api_url), do: {:ok, url, []}

  defp pin_ghes_url(url, _api_url) do
    case SSRFGuard.pin(url) do
      {:ok, pinned_url, hostname} ->
        {:ok, pinned_url, [connect_options: SSRFGuard.connect_options(hostname)]}

      {:error, reason} ->
        {:error, "GitHub Enterprise Server host failed SSRF check: #{inspect(reason)}"}
    end
  end
end
