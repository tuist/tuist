defmodule TuistWeb.PulseSymptomsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton

  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Pulse
  alias Tuist.Pulse.Symptoms
  alias Tuist.Utilities.DateFormatter

  @refresh_interval 60_000
  @params ~w(range widget page search sort_by sort_order)
  @filter_params ~w(filter_state_op filter_state_val filter_tier_op filter_tier_val filter_phenomenon_op filter_phenomenon_val)
  @sorts ~w(revised_at opened_at p_degraded impact_rate)

  def mount(_params, _session, socket) do
    authorize!(socket)
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)
    {:ok, assign(socket, symptoms: AsyncResult.loading(), analytics: AsyncResult.loading(), load_keys: %{})}
  end

  def handle_params(params, _uri, socket) do
    authorize!(socket)
    params = params |> Map.take(@params ++ @filter_params) |> Map.reject(fn {_, v} -> v in [nil, ""] end)
    params = if params["range"] in ~w(24h 7d 30d), do: params, else: Map.put(params, "range", "7d")
    params = if params["sort_by"] in @sorts, do: params, else: Map.drop(params, ~w(sort_by sort_order))
    filters = define_filters()
    params = normalize(params, filters)
    widget = Enum.find(widgets(), &(&1.id == params["widget"])) || hd(widgets())
    sort_by = params["sort_by"] || "revised_at"
    sort_order = if params["sort_order"] in ~w(asc desc), do: params["sort_order"], else: "desc"

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:available_filters, filters)
     |> assign(:active_filters, Filter.Operations.decode_filters_from_query(params, filters))
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:widget, widget)
     |> assign(
       :head_title,
       "Pulse · #{socket.assigns.selected_account.name} · Tuist"
     )
     |> load()}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    authorize!(socket)
    {:noreply, push_patch(socket, to: symptoms_path(socket.assigns, %{"widget" => widget}), replace: true)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    authorize!(socket)
    {:noreply, push_patch(socket, to: symptoms_path(socket.assigns, %{"search" => search, "page" => nil}), replace: true)}
  end

  def handle_event("add_filter", %{"value" => id}, socket) do
    authorize!(socket)

    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) do
      params = id |> Filter.Operations.add_filter_to_query(socket, socket.assigns.params) |> Map.delete("page")

      {:noreply,
       socket
       |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/pulse?#{params}")
       |> push_event("open-dropdown", %{id: "filter-#{id}-value-dropdown"})
       |> push_event("open-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", params, socket) do
    authorize!(socket)
    params = params |> Filter.Operations.update_filters_in_query(socket, socket.assigns.params) |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/pulse?#{params}")
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_info(:refresh, socket) do
    authorize!(socket)
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load(socket, true)}
  end

  defp authorize!(socket) do
    if !Pulse.authorized?(socket.assigns.current_user, socket.assigns.selected_account) do
      raise TuistWeb.Errors.NotFoundError, "Not found"
    end
  end

  defp load(socket, force \\ false) do
    user = socket.assigns.current_user
    account = socket.assigns.selected_account
    params = socket.assigns.params

    Enum.reduce(
      [
        {:symptoms, list_inputs(socket.assigns), fn inputs -> Symptoms.list(user, account, inputs) end},
        {:analytics, Map.take(params, ~w(range)), fn inputs -> Symptoms.analytics(user, account, inputs) end}
      ],
      socket,
      fn {key, inputs, fun}, socket ->
        result = socket.assigns[key]
        changed? = socket.assigns.load_keys[key] != inputs

        if connected?(socket) && (changed? || (!result.loading && (force || result.failed))) do
          socket
          |> cancel_async(key)
          |> assign(:load_keys, Map.put(socket.assigns.load_keys, key, inputs))
          |> assign_async(key, fn -> async_result(key, fun.(inputs)) end)
        else
          socket
        end
      end
    )
  end

  defp async_result(key, {:ok, value}), do: {:ok, %{key => value}}
  defp async_result(_key, error), do: error

  def render(assigns) do
    ~H"""
    <div id="pulse" data-signal="symptoms">
      <div data-part="filters">
        <.dropdown
          id="symptoms-range"
          label={range_label(@params["range"])}
          secondary_text={dgettext("dashboard_pulse", "Period:")}
        >
          <.dropdown_item
            :for={range <- ~w(24h 7d 30d)}
            value={range}
            label={range_label(range)}
            data-selected={@params["range"] == range}
            patch={symptoms_path(assigns, %{"range" => range})}
          />
        </.dropdown>
      </div>
      <.async_card
        :let={ready?}
        id="symptoms-analytics"
        results={[@analytics]}
        title={dgettext("dashboard", "Analytics")}
        icon="chart_arcs"
        data-part="analytics-card"
        chart_frame="cache"
      >
        <div data-part="widgets">
          <.widget
            :for={widget <- widgets()}
            id={"symptoms-widget-#{widget.id}"}
            title={widget.title}
            description={widget.description}
            loading={!ready?}
            value={
              if ready?,
                do: format_number(metric(@analytics.result, widget.id).value, fractional_digits: 0)
            }
            trend_value={if ready?, do: trend(metric(@analytics.result, widget.id))}
            trend_value_label={if ready?, do: trend_value_label(metric(@analytics.result, widget.id))}
            trend_type={widget.trend_type}
            trend_label={trend_label(@params["range"], widget.id)}
            selected={@widget.id == widget.id}
            legend_color={widget.color}
            phx_click="select_widget"
            phx_value_widget={widget.id}
          />
        </div>
        <.card_section data-part="analytics-card-chart-section" data-chart-frame="cache">
          <.skeleton_chart :if={!ready?} height="200px" />
          <.chart
            :if={ready?}
            id="symptoms-chart"
            type="bar"
            series={[
              %{
                name: @widget.title,
                type: "bar",
                barMaxWidth: 32,
                color: "var:noora-chart-#{@widget.color}",
                data:
                  Enum.map(metric(@analytics.result, @widget.id).points, fn [time, count] ->
                    [time * 1000, count]
                  end)
              }
            ]}
            labels={[]}
            extra_options={chart_options(@params["range"])}
          />
        </.card_section>
      </.async_card>
      <.card
        id="symptoms-results"
        title={dgettext("dashboard_pulse", "Symptoms")}
        icon="alert_triangle"
      >
        <.card_section data-part="table-section">
          <div data-part="table-toolbar">
            <.form
              id="symptoms-search-form"
              for={%{}}
              phx-change="search"
              phx-submit="search"
              phx-debounce="300"
              autocomplete="off"
              data-part="query-form"
            >
              <div data-part="query-input">
                <.text_input
                  id="symptoms-search"
                  name="search"
                  type="search"
                  value={@params["search"]}
                  placeholder={dgettext("dashboard_pulse", "Search...")}
                  aria-label={dgettext("dashboard_pulse", "Search symptoms")}
                  show_suffix={false}
                />
              </div>
            </.form>
            <.dropdown
              id="symptoms-sort-by"
              label={sort_label(@sort_by)}
              secondary_text={dgettext("dashboard", "Sort by:")}
            >
              <.dropdown_item
                :for={field <- sorts()}
                value={field}
                label={sort_label(field)}
                patch={sort_patch(assigns, field)}
                data-selected={@sort_by == field}
              >
                <:right_icon><.check /></:right_icon>
              </.dropdown_item>
            </.dropdown>
            <.filter_dropdown
              id="symptoms-filter-dropdown"
              label={dgettext("dashboard", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
          </div>
          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <%= cond do %>
            <% @symptoms.failed -> %>
              <.error_state
                id="symptoms-error"
                role="alert"
                title={dgettext("dashboard_pulse", "Symptoms unavailable")}
                subtitle={dgettext("dashboard_pulse", "Refresh the page to try again.")}
              />
            <% !@symptoms.ok? -> %>
              <div data-part="loading"><.skeleton_chart height="200px" /></div>
            <% @symptoms.result.rows == [] -> %>
              <div id="symptoms-empty">
                <.table_empty_state
                  icon="alert_triangle"
                  title={empty_title(assigns)}
                />
              </div>
            <% true -> %>
              <.table
                id="symptoms-table"
                rows={@symptoms.result.rows}
                row_key={&"symptom-#{&1.id}"}
                row_navigate={&symptom_path(assigns, &1)}
              >
                <:col :let={symptom} label={dgettext("dashboard_pulse", "Symptom")}>
                  <div data-part="issue-cell">
                    <div data-part="issue-title">
                      <span data-part="issue-label" title={symptom.title}>
                        {symptom.title || dgettext("dashboard_pulse", "Untitled symptom")}
                      </span>
                    </div>
                    <div data-part="issue-context">
                      <span data-part="issue-culprit" title={symptom.entity_key}>
                        {symptom.entity_key}
                      </span>
                      <span data-part="issue-service">· {symptom.service}</span>
                    </div>
                  </div>
                </:col>
                <:col :let={symptom} label={dgettext("dashboard_pulse", "Status")}>
                  <.badge_cell
                    label={state_label(Atom.to_string(symptom.state))}
                    color={state_color(symptom.state)}
                    style="light-fill"
                  />
                </:col>
                <:col :let={symptom} label={dgettext("dashboard_pulse", "Sources")}>
                  <div
                    data-part="symptom-sources"
                    aria-label={dgettext("dashboard_pulse", "Evidence sources")}
                  >
                    <.badge
                      :for={source <- evidence_sources(symptom)}
                      label={source_label(source)}
                      color={source_color(source)}
                      style="light-fill"
                    />
                  </div>
                </:col>
                <:col
                  :let={symptom}
                  label={sort_label("p_degraded")}
                  patch={sort_patch(assigns, "p_degraded")}
                  sort_order={@sort_by == "p_degraded" && @sort_order}
                >
                  <div
                    data-part="confidence-cell"
                    title={
                      dgettext(
                        "dashboard_pulse",
                        "Estimated probability that this service is degraded, not the percentage of requests affected."
                      )
                    }
                  >
                    <div
                      :if={!is_nil(symptom.p_degraded)}
                      data-part="confidence-meter"
                      role="meter"
                      aria-label={dgettext("dashboard_pulse", "Confidence")}
                      aria-valuemin="0"
                      aria-valuemax="100"
                      aria-valuenow={symptom.p_degraded * 100}
                      aria-valuetext={percent(symptom.p_degraded)}
                    >
                      <span style={"width: #{symptom.p_degraded * 100}%"} />
                    </div>
                    <span>{percent(symptom.p_degraded)}</span>
                  </div>
                </:col>
                <:col
                  :let={symptom}
                  label={sort_label("impact_rate")}
                  patch={sort_patch(assigns, "impact_rate")}
                  sort_order={@sort_by == "impact_rate" && @sort_order}
                >
                  <.text_cell label={
                    if symptom.impact_rate do
                      rate = symptom.impact_rate
                      digits = if rate == trunc(rate), do: 0, else: 1

                      "#{format_number(rate, fractional_digits: digits)} #{impact_unit_label(symptom.impact_unit)}"
                    else
                      "—"
                    end
                  } />
                </:col>
                <:col
                  :let={symptom}
                  label={dgettext("dashboard_pulse", "Activity")}
                  patch={sort_patch(assigns, "revised_at")}
                  sort_order={@sort_by == "revised_at" && @sort_order}
                >
                  <.text_and_description_cell
                    label={
                      dgettext("dashboard_pulse", "Updated %{time}",
                        time: DateFormatter.from_now(symptom.revised_at)
                      )
                    }
                    description={
                      dgettext("dashboard_pulse", "Opened %{time}",
                        time: DateFormatter.from_now(symptom.opened_at)
                      )
                    }
                    title={Calendar.strftime(symptom.revised_at, "%Y-%m-%d %H:%M UTC")}
                  />
                </:col>
              </.table>
          <% end %>
          <nav
            :if={
              @symptoms.ok? &&
                (@symptoms.result.meta.has_previous_page || @symptoms.result.meta.has_next_page)
            }
            class="tuist-pagination"
            aria-label={dgettext("dashboard_pulse", "Symptom pages")}
          >
            <.button
              id="symptoms-previous-page"
              variant="secondary"
              label={dgettext("dashboard", "Prev")}
              disabled={!@symptoms.result.meta.has_previous_page}
              patch={
                symptoms_path(assigns, %{
                  "page" => min(@symptoms.result.meta.page - 1, @symptoms.result.meta.total_pages)
                })
              }
            >
              <:icon_left><.chevron_left /></:icon_left>
            </.button>
            <.button
              id="symptoms-next-page"
              variant="secondary"
              label={dgettext("dashboard", "Next")}
              disabled={!@symptoms.result.meta.has_next_page}
              patch={symptoms_path(assigns, %{"page" => @symptoms.result.meta.page + 1})}
            >
              <:icon_right><.chevron_right /></:icon_right>
            </.button>
          </nav>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp symptoms_path(assigns, changes) do
    params =
      assigns.params
      |> Map.merge(changes)
      |> Map.reject(fn {_, v} -> v in [nil, ""] end)

    ~p"/#{assigns.selected_account.name}/pulse?#{params}"
  end

  defp symptom_path(assigns, symptom), do: ~p"/#{assigns.selected_account.name}/pulse/symptoms/#{symptom.id}"

  defp metric(analytics, id), do: Enum.find(analytics.widgets, &(&1.id == id))

  defp trend(%{value: current, previous_value: previous}) do
    if previous == 0, do: current * 1.0, else: (current - previous) / previous * 100
  end

  # A percentage of a zero baseline is undefined; show the absolute change.
  defp trend_value_label(%{value: value, previous_value: 0}) when value > 0, do: "+#{value}"
  defp trend_value_label(_metric), do: nil

  defp evidence_sources(%{phenomena: phenomena}) do
    phenomena
    |> Enum.flat_map(&Map.get(&1, "sources", []))
    |> Enum.map(&(&1 |> String.split(".", parts: 2) |> hd()))
    |> Enum.uniq()
    |> Enum.filter(&(&1 in ~w(metric log trace error probe k8s deploy presence)))
    |> Enum.sort()
  end

  defp source_label("metric"), do: dgettext("dashboard_pulse", "Metrics")
  defp source_label("log"), do: dgettext("dashboard_pulse", "Logs")
  defp source_label("trace"), do: dgettext("dashboard_pulse", "Traces")
  defp source_label("error"), do: dgettext("dashboard_pulse", "Errors")
  defp source_label("probe"), do: dgettext("dashboard_pulse", "Probes")
  defp source_label("k8s"), do: dgettext("dashboard_pulse", "Kubernetes events")
  defp source_label("deploy"), do: dgettext("dashboard_pulse", "Deployments")
  defp source_label("presence"), do: dgettext("dashboard_pulse", "Telemetry health")

  defp source_color("metric"), do: "focus"
  defp source_color("trace"), do: "primary"
  defp source_color("log"), do: "information"
  defp source_color("error"), do: "secondary"
  defp source_color(_), do: "neutral"

  defp percent(nil), do: "—"
  defp percent(probability), do: "#{format_number(probability * 100, fractional_digits: 0)}%"

  @doc false
  def impact_unit_label("failed_requests_per_min"), do: dgettext("dashboard_pulse", "failed requests/min")
  def impact_unit_label("stuck_jobs_per_min"), do: dgettext("dashboard_pulse", "stuck jobs/min")
  def impact_unit_label("affected_users_per_min"), do: dgettext("dashboard_pulse", "affected users/min")
  def impact_unit_label(nil), do: nil
  def impact_unit_label(other), do: String.replace(other, "_", " ")

  @doc false
  def phenomenon_label("request_errors"), do: dgettext("dashboard_pulse", "Request errors")
  def phenomenon_label("latency"), do: dgettext("dashboard_pulse", "Latency")
  def phenomenon_label("saturation"), do: dgettext("dashboard_pulse", "Saturation")
  def phenomenon_label("availability"), do: dgettext("dashboard_pulse", "Availability")
  def phenomenon_label("platform_events"), do: dgettext("dashboard_pulse", "Platform events")
  def phenomenon_label("novelty"), do: dgettext("dashboard_pulse", "Novelty")
  def phenomenon_label(other), do: other

  @doc false
  def tier_label(:page), do: dgettext("dashboard_pulse", "Page")
  def tier_label(:board), do: dgettext("dashboard_pulse", "Board")
  def tier_label(_), do: dgettext("dashboard_pulse", "Audit")

  @doc false
  def tier_color(:page), do: "destructive"
  def tier_color(:board), do: "warning"
  def tier_color(_), do: "neutral"

  @doc false
  def state_label("open"), do: dgettext("dashboard_pulse", "Open")
  def state_label("merged"), do: dgettext("dashboard_pulse", "Merged")
  def state_label(_), do: dgettext("dashboard_pulse", "Resolved")

  @doc false
  def state_color(:open), do: "warning"
  def state_color(:merged), do: "neutral"
  def state_color(_), do: "success"

  defp empty_title(%{symptoms: %{result: %{meta: %{page: page}}}}) when page > 1,
    do: dgettext("dashboard_pulse", "No symptoms on this page.")

  defp empty_title(%{active_filters: [], params: params}) when not is_map_key(params, "search"),
    do: dgettext("dashboard_pulse", "Nothing has needed investigation yet.")

  defp empty_title(_assigns), do: dgettext("dashboard_pulse", "No symptoms match these filters.")

  defp sorts, do: @sorts

  defp sort_label("opened_at"), do: dgettext("dashboard_pulse", "Opened")
  defp sort_label("p_degraded"), do: dgettext("dashboard_pulse", "Confidence")
  defp sort_label("impact_rate"), do: dgettext("dashboard_pulse", "Observation")
  defp sort_label(_), do: dgettext("dashboard_pulse", "Updated")

  defp sort_patch(assigns, field) do
    order = if assigns.sort_by == field and assigns.sort_order == "desc", do: "asc", else: "desc"
    symptoms_path(assigns, %{"sort_by" => field, "sort_order" => order, "page" => nil})
  end

  # A URL can carry anything; keep what the table can show, so a bad link
  # lands on a working page instead of an error.
  defp normalize(params, filters) do
    params =
      case Integer.parse(params["page"] || "") do
        {page, ""} when page in 1..100_000 -> params
        _ -> Map.delete(params, "page")
      end

    params = if params["search"], do: Map.update!(params, "search", &String.slice(&1, 0, 1024)), else: params

    Enum.reduce(filters, params, fn filter, params ->
      value = params["filter_#{filter.id}_val"]

      if is_nil(value) or value in filter.options,
        do: params,
        else: Map.drop(params, ["filter_#{filter.id}_op", "filter_#{filter.id}_val"])
    end)
  end

  defp list_inputs(assigns) do
    Enum.reduce(assigns.active_filters, Map.take(assigns.params, ~w(search sort_by sort_order page)), fn
      %{value: value}, inputs when value in [nil, ""] -> inputs
      filter, inputs -> Map.put(inputs, filter.id, to_string(filter.value))
    end)
  end

  defp define_filters do
    [
      option_filter("state", dgettext("dashboard_pulse", "Status"), ~w(open resolved merged), &state_label/1),
      option_filter(
        "tier",
        dgettext("dashboard_pulse", "Tier"),
        ~w(page board audit),
        &tier_label(String.to_existing_atom(&1))
      ),
      option_filter("phenomenon", dgettext("dashboard_pulse", "Phenomenon"), Symptoms.phenomena(), &phenomenon_label/1)
    ]
  end

  defp option_filter(id, name, options, label) do
    %Filter.Filter{
      id: id,
      field: id,
      display_name: name,
      type: :option,
      options: options,
      options_display_names: Map.new(options, &{&1, label.(&1)}),
      operator: :==,
      value: nil
    }
  end

  defp range_label("24h"), do: dgettext("dashboard_pulse", "Last 24 hours")
  defp range_label("30d"), do: dgettext("dashboard_pulse", "Last 30 days")
  defp range_label(_), do: dgettext("dashboard_pulse", "Last 7 days")

  defp trend_label("24h", "open"), do: dgettext("dashboard_pulse", "vs 24 hours ago")
  defp trend_label("30d", "open"), do: dgettext("dashboard_pulse", "vs 30 days ago")
  defp trend_label(_, "open"), do: dgettext("dashboard_pulse", "vs 7 days ago")
  defp trend_label("24h", _), do: dgettext("dashboard_pulse", "vs previous 24 hours")
  defp trend_label("30d", _), do: dgettext("dashboard_pulse", "vs previous 30 days")
  defp trend_label(_, _), do: dgettext("dashboard_pulse", "vs previous 7 days")

  defp widgets,
    do: [
      %{
        id: "opened",
        title: dgettext("dashboard_pulse", "Symptoms opened"),
        color: "primary",
        trend_type: :inverse,
        description:
          dgettext(
            "dashboard_pulse",
            "Times symptoms opened or reopened in the selected period, from the evaluator's revisions."
          )
      },
      %{
        id: "resolved",
        title: dgettext("dashboard_pulse", "Symptoms resolved"),
        color: "secondary",
        trend_type: :regular,
        description:
          dgettext("dashboard_pulse", "Times symptoms resolved in the selected period, after several quiet windows.")
      },
      %{
        id: "open",
        title: dgettext("dashboard_pulse", "Open symptoms"),
        color: "tertiary",
        trend_type: :inverse,
        description:
          dgettext(
            "dashboard_pulse",
            "Symptoms open now, compared with the start of the period. The chart shows how many were open at the end of each hour or day."
          )
      }
    ]

  defp chart_options(range) do
    %{
      grid: %{left: 8, right: 16, top: 12, bottom: 24, containLabel: true},
      legend: %{show: false},
      xAxis: %{
        type: "time",
        boundaryGap: ["2%", "2%"],
        splitNumber: 4,
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          hideOverlap: true,
          formatter: if(range == "24h", do: "fn:toLocaleDateHour", else: "fn:toLocaleDate")
        }
      },
      yAxis: %{
        min: 0,
        minInterval: 1,
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatNumber"},
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}
      },
      tooltip: %{trigger: "axis", valueFormat: "fn:formatNumber"}
    }
  end
end
