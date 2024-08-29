defmodule Tuist.GitHub.Client do
  @moduledoc """
  A module to interact with the GitHub API authenticated as the Tuist GitHub app.
  """

  alias Tuist.VCS.Comment
  alias Tuist.GitHub.TokenStorage

  def get_comments(%{repository: repository, issue_id: issue_id} = attrs) do
    url = "https://api.github.com/repos/#{repository}/issues/#{issue_id}/comments"

    case github_request(&Req.get/1, url: url)
         |> handle_github_response(&get_comments/1, attrs) do
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

  def create_comment(%{repository: repository, issue_id: issue_id, body: body} = attrs) do
    url = "https://api.github.com/repos/#{repository}/issues/#{issue_id}/comments"

    github_request(&Req.post/1, url: url, json: %{body: body})
    |> handle_github_response(&create_comment/1, attrs)
  end

  def update_comment(%{repository: repository, comment_id: comment_id, body: body} = attrs) do
    url = "https://api.github.com/repos/#{repository}/issues/comments/#{comment_id}"

    github_request(&Req.patch/1, url: url, json: %{body: body})
    |> handle_github_response(&create_comment/1, attrs)
  end

  defp github_request(method, attrs) do
    case TokenStorage.get_token() do
      {:ok, %{token: token}} ->
        attrs =
          attrs
          |> Keyword.put(:headers, [
            {"Accept", "application/vnd.github.v3+json"},
            {"Authorization", "token #{token}"}
          ])

        method.(attrs)

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
    case TokenStorage.refresh_token() do
      {:ok, _} -> action.(attrs)
      result -> result
    end
  end

  defp handle_github_response({:ok, %Req.Response{status: status, body: body}}, _action, _attrs) do
    {:error, "Unexpected status code: #{status}. Body: #{Jason.encode!(body)}"}
  end

  defp handle_github_response({:error, reason}, _action, _attrs) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
