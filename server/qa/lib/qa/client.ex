defmodule QA.Client do
  @moduledoc """
  Client module for communicating with the QA server.
  """

  alias QA.LogStreamer

  def create_step(%{
        summary: summary,
        description: description,
        issues: issues,
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    step_url = qa_run_url(server_url, account_handle, project_handle, run_id, "/steps")

    qa_server_request(:post, step_url, auth_token, json: %{summary: summary, description: description, issues: issues})
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
        summary: summary,
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    run_url = qa_run_url(server_url, account_handle, project_handle, run_id)

    qa_server_request(:patch, run_url, auth_token, json: %{status: "completed", summary: summary})
  end

  def screenshot_upload(%{
        file_name: file_name,
        title: title,
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    upload_url = qa_run_url(server_url, account_handle, project_handle, run_id, "/screenshots/upload")

    case qa_server_request(:post, upload_url, auth_token, json: %{file_name: file_name, title: title}) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_screenshot(%{
        file_name: file_name,
        title: title,
        server_url: server_url,
        run_id: run_id,
        auth_token: auth_token,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    screenshot_url = qa_run_url(server_url, account_handle, project_handle, run_id, "/screenshots")

    qa_server_request(:post, screenshot_url, auth_token, json: %{file_name: file_name, title: title})
  end

  def start_log_stream(%{server_url: server_url, run_id: run_id, auth_token: auth_token}) do
    LogStreamer.start_link(%{
      server_url: server_url,
      run_id: run_id,
      auth_token: auth_token
    })
  end

  def stream_log(streamer_pid, %{message: message, level: level, timestamp: timestamp}) do
    LogStreamer.stream_log(streamer_pid, %{
      message: message,
      level: level,
      timestamp: timestamp
    })
  end

  defp qa_run_url(server_url, account_handle, project_handle, run_id, path \\ "") do
    "#{server_url}/api/projects/#{account_handle}/#{project_handle}/qa/runs/#{run_id}#{path}"
  end

  defp qa_server_request(method, url, auth_token, params) do
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

  defp handle_qa_server_response({:ok, %{status: status, body: body}}) when status == 200 do
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
