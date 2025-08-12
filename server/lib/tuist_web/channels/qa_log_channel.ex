defmodule TuistWeb.QALogChannel do
  @moduledoc false
  use TuistWeb, :channel

  alias Tuist.Authorization
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

  def handle_in("log", %{"message" => message, "level" => level, "timestamp" => timestamp}, socket) do
    qa_run = socket.assigns.qa_run
    project_id = qa_run.app_build.preview.project.id

    log_message = "[QA:#{qa_run.id}] #{message}"
    log_metadata = [qa_run_id: qa_run.id, level: level, timestamp: timestamp]

    case level do
      "debug" -> Logger.debug(log_message, log_metadata)
      "info" -> Logger.info(log_message, log_metadata)
      "warning" -> Logger.warning(log_message, log_metadata)
      "error" -> Logger.error(log_message, log_metadata)
      _ -> Logger.info(log_message, log_metadata)
    end

    persist_log_to_clickhouse(project_id, qa_run.id, message, level, timestamp)

    {:reply, :ok, socket}
  end

  defp authorize_qa_run(socket, qa_run_id) do
    with {:ok, subject} <- extract_subject_from_socket(socket),
         {:ok, qa_run} <- QA.qa_run(qa_run_id, preload: [app_build: [preview: :project]]),
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

  defp persist_log_to_clickhouse(project_id, qa_run_id, message, level, timestamp) do
    parsed_timestamp = parse_timestamp(timestamp)

    log_attrs = %{
      project_id: project_id,
      qa_run_id: qa_run_id,
      message: message,
      level: level,
      timestamp: parsed_timestamp,
      inserted_at: DateTime.utc_now()
    }

    log_attrs = Log.changeset(log_attrs)
    log = struct(Log, log_attrs)

    Buffer.insert(log)
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      {:error, _reason} -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()
end
