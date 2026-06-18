defmodule TuistOps.Previews.GitHubActionsClient do
  @moduledoc """
  Minimal GitHub Actions workflow-dispatch client for previews.
  """

  alias TuistOps.Environment

  def dispatch(action, inputs) when action in ["create", "delete"] and is_map(inputs) do
    repo = Environment.github_repository()
    workflow_id = Environment.preview_workflow_id()
    ref = Environment.github_workflow_ref()

    url = "https://api.github.com/repos/#{repo}/actions/workflows/#{workflow_id}/dispatches"

    body = %{
      ref: ref,
      inputs: Map.put(inputs, :action, action)
    }

    url
    |> Req.post(headers: headers(), body: JSON.encode!(body))
    |> handle_dispatch(workflow_id, ref)
  end

  defp headers do
    [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{Environment.github_actions_token()}"},
      {"Content-Type", "application/json; charset=utf-8"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end

  defp handle_dispatch({:ok, %Req.Response{status: status}}, workflow_id, ref)
       when status in 200..299 do
    {:ok, %{workflow_id: workflow_id, workflow_ref: ref}}
  end

  defp handle_dispatch({:ok, %Req.Response{status: status, body: body}}, _workflow_id, _ref) do
    {:error, {:github_status, status, body}}
  end

  defp handle_dispatch({:error, reason}, _workflow_id, _ref) do
    {:error, {:github_error, reason}}
  end
end
