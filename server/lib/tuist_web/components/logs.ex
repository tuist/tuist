defmodule TuistWeb.Components.Logs do
  @moduledoc """
  A LiveComponent for displaying log entries with expandable content.
  The component manages its own expanded state internally.

  ## Usage

      <.live_component
        module={TuistWeb.Components.Logs}
        logs={@logs}
        empty_message="No logs found"
        id="ops-qa-logs"
      />

  ## Log Entry Format

  Each log entry should be a map with:
  - `type` (string) - The log type for styling
  - `message` (string) - The formatted log message
  - `timestamp` (string) - The formatted timestamp
  - `context` (optional) - Additional content to show when expanded
  - `image` (optional) - Image URL to display when expanded

  ## Attributes

  - `id` - DOM ID for the logs container
  - `logs` - List of pre-formatted log entries
  - `empty_message` - Message to show when no logs are present
  """

  use TuistWeb, :live_component
  use Noora

  alias Tuist.Markdown

  @impl true
  def mount(socket) do
    {:ok, assign(socket, expanded_tools: MapSet.new())}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:empty_message, assigns[:empty_message] || "No logs found")}
  end

  @impl true
  def handle_event("toggle_log_expansion", %{"log-id" => log_id}, socket) do
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
    <div id={@id} class="noora-logs">
      <.card title="Logs" icon="file">
        <.card_section>
          <div :if={Enum.empty?(@logs)} data-part="empty-logs">
            <span>{@empty_message}</span>
          </div>
          <div :if={!Enum.empty?(@logs)} data-part="logs-container">
            <div :for={log <- @logs} data-part="log-entry">
              <span data-part="timestamp">{log.timestamp}</span>
              <span data-part="log-type" data-type={String.downcase(log.type)}>
                {log.type}
              </span>
              <.render_log_content log={log} expanded_tools={@expanded_tools} myself={@myself} />
            </div>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :log, :map, required: true
  attr :expanded_tools, :any, required: true
  attr :myself, :any, required: true

  defp render_log_content(%{log: log} = assigns) do
    has_context = Map.has_key?(log, :context) && log.context != nil
    has_image = Map.has_key?(log, :image) && log.image != nil
    is_expandable = has_context || has_image

    if is_expandable do
      ~H"""
      <div data-part="expandable-content">
        <div data-part="content-header">
          <button
            type="button"
            data-part="expand-toggle"
            phx-click="toggle_log_expansion"
            phx-target={@myself}
            phx-value-log-id={log_id(@log)}
          >
            <span class="expand-icon">
              {if expanded?(@log, @expanded_tools), do: "−", else: "+"}
            </span>
          </button>
          <span data-part="content">{raw(Markdown.to_html(@log.message))}</span>
        </div>
        <div :if={expanded?(@log, @expanded_tools)} data-part="expanded-details">
          <div :if={Map.get(@log, :image)} data-part="image-content">
            <img src={@log.image} alt="Log image" />
          </div>
          <div :if={Map.get(@log, :context)} data-part="context-content">
            <pre>{@log.context.json_data}</pre>
          </div>
        </div>
      </div>
      """
    else
      ~H"""
      <span data-part="log-message">{raw(Markdown.to_html(@log.message))}</span>
      """
    end
  end

  defp log_id(log) do
    data_hash = :md5 |> :crypto.hash(to_string(log.timestamp) <> log.type <> log.message) |> Base.encode16(case: :lower)
    "#{log.timestamp}_#{log.type}_#{String.slice(data_hash, 0, 8)}"
  end

  defp expanded?(log, expanded_tools) do
    MapSet.member?(expanded_tools, log_id(log))
  end
end
