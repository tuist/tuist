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

    body =
      %{action: action, issues: issues}
      |> then(&if(result = Map.get(params, :result), do: Map.put(&1, :result, result), else: &1))
      |> then(
        &if(started_at = Map.get(params, :started_at),
          do: Map.put(&1, :started_at, DateTime.to_iso8601(started_at)),
          else: &1
        )
      )

    case qa_server_request(:post, step_url, auth_token, json: body) do
      {:ok, %{"id" => step_id}} -> {:ok, step_id}
      {:ok, response} -> {:ok, response}
      :ok -> :ok
      error -> error
    end
  end

  def start_update_step(%{
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

  defp start_recording_upload(
         %{
           server_url: server_url,
           run_id: run_id,
           auth_token: auth_token,
           account_handle: account_handle,
           project_handle: project_handle
         } = _params
       ) do
    upload_url =
      qa_run_url(server_url, account_handle, project_handle, run_id, "/recordings/upload/start")

    qa_server_request(:post, upload_url, auth_token, json: %{})
  end

  defp generate_recording_upload_url(
         %{
           server_url: server_url,
           run_id: run_id,
           auth_token: auth_token,
           account_handle: account_handle,
           project_handle: project_handle,
           upload_id: upload_id,
           storage_key: storage_key,
           part_number: part_number
         } = params
       ) do
    generate_url =
      qa_run_url(
        server_url,
        account_handle,
        project_handle,
        run_id,
        "/recordings/upload/generate-url"
      )

    content_length = Map.get(params, :content_length)

    json_body = %{
      upload_id: upload_id,
      storage_key: storage_key,
      part_number: part_number
    }

    json_body =
      if content_length do
        Map.put(json_body, :content_length, content_length)
      else
        json_body
      end

    qa_server_request(:post, generate_url, auth_token, json: json_body)
  end

  defp complete_recording_upload(
         %{
           server_url: server_url,
           run_id: run_id,
           auth_token: auth_token,
           account_handle: account_handle,
           project_handle: project_handle,
           upload_id: upload_id,
           storage_key: storage_key,
           parts: parts,
           started_at: started_at,
           duration: duration
         } = _params
       ) do
    complete_url =
      qa_run_url(
        server_url,
        account_handle,
        project_handle,
        run_id,
        "/recordings/upload/complete"
      )

    json_body = %{
      upload_id: upload_id,
      storage_key: storage_key,
      parts: parts,
      started_at: DateTime.to_iso8601(started_at),
      duration: duration
    }

    qa_server_request(:post, complete_url, auth_token, json: json_body)
  end

  def upload_recording(
        %{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          recording_path: recording_path
        } = params
      ) do
    chunk_size = 5 * 1024 * 1024

    with {:ok, %{"upload_id" => upload_id, "storage_key" => storage_key}} <-
           start_recording_upload(%{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle
           }),
         {:ok, parts} <-
           upload_recording_parts(recording_path, chunk_size, %{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             upload_id: upload_id,
             storage_key: storage_key
           }),
         {:ok, _} <-
           complete_recording_upload(%{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             upload_id: upload_id,
             storage_key: storage_key,
             parts: parts,
             started_at: Map.get(params, :started_at),
             duration: Map.get(params, :duration_ms)
           }) do
      {:ok, %{upload_id: upload_id, storage_key: storage_key}}
    end
  end

  defp upload_recording_parts(file_path, chunk_size, upload_params) do
    file_stream = File.stream!(file_path, chunk_size, [])

    parts =
      file_stream
      |> Stream.with_index(1)
      |> Enum.map(fn {chunk, part_number} ->
        with {:ok, %{"url" => upload_url}} <-
               generate_recording_upload_url(
                 Map.merge(upload_params, %{
                   part_number: part_number,
                   content_length: byte_size(chunk)
                 })
               ),
             {:ok, response} <-
               Req.put(upload_url, body: chunk, headers: [{"Content-Type", "video/mp4"}]) do
          etag = etag_from_response(response)
          %{part_number: part_number, etag: etag}
        else
          error -> {:error, "Failed to upload part #{part_number}: #{inspect(error)}"}
        end
      end)

    {:ok, parts}
  end

  defp etag_from_response(%{headers: headers}) do
    {_key, [etag | _]} =
      Enum.find(headers, fn {key, _value} -> String.downcase(key) == "etag" end)

    String.trim(etag, "\"")
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
