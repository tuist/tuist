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
        logs_with_metadata = prepare_logs_with_metadata(logs)

        if connected?(socket) do
          Tuist.PubSub.subscribe("qa_logs:#{qa_run_id}")
        end

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:logs, logs_with_metadata)
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

  @impl true
  def handle_info({:qa_log_created, log}, socket) do
    current_logs = socket.assigns.logs
    processed_log = prepare_log_with_metadata(log)
    updated_logs = current_logs ++ [processed_log]

    {:noreply, assign(socket, :logs, updated_logs)}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp map_qa_status_to_badge_status("failed"), do: "error"
  defp map_qa_status_to_badge_status("completed"), do: "success"
  defp map_qa_status_to_badge_status("running"), do: "attention"
  defp map_qa_status_to_badge_status("pending"), do: "warning"
  defp map_qa_status_to_badge_status(_), do: "disabled"

  defp to_atom(type) when is_binary(type), do: String.to_existing_atom(type)
  defp to_atom(type) when is_atom(type), do: type

  defp log_type_short(log_type) do
    case to_atom(log_type) do
      :usage -> "TOKENS"
      :tool_call -> "TOOL"
      :tool_call_result -> "RESULT"
      :message -> "ASSISTANT"
    end
  end

  defp is_tool_log?(log), do: to_atom(log.type) in [:tool_call, :tool_call_result]
  defp is_tool_result_log?(log), do: to_atom(log.type) == :tool_call_result

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
    case JSON.decode(data) do
      {:ok, %{"name" => "describe_ui", "content" => [%{"content" => nested_content, "type" => "text"}]} = decoded} ->
        handle_describe_ui_content(decoded, nested_content)

      {:ok, [%{"content" => nested_json, "type" => "text"}]} ->
        case JSON.decode(nested_json) do
          {:ok, parsed_data} ->
            Jason.encode!(parsed_data, pretty: true)

          {:error, _} ->
            nested_json
        end

      {:ok, decoded} ->
        Jason.encode!(decoded, pretty: true)

      {:error, _} ->
        data
    end
  end

  defp handle_describe_ui_content(decoded, nested_content) do
    case JSON.decode(nested_content) do
      {:ok, ui_data} ->
        Jason.encode!(%{decoded | "content" => ui_data}, pretty: true)

      {:error, _} ->
        Jason.encode!(decoded, pretty: true)
    end
  end

  @action_tools ["tap", "swipe", "long_press", "type_text", "key_press", "button", "touch", "gesture", "plan_report"]

  defp has_screenshot?(log) do
    case JSON.decode(log.data) do
      {:ok, data} ->
        case data do
          %{"name" => "screenshot"} -> true
          %{"name" => name, "content" => content} when name in @action_tools -> has_screenshot_in_content?(content)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp has_screenshot_in_content?(content) when is_list(content) do
    Enum.any?(content, &has_screenshot_in_text_content?/1)
  end

  defp has_screenshot_in_content?(_), do: false

  defp has_screenshot_in_text_content?(%{"type" => "text", "content" => text_content}) do
    case JSON.decode(text_content) do
      {:ok, nested_data} -> Map.has_key?(nested_data, "screenshot_id")
      _ -> false
    end
  end

  defp has_screenshot_in_text_content?(_), do: false

  defp get_screenshot_metadata(log) do
    case JSON.decode(log.data) do
      {:ok, data} ->
        case data do
          %{"name" => "screenshot", "content" => content} ->
            extract_screenshot_metadata_from_standalone(content)

          %{"name" => name, "content" => content} when name in @action_tools ->
            extract_screenshot_metadata(content)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp extract_screenshot_metadata_from_standalone(content) when is_list(content) do
    # For standalone screenshot tool - look for ContentPart with text containing metadata JSON
    Enum.find_value(content, fn
      %{"type" => "text", "content" => text_content} ->
        with {:ok, nested_data} <- JSON.decode(text_content),
             %{
               "screenshot_id" => screenshot_id,
               "qa_run_id" => qa_run_id,
               "account_handle" => account_handle,
               "project_handle" => project_handle
             } <- nested_data do
          %{
            screenshot_id: screenshot_id,
            qa_run_id: qa_run_id,
            account_handle: account_handle,
            project_handle: project_handle
          }
        else
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp extract_screenshot_metadata_from_standalone(_), do: nil

  defp extract_screenshot_metadata(content) when is_list(content) do
    Enum.find_value(content, &extract_from_text_content/1)
  end

  defp extract_screenshot_metadata(_), do: nil

  defp extract_from_text_content(%{"type" => "text", "content" => text_content}) do
    with {:ok, nested_data} <- JSON.decode(text_content),
         %{
           "screenshot_id" => screenshot_id,
           "qa_run_id" => qa_run_id,
           "account_handle" => account_handle,
           "project_handle" => project_handle
         } <- nested_data do
      %{
        screenshot_id: screenshot_id,
        qa_run_id: qa_run_id,
        account_handle: account_handle,
        project_handle: project_handle
      }
    else
      _ -> nil
    end
  end

  defp extract_from_text_content(_), do: nil

  defp prepare_logs_with_metadata(logs) do
    Enum.map(logs, &prepare_log_with_metadata/1)
  end

  defp prepare_log_with_metadata(log) do
    screenshot_metadata = if has_screenshot?(log), do: get_screenshot_metadata(log)
    Map.put(log, :screenshot_metadata, screenshot_metadata)
  end
end
