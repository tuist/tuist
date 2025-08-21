defmodule TuistWeb.QALogChannel do
  @moduledoc false
  use TuistWeb, :channel

  alias Tuist.Authorization
  alias Tuist.Billing
  alias Tuist.QA
  alias Tuist.QA.Log
  alias Tuist.QA.Logs.Buffer
  alias Tuist.Storage

  require Logger

  def join("qa_logs:" <> qa_run_id, _payload, socket) do
    case authorize_qa_run(socket, qa_run_id) do
      {:ok, qa_run} ->
        socket = assign(socket, :qa_run, qa_run)
        {:ok, socket}

      {:error, _reason} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("log", %{"data" => data, "type" => type, "timestamp" => timestamp}, socket) do
    qa_run = socket.assigns.qa_run
    project_id = qa_run.app_build.preview.project.id

    log_message = "[QA:#{qa_run.id}] #{inspect(data)}"
    log_metadata = [qa_run_id: qa_run.id, type: type, timestamp: timestamp]
    Logger.info(log_message, log_metadata)

    case type do
      "usage" ->
        usage_data = JSON.decode!(data)
        handle_token_usage_log(qa_run, usage_data, timestamp)

      "tool_call" ->
        :ok

      "tool_call_result" ->
        :ok

      "message" ->
        :ok

      "screenshot" ->
        handle_screenshot_log(qa_run, data, timestamp)
    end

    # Modify data for ClickHouse storage - replace full PNG with reference
    processed_data = process_log_data_for_storage(data, type, qa_run.id, timestamp)

    persist_log_to_clickhouse(project_id, qa_run.id, processed_data, type, timestamp)
    {:reply, :ok, socket}
  end

  defp authorize_qa_run(socket, qa_run_id) do
    with {:ok, subject} <- extract_subject_from_socket(socket),
         {:ok, qa_run} <-
           QA.qa_run(qa_run_id, preload: [app_build: [preview: [project: :account]]]),
         :ok <- authorize_subject_for_qa_run(subject, qa_run) do
      {:ok, qa_run}
    end
  end

  defp extract_subject_from_socket(socket) do
    case socket.assigns[:current_subject] do
      nil -> {:error, :unauthenticated}
      subject -> {:ok, subject}
    end
  end

  defp authorize_subject_for_qa_run(subject, qa_run) do
    project = qa_run.app_build.preview.project

    if Authorization.can?(:project_qa_run_update, subject, project) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp persist_log_to_clickhouse(project_id, qa_run_id, data, type, timestamp) do
    parsed_timestamp = parse_timestamp(timestamp)

    log_attrs = %{
      project_id: project_id,
      qa_run_id: qa_run_id,
      data: data,
      type: type,
      timestamp: parsed_timestamp,
      inserted_at: DateTime.utc_now()
    }

    log = struct(Log, log_attrs)

    Buffer.insert(log)

    Tuist.PubSub.broadcast(
      log,
      "qa_logs:#{qa_run_id}",
      :qa_log_created
    )
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      {:error, _reason} -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  defp handle_token_usage_log(qa_run, usage_data, timestamp) do
    parsed_timestamp = parse_timestamp(timestamp)

    attrs = %{
      input_tokens: usage_data["input"],
      output_tokens: usage_data["output"],
      model: usage_data["model"],
      feature: "qa",
      feature_resource_id: qa_run.id,
      account_id: qa_run.app_build.preview.project.account.id,
      timestamp: parsed_timestamp
    }

    case Billing.create_token_usage(attrs) do
      {:ok, _token_usage} ->
        Logger.info(
          "Token usage recorded for QA run #{qa_run.id}: #{usage_data["input"]} input, #{usage_data["output"]} output"
        )

      {:error, changeset} ->
        Logger.error("Failed to record token usage for QA run #{qa_run.id}: #{inspect(changeset.errors)}")

        Appsignal.send_error(%RuntimeError{message: "Failed to record token usage"}, %{
          qa_run_id: qa_run.id,
          changeset_errors: inspect(changeset.errors)
        })
    end
  end

  defp handle_screenshot_log(qa_run, data, timestamp) do
    case JSON.decode!(data) do
      %{"name" => "screenshot", "content" => content} when is_list(content) ->
        Enum.each(content, fn
          %{"type" => "image", "content" => base64_data} ->
            upload_screenshot_to_s3(qa_run, base64_data, timestamp)
          _ ->
            :ok
        end)

      _ ->
        :ok
    end
  end

  defp upload_screenshot_to_s3(qa_run, base64_data, _timestamp) do
    try do
      # Decode base64 data
      decoded_data = Base.decode64!(base64_data)

      # Generate unique filename
      timestamp_str = DateTime.to_iso8601(DateTime.utc_now(), :basic)
      filename = "qa_#{qa_run.id}_#{timestamp_str}.png"
      s3_key = "qa_screenshots/#{filename}"

      # Upload to S3
      case Tuist.Storage.upload(decoded_data, s3_key) do
        {:ok, _} ->
          # Generate S3 URL
          s3_url = Tuist.Storage.generate_upload_url(s3_key)

          # Create screenshot record
          attrs = %{
            qa_run_id: qa_run.id,
            file_name: filename,
            title: "QA Screenshot",
            s3_url: s3_url
          }

          case QA.create_qa_screenshot(attrs) do
            {:ok, screenshot} ->
              Logger.info("Screenshot uploaded and recorded for QA run #{qa_run.id}: #{filename}")
              {:ok, screenshot}

            {:error, changeset} ->
              Logger.error("Failed to create screenshot record for QA run #{qa_run.id}: #{inspect(changeset.errors)}")
              {:error, :database_error}
          end

        {:error, reason} ->
          Logger.error("Failed to upload screenshot to S3 for QA run #{qa_run.id}: #{inspect(reason)}")
          {:error, :upload_failed}
      end
    rescue
      e ->
        Logger.error("Error processing screenshot for QA run #{qa_run.id}: #{inspect(e)}")
        {:error, :processing_error}
    end
  end

  defp process_log_data_for_storage(data, type, qa_run_id, timestamp) do
    case type do
      "screenshot" ->
        case JSON.decode!(data) do
          %{"name" => "screenshot", "content" => content} when is_list(content) ->
            # Replace image content with a reference
            processed_content = Enum.map(content, fn
              %{"type" => "image", "content" => _base64_data} ->
                %{"type" => "image", "content" => "s3_reference", "qa_run_id" => qa_run_id, "timestamp" => timestamp}
              item ->
                item
            end)
            JSON.encode!(%{name: "screenshot", content: processed_content})

          _ ->
            data
        end

      _ ->
        data
    end
  end
end
