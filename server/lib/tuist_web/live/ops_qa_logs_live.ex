defmodule TuistWeb.OpsQALogsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.QA
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def handle_params(%{"qa_run_id" => qa_run_id}, _uri, socket) do
    case QA.qa_run_for_ops(qa_run_id) do
      nil ->
        raise NotFoundError, gettext("QA run not found")

      qa_run ->
        logs = QA.logs_for_run(qa_run_id)
        screenshots = QA.screenshots_for_run(qa_run_id)

        if connected?(socket) do
          Tuist.PubSub.subscribe("qa_logs:#{qa_run_id}")
        end

        {:noreply,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:logs, logs)
         |> assign(:screenshots, screenshots)
         |> assign(:expanded_tools, MapSet.new())
         |> assign(:head_title, "#{gettext("QA Logs")} · #{qa_run.project_name} · Tuist")}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_tool_details", %{"log-id" => log_id}, socket) do
    expanded_tools = socket.assigns.expanded_tools

    new_expanded_tools =
      if MapSet.member?(expanded_tools, log_id) do
        MapSet.delete(expanded_tools, log_id)
      else
        MapSet.put(expanded_tools, log_id)
      end

    {:noreply, assign(socket, :expanded_tools, new_expanded_tools)}
  end

  @impl true
  def handle_info({:qa_log_created, log}, socket) do
    current_logs = socket.assigns.logs
    updated_logs = current_logs ++ [log]

    # Refresh screenshots if this is a screenshot log
    updated_screenshots = if log.type == :screenshot do
      QA.screenshots_for_run(socket.assigns.qa_run.id)
    else
      socket.assigns.screenshots
    end

    {:noreply,
     socket
     |> assign(:logs, updated_logs)
     |> assign(:screenshots, updated_screenshots)}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp map_qa_status_to_badge_status("failed"), do: "error"
  defp map_qa_status_to_badge_status("completed"), do: "success"
  defp map_qa_status_to_badge_status("running"), do: "attention"
  defp map_qa_status_to_badge_status("pending"), do: "warning"
  defp map_qa_status_to_badge_status(_), do: "disabled"

  defp log_type_short(log_type) when is_atom(log_type) do
    case log_type do
      :usage -> "TOKENS"
      :tool_call -> "TOOL"
      :tool_call_result -> "RESULT"
      :message -> "ASSISTANT"
      :screenshot -> "SCREENSHOT"
    end
  end

  defp log_type_short(log_type) when is_binary(log_type), do: log_type_short(String.to_existing_atom(log_type))

  defp format_log_message(log) do
    case JSON.decode!(log.data) do
      %{"message" => message} -> message
      %{"type" => "call", "name" => name} -> name
      %{"type" => "result", "name" => name} -> name
      %{"arguments" => _, "name" => name} -> name
      %{"name" => name} -> name
      %{"input" => input, "output" => output} -> "#{input}/#{output}"
      data -> inspect(data)
    end
  end

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_datetime(_), do: "Unknown"

  defp format_log_timestamp_short(%NaiveDateTime{} = ndt) do
    time = NaiveDateTime.to_time(ndt)

    "#{String.pad_leading(to_string(time.hour), 2, "0")}:#{String.pad_leading(to_string(time.minute), 2, "0")}:#{String.pad_leading(to_string(time.second), 2, "0")}"
  end

  defp format_log_timestamp_short(_), do: "??:??:??"

  defp log_id(log) do
    data_hash = :md5 |> :crypto.hash(log.data) |> Base.encode16(case: :lower)
    "#{log.timestamp}_#{log.type}_#{String.slice(data_hash, 0, 8)}"
  end

  defp expanded?(log, expanded_tools) do
    MapSet.member?(expanded_tools, log_id(log))
  end

  defp prettify_json(data) when is_binary(data) do
    case JSON.decode!(data) do
      %{"name" => "describe_ui", "content" => [%{"content" => nested_json, "type" => "text"}]} =
          decoded ->
        ui_data = JSON.decode!(nested_json)
        Jason.encode!(%{decoded | "content" => ui_data}, pretty: true)

      [%{"content" => nested_json, "type" => "text"}] ->
        nested_json
        |> JSON.decode!()
        |> Jason.encode!(pretty: true)

      decoded ->
        Jason.encode!(decoded, pretty: true)
    end
  end

  defp prettify_json(data), do: inspect(data)

  defp has_screenshot?(log) do
    log.type == :screenshot
  end

  defp get_screenshot_data(log, screenshots) do
    case JSON.decode!(log.data) do
      %{"name" => "screenshot", "content" => content} when is_list(content) ->
        # Find the first screenshot reference and return the corresponding screenshot record
        Enum.find(content, fn item ->
          match?(%{"type" => "image", "content" => "s3_reference"}, item)
        end)
        |> case do
          %{"type" => "image", "content" => "s3_reference", "timestamp" => timestamp} ->
            # Find the matching screenshot by timestamp
            Enum.find(screenshots, fn screenshot ->
              # Compare timestamps (simplified - in practice you might want more sophisticated matching)
              DateTime.to_iso8601(screenshot.inserted_at) == timestamp
            end)
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
