defmodule TuistWeb.QALogChannel do
  @moduledoc false
  use TuistWeb, :channel

  alias Tuist.Authorization
  alias Tuist.Billing
  alias Tuist.QA
  alias Tuist.QA.Log
  alias Tuist.QA.Logs.Buffer

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
    end

    persist_log_to_clickhouse(project_id, qa_run.id, data, type, timestamp)
    {:reply, :ok, socket}
  end

  def handle_info({:qa_log_created, _log}, socket) do
    {:noreply, socket}
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

    case Authorization.authorize(:qa_run_update, subject, project) do
      :ok -> :ok
      {:error, :forbidden} -> {:error, :unauthorized}
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
end
