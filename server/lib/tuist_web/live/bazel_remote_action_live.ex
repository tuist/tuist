defmodule TuistWeb.BazelRemoteActionLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.LiveView.JS
  alias Tuist.Bazel
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Actions
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  @tabs ~w(overview logs)
  # Rows the Logs tab shows first, from the end, and adds per "Load earlier".
  @log_rows 500
  # A command line longer than this starts collapsed to a few lines.
  @long_command_bytes 400
  # Outputs listed before "Show all".
  @shown_outputs 10
  @pending_refresh_ms 5_000

  def mount(%{"invocation_id" => invocation_id, "operation_id" => operation_id}, _session, socket) do
    %{selected_account: account, selected_project: project} = socket.assigns

    # A running invocation has no completed record yet, but its finished
    # actions do; records are scoped to the project either way.
    invocation_id =
      case Bazel.get_invocation(project.id, invocation_id) do
        {:ok, invocation} -> invocation.invocation_id
        {:error, :not_found} -> invocation_id
      end

    case Actions.get(project.id, invocation_id, operation_id) do
      {:ok, action} ->
        socket =
          socket
          |> assign(:invocation_id, invocation_id)
          |> assign(:pending, nil)
          |> assign(:action, action)
          |> assign(:status, status(action))
          |> assign(:command_line, Actions.command_line(action))
          |> assign(:shown_outputs, @shown_outputs)
          |> assign(:head_title, "#{title(action)} · #{dgettext("dashboard_builds", "Remote action")} · Tuist")
          |> assign(log_state(action, %{}))
          |> assign(:log_first_page, 0)
          |> stream(:log_rows, [])

        # Long streams' ends live in object storage; the preview shows until they load.
        socket =
          if connected?(socket) and (action.stdout_truncated or action.stderr_truncated) do
            start_async(socket, :stored_logs, fn -> log_state(action, Actions.stored_logs(account, project, action)) end)
          else
            socket
          end

        {:ok, socket}

      {:error, :not_found} ->
        mount_pending(socket, project, invocation_id, operation_id)
    end
  end

  # An action the scheduler still runs or queues has no record until it
  # finishes. Its page shows what the scheduler knows and loads the record
  # once the gateway has sent it.
  defp mount_pending(socket, project, invocation_id, operation_id) do
    case live_action(project, invocation_id, operation_id) do
      %{} = live ->
        if connected?(socket), do: Process.send_after(self(), :refresh_pending, @pending_refresh_ms)

        {:ok,
         socket
         |> assign(:invocation_id, invocation_id)
         |> assign(:operation_id, operation_id)
         |> assign(:pending, live)
         |> assign(:observed_at, DateTime.utc_now())
         |> assign(:head_title, "#{title(live)} · #{dgettext("dashboard_builds", "Remote action")} · Tuist")}

      nil ->
        raise NotFoundError, dgettext("dashboard_builds", "Remote action not found.")
    end
  end

  defp live_action(project, invocation_id, operation_id) do
    case RemoteExecution.activity(project) do
      {:ok, %{actions: actions}} -> Enum.find(actions, &(&1.id == operation_id and &1.invocation_id == invocation_id))
      {:error, :unavailable} -> nil
    end
  end

  def handle_info(:refresh_pending, socket) do
    %{selected_project: project, invocation_id: invocation_id, operation_id: operation_id} = socket.assigns

    {:noreply,
     start_async(socket, :refresh_pending, fn ->
       case Actions.get(project.id, invocation_id, operation_id) do
         {:ok, _action} -> :recorded
         {:error, :not_found} -> {:live, live_action(project, invocation_id, operation_id)}
       end
     end)}
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "overview"
    {:noreply, socket |> assign(:selected_tab, tab) |> show_log_end()}
  end

  def handle_async(:refresh_pending, {:ok, :recorded}, socket),
    do: {:noreply, push_navigate(socket, to: action_path(socket.assigns))}

  # Between leaving the scheduler and its record arriving, the action is finishing.
  def handle_async(:refresh_pending, result, socket) do
    Process.send_after(self(), :refresh_pending, @pending_refresh_ms)
    now = DateTime.utc_now()

    pending =
      case result do
        {:ok, {:live, %{} = live}} -> live
        {:ok, {:live, nil}} -> socket.assigns.pending |> Map.put(:state, "finishing") |> Map.put_new(:left_at, now)
        {:exit, _reason} -> socket.assigns.pending
      end

    {:noreply, socket |> assign(:pending, pending) |> assign(:observed_at, now)}
  end

  def handle_async(:stored_logs, {:ok, state}, socket), do: {:noreply, socket |> assign(state) |> show_log_end()}
  def handle_async(:stored_logs, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_event("load_earlier_log_lines", _params, socket) do
    {rows, first} = earlier_rows(socket.assigns.log_pages, socket.assigns.log_first_page)

    socket =
      rows
      |> Enum.reverse()
      |> Enum.reduce(socket, &stream_insert(&2, :log_rows, &1, at: 0))

    {:noreply, assign(socket, :log_first_page, first)}
  end

  # The errors, the end of stderr for failures without recognised errors, and
  # the log pages, from the preview and whatever stored copies there are.
  defp log_state(action, stored) do
    stderr =
      action
      |> Actions.recorded_log("stderr", stored["stderr"])
      |> Enum.map_join("\n", &elem(&1, 1))
      |> String.replace_invalid()

    pages = Actions.log_pages(action, stored)

    %{
      errors: Actions.errors(%{action | stderr: stderr}),
      failure_output: failure_output(stderr),
      log_pages: pages
    }
  end

  # Like a CI job log, the Logs tab opens at the end.
  defp show_log_end(%{assigns: %{selected_tab: "logs", log_pages: pages}} = socket) do
    {rows, first} = earlier_rows(pages, length(pages))
    socket |> stream(:log_rows, rows, reset: true) |> assign(:log_first_page, first)
  end

  defp show_log_end(socket), do: socket

  # The rows of the pages before `before`, going back until there are enough.
  defp earlier_rows(pages, before) do
    Enum.reduce_while((before - 1)..0//-1, {[], before}, fn index, {rows, _first} ->
      rows = page_rows(Enum.at(pages, index), index) ++ rows
      if length(rows) >= @log_rows, do: {:halt, {rows, index}}, else: {:cont, {rows, index}}
    end)
  end

  defp page_rows({:lines, first, text}, _index) do
    text
    |> Actions.log_lines()
    |> Enum.with_index(first)
    |> Enum.map(fn {line, number} -> %{id: "line-#{number}", number: number, text: line} end)
  end

  defp page_rows({:gap, stream, bytes, reason}, index) do
    stream =
      if stream == "stdout",
        do: dgettext("dashboard_builds", "Standard output"),
        else: dgettext("dashboard_builds", "Standard error")

    size = ByteFormatter.format_bytes(bytes)

    gap =
      case reason do
        :skipped ->
          dgettext(
            "dashboard_builds",
            "%{stream}: %{size} skipped. Output over 16 MiB keeps its first 16 KiB and its last 16 MiB.",
            stream: stream,
            size: size
          )

        :missing ->
          dgettext(
            "dashboard_builds",
            "%{stream}: the remaining %{size} is not available. It has not been stored yet, could not be stored, or has expired.",
            stream: stream,
            size: size
          )
      end

    [%{id: "gap-#{index}", gap: gap}]
  end

  defp invocation_path(assigns),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{assigns.invocation_id}?tab=remote-execution"

  defp action_path(assigns),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{assigns.invocation_id}/remote-actions/#{assigns.operation_id}"

  # Records have empty strings for what Bazel did not describe; the
  # scheduler's running actions have nil.
  defp title(%{mnemonic: mnemonic, target: target}) when mnemonic not in [nil, ""] and target not in [nil, ""],
    do: "#{mnemonic} #{target}"

  defp title(%{mnemonic: mnemonic}) when mnemonic not in [nil, ""], do: mnemonic
  defp title(%{action_hash: hash}), do: String.slice(hash, 0, 12)
  defp title(%{action_digest: digest}), do: String.slice(digest, 0, 12)

  # {header tile, badge label, badge color}
  defp status(action) do
    case Actions.status(action) do
      :error -> {"failure", dgettext("dashboard_builds", "Error"), "destructive"}
      :cached -> {"success", dgettext("dashboard_builds", "Cached"), "information"}
      :passed -> {"success", dgettext("dashboard_builds", "Passed"), "success"}
      :failed -> {"failure", dgettext("dashboard_builds", "Failed"), "destructive"}
    end
  end

  defp pending_status(%{state: "queued"}), do: {dgettext("dashboard_builds", "Queued"), "warning"}
  defp pending_status(%{state: "finishing"}), do: {dgettext("dashboard_builds", "Finishing"), "primary"}
  defp pending_status(_running), do: {dgettext("dashboard_builds", "Running"), "primary"}

  defp pending_duration(pending, observed_at),
    do:
      DateFormatter.format_duration_from_milliseconds(
        max(DateTime.diff(pending[:left_at] || observed_at, pending.since, :millisecond), 0), fractional_seconds: false)

  defp execution_path("lease"), do: dgettext("dashboard_builds", "Leased worker")
  defp execution_path("scheduled"), do: dgettext("dashboard_builds", "Scheduled")
  defp execution_path(_), do: dgettext("dashboard_builds", "Unknown")

  defp phase_label(:queue_ms), do: dgettext("dashboard_builds", "Queue")
  defp phase_label(:input_fetch_ms), do: dgettext("dashboard_builds", "Input fetch")
  defp phase_label(:execution_ms), do: dgettext("dashboard_builds", "Execution")
  defp phase_label(:output_upload_ms), do: dgettext("dashboard_builds", "Output upload")

  # Missing timestamps mean the executor did not report the phase, not that it took no time.
  defp duration(nil), do: dgettext("dashboard_builds", "Not recorded")
  defp duration(ms), do: DateFormatter.format_duration_from_milliseconds(ms)

  defp timestamp(nil, _timezone), do: dgettext("dashboard_builds", "Not recorded")

  defp timestamp(%NaiveDateTime{} = value, timezone),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateFormatter.format_with_timezone(timezone)

  # The command's working directory is relative to the action's input root,
  # which every Tuist worker materializes at `actionRoot` in
  # infra/sandbox-image/internal/executor/warm.go.
  defp working_directory(action), do: Path.join("/workspace/action", action.working_directory)

  defp long_command?(command_line), do: byte_size(command_line) > @long_command_bytes

  defp environment(action), do: Enum.zip(action.environment_names, action.environment_values)
  defp platform(action), do: Enum.zip(action.platform_names, action.platform_values)

  attr :label, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  defp detail(assigns) do
    ~H"""
    <div data-part="metadata" {@rest}>
      <div data-part="title">{@label}</div>
      <span data-part="label">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  # Compiler errors group by file, like a build's issues; an action whose
  # output has none still gets one card with its exit and the end of stderr.
  defp errors_by_path(errors) do
    errors
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Enum.map(fn path -> {path, Enum.filter(errors, &(&1.path == path))} end)
  end

  defp issue_message(%{path: path, line: line, column: column, message: message}) do
    location = Enum.join([path, line | List.wrap(column)], ":")
    dgettext("dashboard_builds", "%{message} at %{location}", message: message, location: location)
  end

  defp failure_title(%{status_code: code, status_message: message}) when code != 0 and message != "", do: message
  defp failure_title(%{status_code: code}) when code != 0, do: dgettext("dashboard_builds", "The execution failed")

  defp failure_title(%{exit_code: code}),
    do: dgettext("dashboard_builds", "The command exited with code %{code}", code: code)

  defp failure_output(stderr) do
    case stderr |> Actions.log_lines() |> Enum.reject(&(String.trim(&1) == "")) |> Enum.take(-10) do
      [] -> [dgettext("dashboard_builds", "No error output was recorded.")]
      lines -> [Enum.join(lines, "\n")]
    end
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :items, :list, required: true
  attr :output, :boolean, default: false

  defp issue_card(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      data-type="error"
      class="issue-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon"><.alert_circle /></div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">{@title}</h3>
              <span :if={@subtitle != ""} data-part="subtitle">{@subtitle}</span>
            </div>
            <.badge
              :if={not @output}
              label={length(@items)}
              color="destructive"
              style="light-fill"
              size="large"
            />
          </div>
          <.ghost_button data-part="closed-collapsible-button" variant="secondary" size="medium">
            <.chevron_down />
          </.ghost_button>
          <.ghost_button data-part="open-collapsible-button" variant="secondary" size="medium">
            <.chevron_up />
          </.ghost_button>
        </div>
        <div data-part="content" data-state="closed">
          <span :for={item <- @items} data-part="issue" data-output={@output}>{item}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :rows, :any, required: true
  attr :has_earlier, :boolean, required: true
  attr :empty, :boolean, required: true

  # stdout comes first, then stderr: the executor keeps them as separate blobs
  # without timestamps, so their interleaving is unknown. Line numbers run
  # across both; a marker in place says where bytes are not there and why.
  defp logs(assigns) do
    ~H"""
    <.card_section id="remote-action-logs" data-part="logs-section">
      <div
        :if={not @empty}
        id="remote-action-log-viewport"
        phx-hook="ScrollToTail"
        data-part="log-viewport"
        data-scroll-to-tail-item-selector="[data-part='log-line'], [data-part='log-truncated']"
      >
        <button
          :if={@has_earlier}
          type="button"
          phx-click="load_earlier_log_lines"
          data-part="load-earlier"
        >
          {dgettext("dashboard_builds", "Load earlier lines")}
        </button>
        <div id="remote-action-log-rows" phx-update="stream" data-part="log-stream">
          <%= for {dom_id, row} <- @rows do %>
            <div :if={row[:gap]} id={dom_id} data-part="log-truncated">{row.gap}</div>
            <div
              :if={row[:text]}
              id={dom_id}
              data-part="log-line"
              data-annotation={if Actions.error_line?(row.text), do: "error"}
            >
              <span data-part="log-ln">{row.number}</span>
              <span data-part="log-message">{row.text}</span>
            </div>
          <% end %>
        </div>
      </div>
      <p :if={@empty} data-part="empty">
        {dgettext("dashboard_builds", "No output was recorded.")}
      </p>
    </.card_section>
    """
  end

  attr :id, :string, required: true
  attr :pairs, :list, required: true

  # Names above values in the details grid, like Action Details: actions set
  # a handful of variables and platform properties, so all of them show.
  defp pairs(assigns) do
    ~H"""
    <dl id={@id} data-part="metadata-grid">
      <div data-part="metadata-row">
        <div :for={{name, value} <- @pairs} data-part="metadata">
          <dt data-part="title">{name}</dt>
          <%!-- Bazel sets some variables to an empty string (rules_rust's
               CARGO_PKG_AUTHORS for a crate without authors), which differs from unset. --%>
          <dd :if={value != ""} data-part="label"><code>{value}</code></dd>
          <dd :if={value == ""} data-part="label" data-empty>
            {dgettext("dashboard_builds", "Empty")}
          </dd>
        </div>
      </div>
    </dl>
    """
  end
end
