defmodule TuistWeb.PulseErrorLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Pulse
  alias TuistWeb.PulseLive

  @params ~w(range end_at page page_size service)

  def mount(_params, _session, socket) do
    authorize!(socket)
    {:ok, assign(socket, detail: AsyncResult.loading())}
  end

  def handle_params(params, _uri, socket) do
    authorize!(socket)
    fingerprint = params["fingerprint"]
    event_id = params["event_id"]

    inputs =
      params
      |> Map.take(@params)
      |> Map.put_new("range", "1h")
      |> Map.put_new("end_at", socket.assigns[:params]["end_at"] || DateTime.to_iso8601(DateTime.utc_now()))

    user = socket.assigns.current_user
    account = socket.assigns.selected_account
    load_key = {fingerprint, event_id, inputs}
    reload? = socket.assigns[:load_key] != load_key || socket.assigns.detail.failed

    socket =
      socket
      |> assign(:params, inputs)
      |> assign(:tab, if(params["tab"] == "occurrences", do: "occurrences", else: "overview"))
      |> assign(:fingerprint, fingerprint)
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
                do: Pulse.error_event(user, account, fingerprint, event_id, Map.drop(inputs, ~w(page page_size))),
                else: Pulse.error_issue(user, account, fingerprint, inputs)

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
    if !Pulse.authorized?(socket.assigns.current_user, socket.assigns.selected_account),
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
          <.detail_header record={Map.merge(@detail.result.event, %{"service" => @params["service"]})} />
          <.card title={dgettext("dashboard_pulse", "Event details")} icon="alert_circle">
            <.card_section>
              <dl data-part="metadata-grid">
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
                  :if={event["trace_id"] not in [nil, ""]}
                  label={dgettext("dashboard_pulse", "Trace ID")}
                  value={event["trace_id"]}
                />
                <.detail_field
                  :if={span_id(event)}
                  label={dgettext("dashboard_pulse", "Span ID")}
                  value={span_id(event)}
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
                  value={format_number(issue["events"], fractional_digits: 0)}
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
                  value={PulseLive.timestamp_relative(issue["first_seen"])}
                  title={PulseLive.timestamp_label(issue["first_seen"]) <> " UTC"}
                />
                <.detail_field
                  label={dgettext("dashboard_pulse", "Last seen")}
                  value={PulseLive.timestamp_relative(issue["last_seen"])}
                  title={PulseLive.timestamp_label(issue["last_seen"]) <> " UTC"}
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
            size="medium"
          />
          <.badge
            :if={@record["level"]}
            label={@record["level"]}
            color={PulseLive.error_level_color(@record["level"])}
            style="light-fill"
            size="medium"
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
    <.card
      id="pulse-stacktrace"
      title={
        if @exceptions == [] && @event["message"] not in [nil, ""],
          do: dgettext("dashboard_pulse", "Message"),
          else: dgettext("dashboard_pulse", "Stack trace")
      }
      icon="list_tree"
    >
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
            value={PulseLive.timestamp_relative(@event["timestamp"])}
            title={PulseLive.timestamp_label(@event["timestamp"]) <> " UTC"}
          />
          <div :if={@event["environment"] not in [nil, ""]}>
            <dt>{dgettext("dashboard_pulse", "Environment")}</dt>
            <dd><.badge label={@event["environment"]} style="light-fill" /></dd>
          </div>
          <div :if={@event["release"] not in [nil, ""]}>
            <dt>{dgettext("dashboard_pulse", "Release")}</dt>
            <dd><.badge label={@event["release"]} style="light-fill" /></dd>
          </div>
        </dl>
        <pre :if={@exceptions == [] && @event["message"] not in [nil, ""]} data-part="message-body">{@event["message"]}</pre>
        <p :if={@exceptions == [] && @event["message"] not in [nil, ""]} data-part="message-note">
          {dgettext("dashboard_pulse", "This event recorded a message, not an exception.")}
        </p>
        <.table_empty_state
          :if={@exceptions == [] && @event["message"] in [nil, ""]}
          title={dgettext("dashboard_pulse", "No exception recorded")}
        />
        <section :for={{exception, index} <- Enum.with_index(@exceptions)} data-part="exception">
          <div data-part="exception-metadata">
            <span data-part="meta-label">{dgettext("dashboard_pulse", "Exception")}</span>
            <span data-part="meta-value">{exception["type"] || "—"}</span>
          </div>
          <pre :if={exception["value"]} data-part="message-body">{exception["value"]}</pre>
          <.table_empty_state
            :if={(exception["frames"] || []) == []}
            title={dgettext("dashboard_pulse", "No stack frames recorded")}
          />
          <div
            :if={(exception["frames"] || []) != []}
            id={"pulse-stack-frames-#{index}"}
            data-part="stack-frames"
          >
            <div
              :for={frame <- Enum.reverse(exception["frames"] || [])}
              data-part="stack-frame"
              data-in-app={to_string(frame["in_app"] == true)}
              title={
                if frame["in_app"] == true,
                  do: dgettext("dashboard_pulse", "In app"),
                  else: dgettext("dashboard_pulse", "External")
              }
            >
              <span data-part="frame-function">{frame_function(frame)}</span>
              <span data-part="frame-location">{frame_location(frame)}</span>
              <div :if={frame["context_line"] not in [nil, ""]} data-part="frame-context">
                <span data-part="line-number">{frame["lineno"]}</span>
                <pre>{frame["context_line"]}</pre>
              </div>
            </div>
          </div>
        </section>
      </.card_section>
    </.card>
    """
  end

  # Sentry lists chained exceptions oldest first; the raised one leads.
  defp exceptions(%{"exception" => [_ | _] = exceptions}), do: Enum.reverse(exceptions)
  defp exceptions(_event), do: []

  # Elixir, Erlang and Rust SDKs already qualify the function; others, such as
  # Python, report it relative to its module.
  defp frame_function(%{"module" => module, "function" => function})
       when is_binary(module) and module != "" and is_binary(function) do
    short = String.replace_prefix(module, "Elixir.", "")
    if String.contains?(function, short) or String.contains?(function, "::"), do: function, else: "#{short}.#{function}"
  end

  defp frame_function(frame), do: if(frame["function"] in [nil, ""], do: "—", else: frame["function"])

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
      :if={metadata_pairs(contexts(@event["contexts"])) != []}
      id="pulse-event-contexts"
      title={dgettext("dashboard_pulse", "Contexts")}
      icon="stack_2"
    >
      <.card_section>
        <div data-part="contexts-grid">
          <section
            :for={{name, context} <- metadata_pairs(contexts(@event["contexts"]))}
            data-part="context-group"
          >
            <div data-part="context-header">
              <span data-part="context-icon"><.icon name={context_icon(name)} /></span>
              <h3 data-part="context-heading">
                {context_name(name)}
              </h3>
            </div>
            <dl data-part="metadata-grid" data-layout="event-data">
              <.metadata_field
                :for={{key, value} <- metadata_pairs(context)}
                label={key}
                value={value}
              />
              <.metadata_field :if={!is_map(context)} label={name} value={context} />
            </dl>
          </section>
        </div>
      </.card_section>
    </.card>
    <.card
      :if={
        is_map(@event["request"]) &&
          Enum.any?(~w(method url), &(@event["request"][&1] not in [nil, ""]))
      }
      id="pulse-event-request"
      title={dgettext("dashboard_pulse", "Request")}
      icon="server"
    >
      <.card_section>
        <div data-part="request-line">
          <.badge
            :if={@event["request"]["method"] not in [nil, ""]}
            label={@event["request"]["method"]}
            color="primary"
            style="light-fill"
          />
          <code>{@event["request"]["url"]}</code>
        </div>
      </.card_section>
    </.card>
    <.card
      :if={is_list(@event["breadcrumbs"]) && @event["breadcrumbs"] != []}
      id="pulse-event-breadcrumbs"
      title={dgettext("dashboard_pulse", "Breadcrumbs")}
      icon="list_tree"
    >
      <.card_section>
        <ol data-part="timeline">
          <li :for={crumb <- @event["breadcrumbs"]} data-part="timeline-item">
            <span data-part="timeline-icon"><.icon name="history" /></span>
            <div data-part="timeline-content">
              <.badge
                label={crumb["category"] || crumb["type"] || "log"}
                color={PulseLive.error_level_color(crumb["level"])}
                style="light-fill"
                size="small"
              />
              <p :if={crumb["message"]}>{crumb["message"]}</p>
            </div>
            <span data-part="timeline-time">{breadcrumb_time(crumb["timestamp"])}</span>
          </li>
        </ol>
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
      :if={@event["sdk"] not in [nil, "", "/"]}
      id="pulse-event-sdk"
      title={dgettext("dashboard_pulse", "SDK")}
      icon="devices_code"
    >
      <.card_section>
        <dl data-part="metadata-grid">
          <.detail_field
            label={dgettext("dashboard_pulse", "Name")}
            value={@event["sdk"] |> String.split("/", parts: 2) |> List.first()}
          />
          <.detail_field
            label={dgettext("dashboard_pulse", "Version")}
            value={@event["sdk"] |> String.split("/", parts: 2) |> Enum.at(1)}
          />
        </dl>
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

  defp contexts(contexts) when is_map(contexts) do
    Enum.reduce(contexts, %{}, fn {key, value}, groups ->
      case String.split(key, ".", parts: 2) do
        [name, field] ->
          Map.update(groups, name, %{field => value}, &if(is_map(&1), do: Map.put(&1, field, value), else: &1))

        [name] ->
          Map.put_new(groups, name, value)
      end
    end)
  end

  defp contexts(_contexts), do: %{}

  defp context_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", fn word ->
      if word in ~w(os sdk gpu cpu url http api ssl tls ip id), do: String.upcase(word), else: String.capitalize(word)
    end)
  end

  defp context_icon("runtime"), do: "devices_code"
  defp context_icon("os"), do: "device_desktop"
  defp context_icon("trace"), do: "list_tree"
  defp context_icon("device"), do: "device_mobile"
  defp context_icon(_name), do: "stack_2"

  defp breadcrumb_time(time) when is_number(time) do
    case DateTime.from_unix(trunc(time * 1_000_000), :microsecond) do
      {:ok, datetime} -> Calendar.strftime(datetime, "%H:%M:%S UTC")
      _ -> "—"
    end
  end

  defp breadcrumb_time(time) when is_binary(time), do: time
  defp breadcrumb_time(_time), do: "—"

  defp span_id(event), do: if(is_map(event["contexts"]), do: event["contexts"]["trace.span_id"])

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
    do: ~p"/#{assigns.selected_account.name}/pulse/errors?#{Map.take(assigns.params, ~w(range end_at))}"

  defp back_path(assigns), do: tab_path(assigns, "occurrences")

  defp tab_path(assigns, tab),
    do:
      ~p"/#{assigns.selected_account.name}/pulse/errors/issues/#{assigns.fingerprint}?#{Map.put(assigns.params, "tab", tab)}"

  defp event_path(assigns, event),
    do:
      ~p"/#{assigns.selected_account.name}/pulse/errors/issues/#{assigns.fingerprint}/events/#{event["event_id"]}?#{Map.drop(assigns.params, ~w(page page_size))}"

  defp page_path(assigns, direction) do
    params =
      assigns.params
      |> Map.put("page", max(1, assigns.detail.result.meta["page"] + direction))
      |> Map.put("tab", "occurrences")

    ~p"/#{assigns.selected_account.name}/pulse/errors/issues/#{assigns.fingerprint}?#{params}"
  end

  defp detail_error({:error, :not_found}),
    do: dgettext("dashboard_pulse", "This issue or event was not found in the selected period.")

  defp detail_error(_),
    do: dgettext("dashboard_pulse", "Pulse could not load these details. Return to Errors and try again.")
end
