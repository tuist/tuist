defmodule TuistOps.Previews.GitHubActionsClient do
  @moduledoc """
  Minimal GitHub Actions workflow-dispatch client for previews.
  """

  alias TuistOps.Environment

  def dispatch(action, inputs) when action in ["deploy", "delete"] and is_map(inputs) do
    repo = Environment.github_repository()
    workflow_id = Environment.preview_workflow_id()
    ref = Environment.github_workflow_ref()
    inputs = Map.put(inputs, :action, action)
    run_name = workflow_run_name(action, inputs)

    url = "https://api.github.com/repos/#{repo}/actions/workflows/#{workflow_id}/dispatches"

    body = %{
      ref: ref,
      inputs: inputs
    }

    url
    |> Req.post(headers: headers(), body: JSON.encode!(body))
    |> handle_dispatch(workflow_id, ref, run_name)
  end

  def workflow_run_name(action, inputs) when action in ["deploy", "delete"] and is_map(inputs) do
    identifier =
      Map.get(inputs, :slug) ||
        Map.get(inputs, "slug") ||
        Map.get(inputs, :pr_number) ||
        Map.get(inputs, "pr_number") ||
        Map.get(inputs, :commit_sha) ||
        Map.get(inputs, "commit_sha")

    preview_id = Map.get(inputs, :preview_id) || Map.get(inputs, "preview_id")

    ["Preview", action, identifier, preview_id && "##{preview_id}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def workflow_run(run_name) when is_binary(run_name) do
    repo = Environment.github_repository()
    workflow_id = Environment.preview_workflow_id()
    url = "https://api.github.com/repos/#{repo}/actions/workflows/#{workflow_id}/runs"

    url
    |> Req.get(headers: headers(), params: [event: "workflow_dispatch", per_page: 50])
    |> handle_workflow_run(run_name)
  end

  defp headers do
    [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{Environment.github_actions_token()}"},
      {"Content-Type", "application/json; charset=utf-8"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end

  defp handle_dispatch({:ok, %Req.Response{status: status}}, workflow_id, ref, run_name)
       when status in 200..299 do
    {:ok, %{workflow_id: workflow_id, workflow_ref: ref, run_name: run_name}}
  end

  defp handle_dispatch(
         {:ok, %Req.Response{status: status, body: body}},
         _workflow_id,
         _ref,
         _run_name
       ) do
    {:error, {:github_status, status, body}}
  end

  defp handle_dispatch({:error, reason}, _workflow_id, _ref, _run_name) do
    {:error, {:github_error, reason}}
  end

  defp handle_workflow_run({:ok, %Req.Response{status: status, body: body}}, run_name)
       when status in 200..299 do
    run =
      body
      |> Map.get("workflow_runs", [])
      |> Enum.find(&(Map.get(&1, "display_title") == run_name))

    case run do
      nil ->
        {:error, :not_found}

      run ->
        {:ok,
         %{
           id: run["id"],
           status: run["status"],
           conclusion: run["conclusion"],
           html_url: run["html_url"]
         }}
    end
  end

  defp handle_workflow_run({:ok, %Req.Response{status: status, body: body}}, _run_name) do
    {:error, {:github_status, status, body}}
  end

  defp handle_workflow_run({:error, reason}, _run_name) do
    {:error, {:github_error, reason}}
  end
end
