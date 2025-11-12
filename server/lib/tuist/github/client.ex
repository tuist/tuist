defmodule Tuist.GitHub.Client do
  @moduledoc """
  A module to interact with the GitHub API authenticated as the Tuist GitHub app.
  """

  alias Tuist.Base64
  alias Tuist.GitHub.App
  alias Tuist.GitHub.Retry
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.VCS.Repositories.Content
  alias Tuist.VCS.Repositories.Tag

  @doc """
  Lists repositories for a GitHub app installation with pagination support.
  Returns {:ok, %{meta: %{next_url: ...}, repositories: [...]}} format similar to Flop.
  """
  def list_installation_repositories(installation_id, opts \\ []) do
    url =
      Keyword.get(
        opts,
        :next_url,
        "https://api.github.com/installation/repositories?per_page=100"
      )

    case App.get_installation_token(installation_id) do
      {:ok, %{token: token}} ->
        req_opts =
          [
            url: url,
            headers: default_headers(token),
            finch: Tuist.Finch
          ] ++ Retry.retry_options()

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

      response ->
        response
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

  def get_user_by_id(%{id: github_id, installation_id: installation_id}) do
    url = "https://api.github.com/user/#{github_id}"

    case github_request(&Req.get/1, url: url, installation_id: installation_id) do
      {:ok, user} ->
        {:ok, %VCS.User{username: user["login"]}}

      response ->
        response
    end
  end

  def get_comments(%{
        repository_full_handle: repository_full_handle,
        issue_id: issue_id,
        installation_id: installation_id
      }) do
    url = "https://api.github.com/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    case github_request(&Req.get/1, url: url, installation_id: installation_id) do
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
        installation_id: installation_id
      }) do
    url = "https://api.github.com/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    github_request(&Req.post/1,
      url: url,
      installation_id: installation_id,
      json: %{body: body}
    )
  end

  def update_comment(%{
        repository_full_handle: repository_full_handle,
        comment_id: comment_id,
        body: body,
        installation_id: installation_id
      }) do
    url = "https://api.github.com/repos/#{repository_full_handle}/issues/comments/#{comment_id}"

    github_request(&Req.patch/1,
      url: url,
      installation_id: installation_id,
      json: %{body: body}
    )
  end

  def get_source_archive_by_tag_and_repository_full_handle(%{
        repository_full_handle: repository_full_handle,
        tag: tag,
        token: token
      }) do
    url = "https://api.github.com/repos/#{repository_full_handle}/zipball/refs/tags/#{tag}"
    {:ok, path} = Briefly.create()

    req_opts =
      [
        url: url,
        headers: default_headers(token),
        decode_body: false,
        finch: Tuist.Finch,
        into: File.stream!(path, [:write])
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %{status: 200}} ->
        {:ok, path}

      {:ok, %{status: status}} ->
        {:error,
         "Unexpected status code #{status} when downloading #{repository_full_handle} repository's source archive for #{tag} tag."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_repository_content(%{repository_full_handle: repository_full_handle, token: token}, opts \\ []) do
    path = Keyword.get(opts, :path, "")
    url = "https://api.github.com/repos/#{repository_full_handle}/contents/#{path}"

    reference = Keyword.get(opts, :reference)

    url =
      if is_nil(reference) do
        url
      else
        url <> "?ref=#{reference}"
      end

    req_opts =
      [
        url: url,
        headers: default_headers(token),
        finch: Tuist.Finch
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %{status: 200, body: %{"content" => content, "path" => path}}} ->
        {:ok, %Content{path: path, content: Base64.decode(content)}}

      {:ok, %{status: 200, body: directory_contents}} ->
        {:ok, Enum.map(directory_contents, &%Content{path: &1["path"]})}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status code: #{status} when getting contents at #{url}."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_request(method, attrs) do
    installation_id = Keyword.get(attrs, :installation_id)

    case App.get_installation_token(installation_id) do
      {:ok, %{token: token}} ->
        attrs_with_headers =
          attrs
          |> Keyword.put(:headers, [
            {"Accept", "application/vnd.github.v3+json"},
            {"Authorization", "token #{token}"}
          ])
          |> Keyword.put(:finch, Tuist.Finch)
          |> Keyword.merge(Retry.retry_options())
          |> Keyword.delete(:installation_id)

        attrs_with_headers |> method.() |> handle_github_response(method, attrs)

      {:error, response} ->
        {:error, response}
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

  def get_tags(%{repository_full_handle: repository_full_handle, token: token}, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 100)
    url = "https://api.github.com/repos/#{repository_full_handle}/tags?page_size=#{page_size}"

    get_all_tags_recursively(%{
      url: url,
      token: token,
      tags: []
    })
  end

  defp get_all_tags_recursively(%{url: url, token: token, tags: tags}) do
    req_opts =
      [
        url: url,
        headers: default_headers(token),
        finch: Tuist.Finch
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: page_tags, headers: response_headers}} ->
        page_tags = Enum.map(page_tags, &%Tag{name: &1["name"]})

        all_tags =
          tags ++ page_tags

        next_page_url = get_next_page_url_from_response_headers(response_headers)

        # If there's a next page, fetch it; otherwise, return all tags
        if next_page_url do
          get_all_tags_recursively(%{url: next_page_url, token: token, tags: all_tags})
        else
          all_tags
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, _reason} = error ->
        error
    end
  end

  defp get_next_page_url_from_response_headers(response_headers) do
    Enum.find_value(response_headers, fn
      {"link", link_header} ->
        case parse_next_page_url(link_header) do
          nil -> nil
          next_page_url -> next_page_url <> "&page_size=100"
        end

      _ ->
        nil
    end)
  end

  defp default_headers(token) do
    [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "Bearer #{token}"}
    ]
  end

  defp parse_next_page_url([link_header]) do
    # Extract the URL of the next page from the Link header, if available
    link_header
    |> String.split(",")
    |> Enum.find_value(fn link ->
      if String.contains?(link, "rel=\"next\"") do
        [url | _] = String.split(link, ";")
        # Remove any leading or trailing characters like "<", ">", and whitespace
        url
        |> String.replace(~r/[<>]/, "")
        |> String.trim()
      end
    end)
  end
end
