defmodule Runner.QA.Client do
  @moduledoc """
  Client module for communicating with the QA server.
  """

  alias Runner.QA.LogStreamer

  require Logger

  def create_step(
        %{
          action: action,
          issues: issues,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        } = params
      ) do
    step_url = qa_run_url(server_url, account_handle, project_handle, run_id, "/steps")

    body = %{action: action, issues: issues}
    body = if result = Map.get(params, :result), do: Map.put(body, :result, result), else: body

    case qa_server_request(:post, step_url, auth_token, json: body) do
      {:ok, %{"id" => step_id}} -> {:ok, step_id}
      {:ok, response} -> {:ok, response}
      :ok -> :ok
      error -> error
    end
  end

  def update_step(%{
        step_id: step_id,
        result: result,
        issues: issues,
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    step_url = qa_run_url(server_url, account_handle, project_handle, run_id, "/steps/#{step_id}")

    Task.start(fn ->
      case qa_server_request(:patch, step_url, auth_token, json: %{result: result, issues: issues}) do
        {:ok, _} ->
          Logger.debug("Successfully updated step #{step_id}")

        {:error, reason} ->
          Logger.error("Failed to update step #{step_id}: #{inspect(reason)}")
      end
    end)

    {:ok, :async}
  end

  def start_run(%{
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    run_url = qa_run_url(server_url, account_handle, project_handle, run_id)

    qa_server_request(:patch, run_url, auth_token, json: %{status: "running"})
  end

  def finalize_run(%{
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    run_url = qa_run_url(server_url, account_handle, project_handle, run_id)

    qa_server_request(:patch, run_url, auth_token, json: %{status: "completed"})
  end

  def fail_run(%{
        error_message: error_message,
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    run_url = qa_run_url(server_url, account_handle, project_handle, run_id)

    qa_server_request(:patch, run_url, auth_token, json: %{status: "failed", error_message: error_message})
  end

  def screenshot_upload(%{
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle,
        screenshot_id: screenshot_id
      }) do
    upload_url =
      qa_run_url(
        server_url,
        account_handle,
        project_handle,
        run_id,
        "/screenshots/#{screenshot_id}/upload"
      )

    case qa_server_request(:post, upload_url, auth_token) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_screenshot(
        %{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          step_id: step_id
        } = _params
      ) do
    screenshot_url =
      qa_run_url(server_url, account_handle, project_handle, run_id, "/screenshots")

    qa_server_request(:post, screenshot_url, auth_token, json: %{step_id: step_id})
  end

  def start_log_stream(%{server_url: server_url, run_id: run_id, auth_token: auth_token}) do
    LogStreamer.start_link(%{
      server_url: server_url,
      run_id: run_id,
      auth_token: auth_token
    })
  end

  def stream_log(streamer_pid, %{data: data, type: type, timestamp: timestamp}) do
    LogStreamer.stream_log(streamer_pid, %{
      data: data,
      type: type,
      timestamp: timestamp
    })
  end

  defp qa_run_url(server_url, account_handle, project_handle, run_id, path \\ "") do
    "#{server_url}/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{run_id}#{path}"
  end

  defp qa_server_request(method, url, auth_token, params \\ []) do
    opts =
      [
        url: url,
        headers: %{"Authorization" => "Bearer #{auth_token}"}
      ] ++ params

    case_result =
      case method do
        :post -> Req.post(opts)
        :patch -> Req.patch(opts)
      end

    handle_qa_server_response(case_result)
  end

  defp handle_qa_server_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_qa_server_response({:ok, %{status: status}}) when status in 200..299 do
    :ok
  end

  defp handle_qa_server_response({:ok, %{status: status}}) do
    {:error, "Server returned unexpected status #{status}"}
  end

  defp handle_qa_server_response({:error, error}) do
    {:error, error}
  end
end
