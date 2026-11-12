defmodule TuistWeb.PulseErrorLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Pulse
  alias TuistWeb.PulseLive

  @params ~w(range end_at page page_size project environment release service)

  def mount(_params, _session, socket) do
    authorize!(socket)
    {:ok, assign(socket, detail: AsyncResult.loading())}
  end

  def handle_params(params, _uri, socket) do
    authorize!(socket)
    issue_id = params["issue_id"]
    event_id = params["event_id"]

    inputs =
      params
      |> Map.take(@params)
      |> Map.put_new("range", "1h")
      |> Map.put_new("end_at", socket.assigns[:params]["end_at"] || DateTime.to_iso8601(DateTime.utc_now()))

    user = socket.assigns.current_user
    account = socket.assigns.selected_account
    load_key = {issue_id, event_id, inputs}
    reload? = socket.assigns[:load_key] != load_key || socket.assigns.detail.failed

    socket =
      socket
      |> assign(:params, inputs)
      |> assign(:tab, if(params["tab"] == "occurrences", do: "occurrences", else: "overview"))
      |> assign(:issue_id, issue_id)
      |> assign(:event_id, event_id)
      |> assign(:head_title, "#{dgettext("dashboard_pulse", "Error details")} · #{account.name} · Tuist")

    socket =
      if connected?(socket) && reload? do
        socket
        |> assign(:load_key, load_key)
        |> cancel_async(:detail)
        |> assign_async(
          :detail,
          fn ->
            result =
              if event_id,
                do: Pulse.error_event(user, account, issue_id, event_id, Map.drop(inputs, ~w(page page_size))),
                else: Pulse.error_issue(user, account, issue_id, inputs)

            case result do
              {:ok, data} -> {:ok, %{detail: data}}
              {:error, reason} -> {:error, reason}
            end
          end,
          reset: true
        )
      else
        socket
      end

    {:noreply, socket}
  end

  defp authorize!(socket) do
    if !Pulse.errors_available?() or !Pulse.authorized?(socket.assigns.current_user, socket.assigns.selected_account),
      do: raise(TuistWeb.Errors.NotFoundError, "Not found")
  end

  def render(assigns) do
    ~H"""
    <div id="pulse-error-detail">
      <.button
        id="pulse-error-back"
        data-part="back-button"
        variant="secondary"
        size="medium"
        label={
          if @event_id,
            do: dgettext("dashboard_pulse", "Back to issue"),
            else: dgettext("dashboard_pulse", "Errors")
        }
        navigate={back_path(assigns)}
      >
        <:icon_left><.arrow_left /></:icon_left>
      </.button>
      <%= cond do %>
        <% @detail.failed -> %>
          <.card title={dgettext("dashboard_pulse", "Error details")} icon="alert_circle">
            <.card_section>
              <.error_state
                id="pulse-detail-error"
                title={dgettext("dashboard_pulse", "Error details unavailable")}
                subtitle={detail_error(@detail.failed)}
              />
            </.card_section>
          </.card>
        <% !@detail.ok? -> %>
          <.card title={dgettext("dashboard_pulse", "Error details")} icon="alert_circle">
            <.card_section><.skeleton_chart height="200px" /></.card_section>
          </.card>
        <% @event_id -> %>
          <% event = @detail.result.event %>
          <.detail_header record={event} />
          <.card title={dgettext("dashboard_pulse", "Event details")} icon="alert_circle">
            <.card_section>
              <dl data-part="metadata-grid">
                <.detail_field
                  label={dgettext("dashboard_pulse", "Project")}
                  value={event["project"]}
                />
                <.detail_field
                  label={dgettext("dashboard_pulse", "Time (UTC)")}
                  value={PulseLive.timestamp_label(event["timestamp"])}
                />
                <.detail_field
                  label={dgettext("dashboard_pulse", "Environment")}
                  value={event["environment"]}
                />
                <.detail_field
                  label={dgettext("dashboard_pulse", "Release")}
                  value={event["release"]}
                />
                <.detail_field
                  label={dgettext("dashboard_pulse", "Event ID")}
                  value={event["event_id"]}
                />
                <.detail_field
                  :if={event["trace_id"]}
                  label={dgettext("dashboard_pulse", "Trace ID")}
                  value={event["trace_id"]}
                />
                <.detail_field
                  :if={event["span_id"]}
                  label={dgettext("dashboard_pulse", "Span ID")}
                  value={event["span_id"]}
                />
              </dl>
            </.card_section>
          </.card>
          <.exception_details event={event} />
          <.event_metadata event={event} />
        <% true -> %>
          <% issue = @detail.result.issue %>
          <.detail_header record={issue} />
          <.tab_menu_horizontal>
            <.tab_menu_horizontal_item
              id="pulse-error-overview-tab"
              label={dgettext("dashboard", "Overview")}
              selected={@tab == "overview"}
              patch={tab_path(assigns, "overview")}
              replace={true}
            />
            <.tab_menu_horizontal_item
              id="pulse-error-occurrences-tab"
              label={dgettext("dashboard_pulse", "Occurrences")}
              selected={@tab == "occurrences"}
              patch={tab_path(assigns, "occurrences")}
              replace={true}
            />
          </.tab_menu_horizontal>
          <.card
            :if={@tab == "overview"}
            id="pulse-issue-overview"
            title={dgettext("dashboard", "Overview")}
            icon="info_circle"
          >
            <.card_section>
              <dl data-part="metadata-grid" data-layout="overview">
                <div>
                  <dt>{dgettext("dashboard_pulse", "Level")}</dt>
                  <dd>
                    <.badge
                      :if={issue["level"]}
                      label={issue["level"]}
                      color={PulseLive.error_level_color(issue["level"])}
                      style="light-fill"
                      size="small"
                    />
                    <span :if={!issue["level"]}>{dgettext("dashboard_pulse", "Not recorded")}</span>
                  </dd>
                </div>
                <.detail_field
                  label={dgettext("dashboard_pulse", "Events in this period")}
                  value={format_number(issue["count"], fractional_digits: 0)}
                />
                <div>
                  <dt>{dgettext("dashboard_pulse", "Platform")}</dt>
                  <dd data-part="platform-value">
                    <.icon name={PulseLive.error_platform_icon(issue["platform"])} />
                    {PulseLive.error_platform_label(issue["platform"])}
                  </dd>
                </div>
                <.detail_field
                  label={dgettext("dashboard_pulse", "First seen in this period")}
                  value={PulseLive.timestamp_relative(issue["first_seen_ns"])}
                  title={PulseLive.timestamp_label(issue["first_seen_ns"]) <> " UTC"}
                />
                <.detail_field
                  label={dgettext("dashboard_pulse", "Last seen")}
                  value={PulseLive.timestamp_relative(issue["last_seen_ns"])}
                  title={PulseLive.timestamp_label(issue["last_seen_ns"]) <> " UTC"}
                />
              </dl>
            </.card_section>
          </.card>
          <.card
            :if={@tab == "overview"}
            title={dgettext("dashboard_pulse", "Occurrences")}
            icon="chart_arcs"
          >
            <.card_section data-part="occurrence-chart">
              <.chart
                id="pulse-issue-occurrences"
                type="bar"
                series={[
                  %{
                    name: dgettext("dashboard_pulse", "Events"),
                    data:
                      Enum.map(@detail.result.occurrence_series, fn [time, count] ->
                        [time * 1000, count]
                      end),
                    barMaxWidth: 32
                  }
                ]}
                show_legend={false}
                extra_options={
                  %{
                    grid: %{left: 16, right: 16, top: 16, bottom: 16, containLabel: true},
                    xAxis: %{type: "time", splitNumber: 4, axisLabel: %{hideOverlap: true}},
                    yAxis: %{min: 0, minInterval: 1, axisLabel: %{formatter: "fn:formatNumber"}},
                    tooltip: %{trigger: "axis", valueFormat: "fn:formatNumber"}
                  }
                }
              />
            </.card_section>
          </.card>
          <.exception_details
            :if={@tab == "overview"}
            event={@detail.result.latest_event}
            navigate={event_path(assigns, @detail.result.latest_event)}
          />
          <.event_metadata :if={@tab == "overview"} event={@detail.result.latest_event} />
          <.card
            :if={@tab == "occurrences"}
            title={dgettext("dashboard_pulse", "Occurrences")}
            icon="history"
          >
            <.card_section data-part="table-section">
              <.table
                id="pulse-error-events"
                rows={@detail.result.events}
                row_key={&("pulse-event-" <> &1["event_id"])}
                row_navigate={&event_path(assigns, &1)}
              >
                <:col :let={event} label={dgettext("dashboard_pulse", "Time (UTC)")}>
                  <.text_cell label={PulseLive.timestamp_label(event["timestamp"])} />
                </:col>
                <:col :let={event} label={dgettext("dashboard_pulse", "Level")}>
                  <.badge_cell
                    label={event["level"] || "—"}
                    color={PulseLive.error_level_color(event["level"])}
                  />
                </:col>
                <:col :let={event} label={dgettext("dashboard_pulse", "Environment")}>
                  <.text_cell label={event["environment"] || "—"} />
                </:col>
                <:col :let={event} label={dgettext("dashboard_pulse", "Release")}>
                  <.text_cell label={event["release"] || "—"} />
                </:col>
                <:col :let={event} label={dgettext("dashboard_pulse", "Event ID")}>
                  <.text_cell label={event["event_id"]} />
                </:col>
                <:empty_state>
                  <.table_empty_state title={
                    dgettext("dashboard_pulse", "No occurrences in this period")
                  } />
                </:empty_state>
              </.table>
              <nav
                :if={@detail.result.meta["has_previous_page"] || @detail.result.meta["has_next_page"]}
                class="tuist-pagination"
                aria-label={dgettext("dashboard_pulse", "Occurrence pages")}
              >
                <.button
                  id="pulse-events-prev"
                  variant="secondary"
                  label={dgettext("dashboard", "Prev")}
                  disabled={!@detail.result.meta["has_previous_page"]}
                  patch={page_path(assigns, -1)}
                >
                  <:icon_left><.chevron_left /></:icon_left>
                </.button>
                <.button
                  id="pulse-events-next"
                  variant="secondary"
                  label={dgettext("dashboard", "Next")}
                  disabled={!@detail.result.meta["has_next_page"]}
                  patch={page_path(assigns, 1)}
                >
                  <:icon_right><.chevron_right /></:icon_right>
                </.button>
              </nav>
            </.card_section>
          </.card>
      <% end %>
    </div>
    """
  end

  attr :record, :map, required: true

  defp detail_header(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="title-group">
        <div data-part="title">
          <span data-part="error-icon"><.alert_circle /></span>
          <h1 data-part="detail-title">{@record["title"]}</h1>
        </div>
        <div data-part="badges">
          <.badge
            :if={@record["service"]}
            label={@record["service"]}
            color="primary"
            style="light-fill"
            size="large"
          />
          <.badge
            :if={@record["project"]}
            label={@record["project"]}
            color="neutral"
            style="light-fill"
            size="large"
          />
          <.badge
            :if={@record["level"]}
            label={@record["level"]}
            color={PulseLive.error_level_color(@record["level"])}
            style="light-fill"
            size="large"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true
  attr :navigate, :string, default: nil

  defp exception_details(assigns) do
    assigns = assign(assigns, :exceptions, exceptions(assigns.event))

    ~H"""
    <.card id="pulse-stacktrace" title={dgettext("dashboard_pulse", "Stack trace")} icon="list_tree">
      <:actions :if={@navigate}>
        <.button
          variant="secondary"
          size="small"
          label={dgettext("dashboard_pulse", "View event")}
          navigate={@navigate}
        />
      </:actions>
      <.card_section>
        <dl :if={@navigate} data-part="metadata-grid">
          <.detail_field
            label={dgettext("dashboard_pulse", "Latest event")}
            value={PulseLive.timestamp_label(@event["timestamp"])}
          />
          <div :if={@event["environment"]}>
            <dt>{dgettext("dashboard_pulse", "Environment")}</dt>
            <dd><.badge label={@event["environment"]} style="light-fill" /></dd>
          </div>
          <div :if={@event["release"]}>
            <dt>{dgettext("dashboard_pulse", "Release")}</dt>
            <dd><.badge label={@event["release"]} style="light-fill" /></dd>
          </div>
        </dl>
        <.table_empty_state
          :if={@exceptions == []}
          title={dgettext("dashboard_pulse", "No exception recorded")}
        />
        <section :for={{exception, index} <- Enum.with_index(@exceptions)} data-part="exception">
          <div data-part="exception-heading">
            <h3>{exception["type"] || dgettext("dashboard_pulse", "Exception")}</h3>
            <p :if={exception["value"]}>{exception["value"]}</p>
          </div>
          <.table_empty_state
            :if={(exception["frames"] || []) == []}
            title={dgettext("dashboard_pulse", "No stack frames recorded")}
          />
          <.table
            :if={(exception["frames"] || []) != []}
            id={"pulse-stack-frames-#{index}"}
            rows={Enum.with_index(Enum.reverse(exception["frames"] || []))}
            row_key={fn {_, frame_index} -> "pulse-frame-#{index}-#{frame_index}" end}
          >
            <:col :let={{frame, _}} label={dgettext("dashboard_pulse", "Function")}>
              <div data-part="stack-frame" data-in-app={to_string(frame["in_app"] == true)}>
                <code><span :if={frame["module"]}>{frame["module"]}.</span>{frame["function"] || "—"}</code>
              </div>
            </:col>
            <:col :let={{frame, _}} label={dgettext("dashboard_pulse", "File")}>
              <.text_cell label={frame_location(frame)} data-column="frame-location" />
            </:col>
            <:col :let={{frame, _}} label={dgettext("dashboard_pulse", "Origin")}>
              <div data-part="cell">
                <.badge
                  label={
                    if frame["in_app"] == true,
                      do: dgettext("dashboard_pulse", "In app"),
                      else: dgettext("dashboard_pulse", "External")
                  }
                  color={if frame["in_app"] == true, do: "primary", else: "neutral"}
                  style="light-fill"
                  size="small"
                />
              </div>
            </:col>
          </.table>
        </section>
      </.card_section>
    </.card>
    """
  end

  defp exceptions(%{"exceptions" => [_ | _] = exceptions}), do: Enum.reverse(exceptions)
  defp exceptions(%{"exception" => exception}) when map_size(exception) > 0, do: [exception]
  defp exceptions(_event), do: []

  defp frame_location(%{"filename" => filename, "lineno" => line}) when is_binary(filename) and is_integer(line),
    do: "#{filename}:#{line}"

  defp frame_location(frame), do: frame["filename"] || "—"

  attr :event, :map, required: true

  defp event_metadata(assigns) do
    ~H"""
    <.card
      :if={metadata_pairs(@event["tags"]) != []}
      id="pulse-event-tags"
      title={dgettext("dashboard_pulse", "Tags")}
      icon="alert_hexagon"
    >
      <.card_section>
        <dl data-part="metadata-grid" data-layout="event-data">
          <.metadata_field
            :for={{key, value} <- metadata_pairs(@event["tags"])}
            label={key}
            value={value}
          />
        </dl>
      </.card_section>
    </.card>
    <.card
      :if={metadata_pairs(@event["contexts"]) != []}
      id="pulse-event-contexts"
      title={dgettext("dashboard_pulse", "Contexts")}
      icon="stack_2"
    >
      <.card_section>
        <section
          :for={{name, context} <- metadata_pairs(@event["contexts"])}
          data-part="context-group"
        >
          <h3 data-part="context-heading">{name}</h3>
          <dl data-part="metadata-grid" data-layout="event-data">
            <.metadata_field :for={{key, value} <- metadata_pairs(context)} label={key} value={value} />
            <.metadata_field :if={!is_map(context)} label={name} value={context} />
          </dl>
        </section>
      </.card_section>
    </.card>
    <.card
      :if={metadata_pairs(@event["extra"]) != []}
      id="pulse-event-extra"
      title={dgettext("dashboard_pulse", "Additional data")}
      icon="database"
    >
      <.card_section>
        <dl data-part="metadata-grid" data-layout="event-data">
          <.metadata_field
            :for={{key, value} <- metadata_pairs(@event["extra"])}
            label={key}
            value={value}
          />
        </dl>
      </.card_section>
    </.card>
    <.card
      :if={metadata_pairs(@event["modules"]) != []}
      id="pulse-event-modules"
      title={dgettext("dashboard_pulse", "Modules")}
      icon="package"
    >
      <.card_section>
        <.table
          id="pulse-modules-table"
          rows={metadata_pairs(@event["modules"])}
          row_key={fn {name, _} -> "pulse-module-" <> Base.url_encode64(name, padding: false) end}
        >
          <:col :let={{name, _}} label={dgettext("dashboard_pulse", "Module")}>
            <.text_cell label={name} />
          </:col>
          <:col :let={{_, version}} label={dgettext("dashboard_pulse", "Version")}>
            <.text_cell label={metadata_value(version)} />
          </:col>
        </.table>
      </.card_section>
    </.card>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp metadata_field(assigns) do
    ~H"""
    <div data-structured={to_string(is_map(@value) || is_list(@value))}>
      <dt>{@label}</dt>
      <dd>
        <div :if={is_map(@value) || is_list(@value)}>{metadata_value(@value)}</div><span :if={
          !is_map(@value) && !is_list(@value)
        }>{metadata_value(@value)}</span>
      </dd>
    </div>
    """
  end

  defp metadata_pairs(value) when is_map(value), do: Enum.sort(value)
  defp metadata_pairs(_), do: []
  defp metadata_value(value) when is_binary(value), do: value

  defp metadata_value(value) when is_map(value) or is_list(value) do
    value
    |> :json.format(fn
      nil, _encoder, _state -> "null"
      value, encoder, state -> :json.format_value(value, encoder, state)
    end)
    |> IO.iodata_to_binary()
    |> Lumis.highlight!(language: "json", formatter: :html_linked)
    |> Phoenix.HTML.raw()
  end

  defp metadata_value(value), do: JSON.encode!(value)

  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :title, :string, default: nil

  defp detail_field(assigns) do
    ~H"""
    <div>
      <dt>{@label}</dt><dd title={@title}>{if @value in [nil, ""], do: "—", else: @value}</dd>
    </div>
    """
  end

  defp back_path(%{event_id: nil} = assigns),
    do: ~p"/#{assigns.selected_account.name}/~/pulse/errors?#{Map.take(assigns.params, ~w(range end_at))}"

  defp back_path(assigns), do: tab_path(assigns, "occurrences")

  defp tab_path(assigns, tab),
    do:
      ~p"/#{assigns.selected_account.name}/~/pulse/errors/issues/#{assigns.issue_id}?#{Map.put(assigns.params, "tab", tab)}"

  defp event_path(assigns, event),
    do:
      ~p"/#{assigns.selected_account.name}/~/pulse/errors/issues/#{assigns.issue_id}/events/#{event["event_id"]}?#{Map.drop(assigns.params, ~w(page page_size))}"

  defp page_path(assigns, direction) do
    params =
      assigns.params
      |> Map.put("page", max(1, assigns.detail.result.meta["page"] + direction))
      |> Map.put("tab", "occurrences")

    ~p"/#{assigns.selected_account.name}/~/pulse/errors/issues/#{assigns.issue_id}?#{params}"
  end

  defp detail_error({:error, :not_found}),
    do: dgettext("dashboard_pulse", "This issue or event was not found in the selected period.")

  defp detail_error(_),
    do: dgettext("dashboard_pulse", "Pulse could not load these details. Return to Errors and try again.")
end
