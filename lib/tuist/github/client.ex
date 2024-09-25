defmodule Tuist.GitHub.Client do
  @moduledoc """
  A module to interact with the GitHub API authenticated as the Tuist GitHub app.
  """

  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.GitHub.App

  @doc """
  `repository_full_handle` is necessary as to interact with the user endpoint,
  we need to be authenticated with the GitHub app installation token associated with a specific repository.
  """
  def get_user_by_id(%{id: github_id, repository_full_handle: repository_full_handle}) do
    url = "https://api.github.com/user/#{github_id}"

    case github_request(&Req.get/1, url: url, repository_full_handle: repository_full_handle) do
      {:ok, user} ->
        {:ok, %VCS.User{username: user["login"]}}

      response ->
        response
    end
  end

  def get_repository(repository_full_handle) do
    url = "https://api.github.com/repos/#{repository_full_handle}"

    case github_request(&Req.get/1, url: url, repository_full_handle: repository_full_handle) do
      {:ok, repository} ->
        {:ok,
         %VCS.Repositories.Repository{
           full_handle: repository["full_name"],
           default_branch: repository["default_branch"],
           provider: :github
         }}

      response ->
        response
    end
  end

  def get_user_permission(%{username: username, repository_full_handle: repository_full_handle}) do
    url =
      "https://api.github.com/repos/#{repository_full_handle}/collaborators/#{username}/permission"

    case github_request(&Req.get/1, url: url, repository_full_handle: repository_full_handle) do
      {:ok, permission} ->
        {:ok, %VCS.Repositories.Permission{permission: permission["permission"]}}

      response ->
        response
    end
  end

  def get_comments(%{repository_full_handle: repository_full_handle, issue_id: issue_id}) do
    url = "https://api.github.com/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    case github_request(&Req.get/1, url: url, repository_full_handle: repository_full_handle) do
      {:ok, comments} ->
        {:ok,
         comments
         |> Enum.map(fn comment ->
           client_id =
             if is_nil(comment["performed_via_github_app"]) do
               nil
             else
               comment["performed_via_github_app"]["client_id"]
             end

           %Comment{id: comment["id"], client_id: client_id}
         end)}

      response ->
        response
    end
  end

  def create_comment(%{
        repository_full_handle: repository_full_handle,
        issue_id: issue_id,
        body: body
      }) do
    url = "https://api.github.com/repos/#{repository_full_handle}/issues/#{issue_id}/comments"

    github_request(&Req.post/1,
      url: url,
      repository_full_handle: repository_full_handle,
      json: %{body: body}
    )
  end

  def update_comment(%{
        repository_full_handle: repository_full_handle,
        comment_id: comment_id,
        body: body
      }) do
    url = "https://api.github.com/repos/#{repository_full_handle}/issues/comments/#{comment_id}"

    github_request(&Req.patch/1,
      url: url,
      repository_full_handle: repository_full_handle,
      json: %{body: body}
    )
  end

  defp github_request(method, attrs) do
    repository_full_handle = Keyword.get(attrs, :repository_full_handle)

    case App.get_app_installation_token_for_repository(repository_full_handle) do
      {:ok, %{token: token}} ->
        attrs_with_headers =
          attrs
          |> Keyword.put(:headers, [
            {"Accept", "application/vnd.github.v3+json"},
            {"Authorization", "token #{token}"}
          ])
          |> Keyword.delete(:repository_full_handle)

        method.(attrs_with_headers)
        |> handle_github_response(method, attrs)

      {:error, response} ->
        {:error, response}
    end
  end

  defp handle_github_response({:ok, %{status: 200, body: body}}, _action, _attrs) do
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
end
