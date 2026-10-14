defmodule Tuist.Origin.Client do
  @moduledoc """
  Origin's installation-scoped REST API. Transport errors and non-success responses
  remain errors so report workers retry rather than silently lose feedback.
  """

  alias Tuist.Origin.Auth

  @base_url "https://api.cursor.com/v1/origin"

  def get_installation(id) do
    with {:ok, token} <- Auth.app_jwt(), do: request(:get, "/app/installations/#{segment(id)}", token)
  end

  def delete_installation(id) do
    with {:ok, token} <- Auth.app_jwt(), do: request(:delete, "/app/installations/#{segment(id)}", token)
  end

  def get_installation_token(id, grant \\ %{}) do
    with {:ok, jwt} <- Auth.app_jwt(),
         {:ok, %{"token" => token}} <- request(:post, "/app/installations/#{segment(id)}/access_tokens", jwt, json: grant) do
      {:ok, token}
    end
  end

  def repositories(installation) do
    paginate(installation, "/installation/repos", "repositories")
  end

  def pull_requests(installation, repository, sha) do
    paginate(installation, repo_path(repository) <> "/pulls", "pullRequests", headSha: sha, state: "open")
  end

  def get_pull_request(installation, repository, number) do
    installation_request(:get, repo_path(repository) <> "/pulls/#{segment(number)}", installation)
  end

  def get_git_ref(installation, repository, ref) do
    installation_request(:get, repo_path(repository) <> "/git/ref/#{segment(ref)}", installation)
  end

  def get_git_commit(installation, repository, sha) do
    installation_request(:get, repo_path(repository) <> "/git/commits/#{segment(sha)}", installation)
  end

  def comments(installation, repository, number) do
    paginate(installation, repo_path(repository) <> "/pulls/#{segment(number)}/comments", "comments")
  end

  def create_comment(installation, repository, number, body) do
    installation_request(:post, repo_path(repository) <> "/pulls/#{segment(number)}/comments", installation,
      json: %{body: body}
    )
  end

  def update_comment(installation, repository, id, body) do
    installation_request(:patch, repo_path(repository) <> "/pulls/comments/#{segment(id)}", installation,
      json: %{body: body}
    )
  end

  def post_check_run(installation, repository, body) do
    installation_request(:post, repo_path(repository) <> "/check-runs", installation, json: body)
  end

  defp paginate(installation, path, collection, params \\ [], pages \\ [], seen \\ MapSet.new()) do
    with {:ok, body} <- installation_request(:get, path, installation, params: [pageSize: 100] ++ params),
         items when is_list(items) <- body[collection] do
      pages = [items | pages]

      case body["nextPageToken"] do
        token when token in [nil, ""] ->
          {:ok, pages |> Enum.reverse() |> List.flatten()}

        token ->
          if MapSet.member?(seen, token) or MapSet.size(seen) >= 100 do
            {:error, :invalid_pagination}
          else
            paginate(
              installation,
              path,
              collection,
              Keyword.put(params, :pageToken, token),
              pages,
              MapSet.put(seen, token)
            )
          end
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp installation_request(method, path, %{installation_id: id}, opts \\ []) do
    with {:ok, token} <- get_installation_token(id), do: request(method, path, token, opts)
  end

  defp request(method, path, token, opts \\ []) do
    opts =
      Keyword.merge(
        [
          method: method,
          url: @base_url <> path,
          auth: {:bearer, token},
          retry: false,
          redirect: false,
          receive_timeout: 10_000
        ],
        opts
      )

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, _} -> {:error, :transport}
    end
  end

  defp repo_path(handle) do
    "/repos/" <> Enum.map_join(String.split(handle, "/"), "/", &segment/1)
  end

  defp segment(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
end
