defmodule TuistWeb.Components.Logs do
  @moduledoc """
  A generic logs component for displaying log entries with expandable content.

  ## Usage

      <.logs
        logs={@logs}
        expanded_tools={@expanded_tools}
        empty_message="No logs found"
        id="ops-qa-logs"
      />

  ## Log Entry Format

  Each log entry should be a map with:
  - `type` (string) - The log type for styling
  - `message` (string) - The formatted log message
  - `timestamp` (string) - The formatted timestamp
  - `context` (optional) - Additional content to show when expanded

  ## Attributes

  - `logs` - List of pre-formatted log entries
  - `expanded_tools` - MapSet of expanded log IDs
  - `empty_message` - Message to show when no logs are present
  - `id` - DOM ID for the logs container
  """

  use Phoenix.Component
  use TuistWeb, :verified_routes
  use Noora

  attr :logs, :list, required: true
  attr :expanded_tools, :any, default: MapSet.new()
  attr :empty_message, :string, default: "No logs found"
  attr :id, :string, default: "logs"

  def logs(assigns) do
    ~H"""
    <div id={@id}>
      <.card title="Logs" icon="file">
        <.card_section>
          <div :if={Enum.empty?(@logs)} data-part="empty-logs">
            <span>{@empty_message}</span>
          </div>
          <div :if={!Enum.empty?(@logs)} data-part="logs-container">
            <div :for={log <- @logs} data-part="log-entry" data-type={log.type}>
              <span data-part="timestamp">{log.timestamp}</span>
              <span data-part="log-type" data-type={log.type}>
                {log.type}
              </span>
              <.render_log_content
                log={log}
                expanded_tools={@expanded_tools}
              />
            </div>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :log, :map, required: true
  attr :expanded_tools, :any, required: true

  defp render_log_content(%{log: log} = assigns) do
    is_expandable = Map.has_key?(log, :context) && log.context != nil

    if is_expandable do
      ~H"""
      <div data-part="expandable-content">
        <div data-part="content-header">
          <button
            type="button"
            data-part="expand-toggle"
            phx-click="toggle_log_expansion"
            phx-value-log-id={log_id(@log)}
          >
            <span class="expand-icon">
              {if expanded?(@log, @expanded_tools), do: "−", else: "+"}
            </span>
          </button>
          <span data-part="content">{@log.message}</span>
        </div>
        <div :if={expanded?(@log, @expanded_tools)} data-part="expanded-details">
          <div :if={@log.context.screenshot_metadata && @log.context.screenshot_metadata.screenshot_id} data-part="screenshot-content">
            <img
              src={
                ~p"/#{@log.context.screenshot_metadata.account_handle}/#{@log.context.screenshot_metadata.project_handle}/qa/runs/#{@log.context.screenshot_metadata.qa_run_id}/screenshots/#{@log.context.screenshot_metadata.screenshot_id}"
              }
              alt="Screenshot"
              style="max-width: 100%; max-height: 400px; height: auto; border-radius: 6px; margin-bottom: 12px;"
            />
          </div>
          <div :if={@log.context.screenshot_metadata && !@log.context.screenshot_metadata.screenshot_id} data-part="screenshot-content">
            <p style="color: #666; font-style: italic;">
              Screenshot captured (metadata unavailable)
            </p>
          </div>
          <div data-part="json-content">
            {@log.context.json_data}
          </div>
        </div>
      </div>
      """
    else
      ~H"""
      <div data-part="log-message" data-type={@log.type}>
        {@log.message}
      </div>
      """
    end
  end

  # Helper functions that can be used by consumers
  def log_id(log) do
    data_hash = :md5 |> :crypto.hash(to_string(log.timestamp) <> log.type <> log.message) |> Base.encode16(case: :lower)
    "#{log.timestamp}_#{log.type}_#{String.slice(data_hash, 0, 8)}"
  end

  def expanded?(log, expanded_tools) do
    MapSet.member?(expanded_tools, log_id(log))
  end
end