defmodule TuistWeb.OpsQALogsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.QA

  @impl true
  def mount(%{"qa_run_id" => qa_run_id}, _session, socket) do
    case QA.qa_run_for_ops(qa_run_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("QA run not found"))
         |> push_navigate(to: ~p"/ops/qa")}

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

  @impl true
  def render(assigns) do
    ~H"""
    <div id="qa-logs">
      <div data-part="header">
        <div data-part="breadcrumb">
          <.link_button label={gettext("Back")} navigate={~p"/ops/qa"} variant="secondary">
            <:icon_left>
              <.arrow_left />
            </:icon_left>
          </.link_button>
        </div>

        <div data-part="title-section">
          <div data-part="meta">
            <span data-part="project">{@qa_run.account_name}/{@qa_run.project_name}</span>
            <.status_badge
              status={map_qa_status_to_badge_status(@qa_run.status)}
              label={String.capitalize(@qa_run.status)}
            />
            <span data-part="time">{format_datetime(@qa_run.inserted_at)}</span>
          </div>
        </div>
      </div>

      <div data-part="logs-section">
        <.card title={gettext("Logs")} icon="file">
          <.card_section>
            <%= if Enum.empty?(@logs) do %>
              <div data-part="empty-logs">
                <span>{gettext("No logs found for this QA run")}</span>
              </div>
            <% else %>
              <div data-part="logs-container">
                <div :for={log <- @logs} data-part="log-entry" data-type={log.type}>
                  <span data-part="timestamp">{format_log_timestamp_short(log.timestamp)}</span>
                  <span data-part="log-type" data-type={log.type}>
                    {log_type_short(log)}
                  </span>
                  <%= if log.type == :tool_call or log.type == :tool_call_result do %>
                    <div data-part="tool-call-content">
                      <div data-part="tool-call-header">
                        <button
                          type="button"
                          data-part="expand-toggle"
                          phx-click="toggle_tool_details"
                          phx-value-log-id={log_id(log)}
                        >
                          <span class="expand-icon">
                            {if expanded?(log, @expanded_tools), do: "−", else: "+"}
                          </span>
                        </button>
                        <span data-part="tool-name">{format_log_message(log)}</span>
                      </div>
                      <%= if expanded?(log, @expanded_tools) do %>
                        <div data-part="tool-call-details">
                          <%= if log.type == :tool_call_result and has_screenshot?(log) do %>
                            <div data-part="screenshot-content">
                              <img
                                src={"data:image/png;base64,#{get_screenshot_data(log)}"}
                                alt="Screenshot"
                                style="max-width: 100%; max-height: 400px; height: auto; border-radius: 6px; margin-bottom: 12px;"
                              />
                            </div>
                          <% else %>
                            <pre data-part="json-content">{prettify_json(log.data)}</pre>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div data-part="log-message" data-type={log.type}>{format_log_message(log)}</div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </.card_section>
        </.card>
      </div>
    </div>
    """
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
