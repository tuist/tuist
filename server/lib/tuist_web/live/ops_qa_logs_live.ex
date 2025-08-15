defmodule TuistWeb.OpsQALogsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.QA
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def mount(%{"qa_run_id" => qa_run_id}, _session, socket) do
    case QA.qa_run_for_ops(qa_run_id) do
      nil ->
        raise NotFoundError, gettext("QA run not found")

      qa_run ->
        logs = QA.logs_for_run(qa_run_id)

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:logs, logs)
         |> assign(:expanded_tools, MapSet.new())
         |> assign(:head_title, "#{gettext("QA Logs")} · #{qa_run.project_name} · Tuist")}
    end
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

  defp map_qa_status_to_badge_status("failed"), do: "error"
  defp map_qa_status_to_badge_status("completed"), do: "success"
  defp map_qa_status_to_badge_status("running"), do: "attention"
  defp map_qa_status_to_badge_status("pending"), do: "warning"
  defp map_qa_status_to_badge_status(_), do: "disabled"

  defp log_type_short(log) do
    case log.type do
      :usage -> "TOKENS"
      :tool_call -> "TOOL"
      :tool_call_result -> "RESULT"
      :message -> "ASSISTANT"
    end
  end

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
    case JSON.decode!(log.data) do
      %{"name" => "screenshot", "content" => content} when is_list(content) ->
        Enum.any?(content, fn
          %{"type" => "image", "content" => _} -> true
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp get_screenshot_data(log) do
    case JSON.decode!(log.data) do
      %{"name" => "screenshot", "content" => content} when is_list(content) ->
        content
        |> Enum.find(fn
          %{"type" => "image", "content" => _} -> true
          _ -> false
        end)
        |> case do
          %{"content" => base64_data} -> base64_data
          _ -> ""
        end

      _ ->
        ""
    end
  end
end
