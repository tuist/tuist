defmodule AtlasWeb.AcquisitionLive do
  @moduledoc """
  Tuist's acquisition funnel per source and campaign: landings from campaign
  links, signups and paying customers. See `Atlas.TuistAcquisition`.
  """
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.Components.EmptyCardSection
  import AtlasWeb.Components.Skeleton
  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.Widget

  alias Atlas.TuistAcquisition
  alias Atlas.TuistOverview
  alias AtlasWeb.AcquisitionLive.Tables
  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Socket

  @widgets ~w(landings signups attributed_signups customers)
  @max_days 366
  @default_widget "landings"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Acquisition"))}
  end

  def handle_params(params, uri, socket) do
    {preset, {start_date, end_date}} = window_from_params(params)
    source = normalize_source(params["source"])
    campaign = if socket.assigns.live_action == :campaign, do: params["campaign"]

    changed? =
      Map.get(socket.assigns, :start_date) != start_date or Map.get(socket.assigns, :end_date) != end_date or
        Map.get(socket.assigns, :source, :unset) != source or Map.get(socket.assigns, :campaign, :unset) != campaign

    socket =
      socket
      |> assign(:page_title, if(campaign, do: campaign, else: gettext("Acquisition")))
      |> assign(:campaign, campaign)
      |> assign(:query_params, uri |> URI.parse() |> Map.get(:query) |> Kernel.||("") |> URI.decode_query())
      |> assign(:selected_preset, preset)
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> assign(:source, source)
      |> assign(:date_range_period, {date_start_of(start_date), date_end_of(end_date)})
      |> assign(:selected_widget, normalize_widget(params["widget"]))
      |> assign(:trend_label, trend_label(start_date, end_date))

    socket =
      if changed? do
        socket
        |> assign(:funnel, AsyncResult.loading())
        |> start_async(:funnel, fn ->
          TuistAcquisition.funnel({start_date, end_date}, source: source, campaign: campaign)
        end)
      else
        socket
      end

    {:noreply, assign_tables(socket)}
  end

  def handle_async(:funnel, {:ok, result}, socket) do
    {:noreply, socket |> assign(:funnel, AsyncResult.ok(socket.assigns.funnel, result)) |> assign_tables()}
  end

  def handle_async(:funnel, {:exit, reason}, socket) do
    {:noreply, assign(socket, :funnel, AsyncResult.failed(socket.assigns.funnel, {:exit, reason}))}
  end

  def handle_event(
        "range_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    range =
      if preset == "custom",
        do: %{"range" => "custom", "start" => start_date, "end" => end_date},
        else: %{"range" => preset, "start" => nil, "end" => nil}

    {:noreply, push_patch(socket, to: page_path(socket, range))}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch(socket, to: page_path(socket, %{"widget" => widget}))}
  end

  def handle_event("search_table", %{"table_search" => %{"table" => table, "query" => query}}, socket)
      when table in ["campaigns", "channels", "subscriptions"] and is_binary(query) do
    query = query |> String.trim() |> String.slice(0, 120)
    {:noreply, push_patch(socket, to: page_path(socket, %{(table <> "_q") => query}), replace: true)}
  end

  def handle_event("add_filter", %{"value" => id}, socket) do
    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) do
      params = Filter.Operations.add_filter_to_query(id, socket, socket.assigns.query_params)

      {:noreply,
       socket
       |> push_patch(to: page_path(socket, params, replace: true))
       |> push_event("open-dropdown", %{id: "filter-#{id}-value-dropdown"})
       |> push_event("open-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", %{"payload_filter_id" => id} = params, socket) do
    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) do
      query = Filter.Operations.update_filters_in_query(params, socket, socket.assigns.query_params)

      {:noreply,
       socket
       |> push_patch(to: page_path(socket, query, replace: true))
       |> push_event("close-dropdown", %{id: "all", all: true})
       |> push_event("close-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  # Noora's filter events look filters up in `available_filters`; every table's
  # are there under their table prefix.
  defp assign_tables(socket) do
    data = if ready?(socket.assigns.funnel), do: funnel(socket.assigns.funnel)

    socket
    |> assign(:available_filters, Tables.available_filters(data))
    |> assign(:tables, Map.new(Tables.tables(), &{&1, Tables.state(&1, socket.assigns.query_params, data)}))
  end

  def render(assigns) do
    ~H"""
    <div id="acquisition" data-campaign={@campaign}>
      <div :if={@campaign} data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="acquisition-breadcrumb-overview"
              label={gettext("Acquisition")}
              phx-click={JS.patch(campaign_back_path(assigns))}
            />
            <.breadcrumb id="acquisition-breadcrumb-campaign" label={@campaign} />
          </.breadcrumbs>
          <h1 id="acquisition-campaign-title" data-part="title">{@campaign}</h1>
          <p :if={campaign_description(@funnel)} data-part="description">
            {campaign_description(@funnel)}
          </p>
        </div>
        <div data-part="header-actions">
          {render_filters(assigns)}
        </div>
      </div>
      <div :if={!@campaign} data-part="analytics-filters">
        {render_filters(assigns)}
      </div>
      <.card
        id="acquisition-funnel"
        title={gettext("Funnel")}
        icon="chart_arcs"
        data-part="funnel-card"
      >
        <div data-part="analytics-content">
          <div data-part="widgets">
            <.widget
              :for={widget <- widgets()}
              id={"acquisition-widget-#{String.replace(widget, "_", "-")}"}
              variant="analytics"
              title={widget_title(widget)}
              tooltip_description={widget_description(widget)}
              legend_color={legend_color(widget)}
              value={
                if ready?(@funnel),
                  do:
                    format_count(Map.fetch!(funnel(@funnel).totals, String.to_existing_atom(widget)))
              }
              loading={loading?(@funnel)}
              empty={!loading?(@funnel) && !ready?(@funnel)}
              empty_label={unavailable_label(@funnel)}
              trend_value={if ready?(@funnel), do: trend(funnel(@funnel), widget)}
              trend_label={@trend_label}
              phx_click="select_widget"
              phx_value_widget={widget}
              selected={@selected_widget == widget}
            />
          </div>
          {render_chart(assigns)}
        </div>
      </.card>

      <.card
        :if={@campaign}
        id="acquisition-effectiveness"
        title={gettext("Effectiveness")}
        icon="chart_dots"
        data-part="effectiveness-card"
      >
        <.card_section>
          {render_effectiveness(assigns)}
        </.card_section>
      </.card>

      <.card :if={!@campaign} title={gettext("Campaigns")} icon="stack_2" data-part="campaigns-card">
        <.card_section data-part="table-section">
          {render_campaigns(assigns)}
        </.card_section>
      </.card>

      <.card
        title={if @campaign, do: gettext("Sources and ads"), else: gettext("Channels")}
        icon="world"
        data-part="channels-card"
      >
        <.card_section data-part="table-section">
          {render_channels(assigns)}
        </.card_section>
      </.card>

      <.card title={gettext("Subscriptions")} icon="credit_card" data-part="subscriptions-card">
        <.card_section data-part="table-section">
          {render_subscriptions(assigns)}
        </.card_section>
      </.card>
    </div>
    """
  end

  defp render_filters(assigns) do
    ~H"""
    <.dropdown
      id="acquisition-source"
      label={if @source, do: source_label(@source), else: gettext("Any")}
      secondary_text={gettext("Source:")}
    >
      <.dropdown_item
        :for={source <- [nil | source_choices(@funnel, @source)]}
        value={source || "any"}
        label={if source, do: source, else: gettext("Any")}
        patch={page_path(assigns, %{"source" => source})}
        data-selected={@source == source}
      >
        <:right_icon :if={@source == source}><.check /></:right_icon>
      </.dropdown_item>
    </.dropdown>
    <.date_picker
      id="acquisition-date-range-picker"
      name="acquisition-date-range"
      presets={date_picker_presets()}
      selected_preset={@selected_preset}
      period={@date_range_period}
      on_period_change="range_changed"
      max={Date.utc_today()}
    >
      <:actions>
        <.button
          label={gettext("Cancel")}
          variant="secondary"
          phx-click={
            JS.dispatch("phx:date-picker-cancel", detail: %{id: "acquisition-date-range-picker"})
          }
        />
        <.button
          label={gettext("Apply")}
          phx-click={
            JS.dispatch("phx:date-picker-apply", detail: %{id: "acquisition-date-range-picker"})
          }
        />
      </:actions>
    </.date_picker>
    """
  end

  defp campaign_description(funnel) do
    if ready?(funnel) do
      case funnel(funnel).sources do
        [] -> nil
        sources -> gettext("Sources: %{sources}", sources: Enum.join(sources, ", "))
      end
    end
  end

  defp render_chart(assigns) do
    cond do
      loading?(assigns.funnel) ->
        ~H"""
        <.card_section data-chart-frame="compact">
          <div data-part="analytics-chart"><.skeleton_chart height="200px" /></div>
        </.card_section>
        """

      ready?(assigns.funnel) and
          Enum.any?(selected_points(assigns), fn {_date, value} -> value > 0 end) ->
        points = selected_points(assigns)
        dates = Enum.map(points, fn {date, _value} -> Date.to_iso8601(date) end)

        assigns =
          assigns
          |> assign(:dates, dates)
          |> assign(:values, Enum.map(points, &elem(&1, 1)))
          |> assign(
            :chart_dom_id,
            Enum.join([assigns.selected_widget, assigns.source || "all", List.first(dates), List.last(dates)], "-")
          )

        ~H"""
        <.card_section data-chart-frame="compact">
          <div data-part="analytics-chart" id={"acquisition-chart-wrapper-#{@chart_dom_id}"}>
            <.chart
              id={"acquisition-chart-#{@chart_dom_id}"}
              data-part="funnel-chart"
              type="line"
              labels={@dates}
              series={[
                %{
                  name: widget_title(@selected_widget),
                  data: @values,
                  color: "var:noora-chart-#{legend_color(@selected_widget)}",
                  type: "line",
                  smooth: 0.1,
                  symbol: "none"
                }
              ]}
              extra_options={chart_options(@dates, funnel(@funnel).granularity)}
              y_axis_min={0}
              show_legend={false}
            />
          </div>
        </.card_section>
        """

      true ->
        assigns = assign(assigns, :empty_title, empty_chart_title(assigns.funnel))

        ~H"""
        <.empty_card_section id="acquisition-chart-empty" title={@empty_title} data-chart-frame="compact">
          <:image>
            <img
              src="/images/empty_line_chart_light.png"
              data-theme="light"
              loading="lazy"
              decoding="async"
              alt=""
            />
            <img
              src="/images/empty_line_chart_dark.png"
              data-theme="dark"
              loading="lazy"
              decoding="async"
              alt=""
            />
          </:image>
        </.empty_card_section>
        """
    end
  end

  defp render_channels(assigns) do
    cond do
      loading?(assigns.funnel) ->
        ~H"""
        <div data-part="channels-skeleton">
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
        </div>
        """

      ready?(assigns.funnel) ->
        state = assigns.tables["channels"]
        path = fn changes -> page_path(assigns, changes) end

        assigns =
          assigns
          |> assign(:state, state)
          |> assign(:path, path)
          |> assign(:rows, funnel(assigns.funnel).channels |> Tables.apply(state) |> Enum.with_index())
          |> assign(:row_navigate, fn {channel, _index} -> channel_path(assigns, channel) end)

        ~H"""
        <Tables.toolbar state={@state} path={@path} />
        <.table
          id="acquisition-channels-table"
          rows={@rows}
          row_key={fn {_channel, index} -> "channel-#{index}" end}
          row_navigate={@row_navigate}
        >
          <:col :let={{channel, _index}} label={gettext("Source")}>
            <.text_and_description_cell label={source_label(channel.source)} description={channel.medium} />
          </:col>
          <:col :let={{channel, _index}} label={gettext("Campaign")}>
            <.text_cell label={blank_dash(channel.campaign)} />
          </:col>
          <:col :let={{channel, _index}} label={gettext("Ad")}>
            <.text_cell label={blank_dash(channel.content)} />
          </:col>
          <:col
            :let={{channel, _index}}
            label={gettext("Landings")}
            patch={@state |> Tables.column_sort("landings", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("landings", @path) |> elem(1)}
          >
            <.text_cell label={format_count(channel.landings)} />
          </:col>
          <:col
            :let={{channel, _index}}
            label={gettext("Signups")}
            patch={@state |> Tables.column_sort("signups", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("signups", @path) |> elem(1)}
          >
            <.text_cell
              label={format_count(channel.signups)}
              sublabel={rate(channel.signups, channel.landings)}
            />
          </:col>
          <:col
            :let={{channel, _index}}
            label={gettext("Customers")}
            patch={@state |> Tables.column_sort("customers", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("customers", @path) |> elem(1)}
          >
            <.text_cell
              label={format_count(channel.customers)}
              sublabel={rate(channel.customers, channel.signups)}
            />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="world"
              title={gettext("No matching landings or signups")}
              subtitle={
                gettext(
                  "Visits from links tagged with utm_source (or ref) and signups that came from them show up here."
                )
              }
            />
          </:empty_state>
        </.table>
        """

      true ->
        ~H"""
        <.table id="acquisition-channels-table" rows={[]}>
          <:col label={gettext("Source")}></:col>
          <:col label={gettext("Campaign")}></:col>
          <:col label={gettext("Ad")}></:col>
          <:col label={gettext("Landings")}></:col>
          <:col label={gettext("Signups")}></:col>
          <:col label={gettext("Customers")}></:col>
          <:empty_state>
            <.table_empty_state
              icon="world"
              title={unavailable_label(@funnel)}
              subtitle={unavailable_subtitle(@funnel)}
            />
          </:empty_state>
        </.table>
        """
    end
  end

  defp render_campaigns(assigns) do
    cond do
      loading?(assigns.funnel) ->
        ~H"""
        <div data-part="channels-skeleton">
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
        </div>
        """

      ready?(assigns.funnel) ->
        state = assigns.tables["campaigns"]

        assigns =
          assigns
          |> assign(:state, state)
          |> assign(:path, fn changes -> page_path(assigns, changes) end)
          |> assign(:rows, funnel(assigns.funnel).campaigns |> Tables.apply(state) |> Enum.with_index())

        ~H"""
        <Tables.toolbar state={@state} path={@path} />
        <.table
          id="acquisition-campaigns-table"
          rows={@rows}
          row_key={fn {campaign, _index} -> "campaign-#{campaign.campaign}" end}
          row_navigate={fn {campaign, _index} -> campaign_path(assigns, campaign.campaign) end}
        >
          <:col :let={{campaign, _index}} label={gettext("Campaign")}>
            <.text_and_description_cell
              label={campaign.campaign}
              description={Enum.join(campaign.sources, ", ")}
            />
          </:col>
          <:col :let={{campaign, _index}} label={gettext("Ads")}>
            <.text_cell label={if campaign.ads == [], do: "–", else: format_count(length(campaign.ads))} />
          </:col>
          <:col
            :let={{campaign, _index}}
            label={gettext("Landings")}
            patch={@state |> Tables.column_sort("landings", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("landings", @path) |> elem(1)}
          >
            <.text_cell label={format_count(campaign.landings)} />
          </:col>
          <:col
            :let={{campaign, _index}}
            label={gettext("Signups")}
            patch={@state |> Tables.column_sort("signups", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("signups", @path) |> elem(1)}
          >
            <.text_cell
              label={format_count(campaign.signups)}
              sublabel={rate(campaign.signups, campaign.landings)}
            />
          </:col>
          <:col
            :let={{campaign, _index}}
            label={gettext("Customers")}
            patch={@state |> Tables.column_sort("customers", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("customers", @path) |> elem(1)}
          >
            <.text_cell
              label={format_count(campaign.customers)}
              sublabel={rate(campaign.customers, campaign.signups)}
            />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="stack_2"
              title={gettext("No matching campaigns")}
              subtitle={gettext("Links tagged with utm_campaign show up here, each with its own page.")}
            />
          </:empty_state>
        </.table>
        """

      true ->
        ~H"""
        <.table id="acquisition-campaigns-table" rows={[]}>
          <:col label={gettext("Campaign")}></:col>
          <:col label={gettext("Landings")}></:col>
          <:col label={gettext("Signups")}></:col>
          <:col label={gettext("Customers")}></:col>
          <:empty_state>
            <.table_empty_state
              icon="stack_2"
              title={unavailable_label(@funnel)}
              subtitle={unavailable_subtitle(@funnel)}
            />
          </:empty_state>
        </.table>
        """
    end
  end

  defp render_effectiveness(assigns) do
    if ready?(assigns.funnel) do
      assigns = assign(assigns, :effectiveness, funnel(assigns.funnel).effectiveness)

      ~H"""
      <dl data-part="details">
        <div
          :for={{id, label, value} <- effectiveness_items(@effectiveness)}
          data-part="detail"
          id={"acquisition-effectiveness-#{id}"}
        >
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      </dl>
      """
    else
      ~H"""
      <div data-part="channels-skeleton">
        <.skeleton_box width="100%" height="64px" border_radius="8px" />
      </div>
      """
    end
  end

  defp effectiveness_items(e) do
    [
      {"signup-rate", gettext("Signup rate"), percent(e.signup_rate)},
      {"customer-rate", gettext("Customer rate"), percent(e.customer_rate)},
      {"landings-per-customer", gettext("Landings per customer"), number(e.landings_per_customer)},
      {"days-to-subscribe", gettext("Median days to subscribe"), number(e.median_days_to_subscribe)},
      {"top-source", gettext("Top source"), e.top_source || "–"},
      {"top-ad", gettext("Top ad"), e.top_ad || "–"},
      {"plans", gettext("Plans"), plans(e.plans)},
      {"active", gettext("Active"), active_range(e.first_active_on, e.last_active_on)}
    ]
  end

  defp percent(nil), do: "–"
  defp percent(value), do: "#{Float.round(value * 100, 1)}%"

  defp number(nil), do: "–"
  defp number(value) when is_integer(value), do: Integer.to_string(value)
  defp number(value), do: value |> Float.round(1) |> Float.to_string() |> String.replace_suffix(".0", "")

  defp plans(plans) when plans == %{}, do: "–"

  defp plans(plans),
    do: plans |> Enum.sort() |> Enum.map_join(", ", fn {plan, count} -> "#{count} #{plan_label(plan)}" end)

  defp active_range(nil, _last), do: "–"
  defp active_range(first, first), do: format_date(first)
  defp active_range(first, last), do: "#{format_date(first)} – #{format_date(last)}"

  defp channel_path(assigns, %{campaign: campaign}) when campaign != "" and is_nil(assigns.campaign),
    do: campaign_path(assigns, campaign)

  defp channel_path(_assigns, %{source: ""}), do: nil

  defp channel_path(assigns, %{source: source}),
    do: page_path(assigns, %{"source" => source}, replace: true, keep_range: true)

  defp campaign_path(assigns, campaign),
    do: ~p"/commercial/gtm/acquisition/campaigns/#{campaign}" <> range_query(assigns)

  defp campaign_back_path(assigns), do: ~p"/commercial/gtm/acquisition" <> range_query(assigns)

  defp range_query(assigns) do
    case Map.take(assigns.query_params, ~w(range start end)) do
      query when query == %{} -> ""
      query -> "?" <> URI.encode_query(query)
    end
  end

  defp render_subscriptions(assigns) do
    cond do
      loading?(assigns.funnel) ->
        ~H"""
        <div data-part="channels-skeleton">
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
          <.skeleton_box width="100%" height="44px" border_radius="8px" />
        </div>
        """

      ready?(assigns.funnel) ->
        state = assigns.tables["subscriptions"]

        assigns =
          assigns
          |> assign(:state, state)
          |> assign(:path, fn changes -> page_path(assigns, changes) end)
          |> assign(
            :page,
            funnel(assigns.funnel).subscriptions |> Tables.apply(state) |> Tables.paginate(state.page)
          )
          |> then(&assign(&1, :rows, Enum.with_index(&1.page.rows)))

        ~H"""
        <Tables.toolbar state={@state} path={@path} />
        <.table
          id="acquisition-subscriptions-table"
          rows={@rows}
          row_key={fn {_subscription, index} -> "subscription-#{index}" end}
        >
          <:col :let={{subscription, _index}} label={gettext("Account")}>
            <.text_and_description_cell
              label={subscription.account}
              description={gettext("Signed up %{date}", date: format_date(subscription.signed_up_on))}
            />
          </:col>
          <:col :let={{subscription, _index}} label={gettext("Plan")}>
            <.badge_cell
              label={plan_label(subscription.plan)}
              color={if subscription.plan == "enterprise", do: "primary", else: "information"}
              style="light-fill"
            />
          </:col>
          <:col :let={{subscription, _index}} label={gettext("Status")}>
            <.status_badge_cell
              label={status_label(subscription.status)}
              status={if subscription.status == "active", do: "success", else: "attention"}
            />
          </:col>
          <:col
            :let={{subscription, _index}}
            label={gettext("Subscribed")}
            patch={@state |> Tables.column_sort("subscribed_on", @path) |> elem(0)}
            sort_order={@state |> Tables.column_sort("subscribed_on", @path) |> elem(1)}
          >
            <.text_cell label={format_date(subscription.subscribed_on)} />
          </:col>
          <:col :let={{subscription, _index}} label={gettext("Source")}>
            <.text_and_description_cell
              label={source_label(subscription.source)}
              description={subscription.medium}
            />
          </:col>
          <:col :let={{subscription, _index}} label={gettext("Campaign")}>
            <.text_cell label={blank_dash(subscription.campaign)} />
          </:col>
          <:col :let={{subscription, _index}} label={gettext("Ad")}>
            <.text_cell label={blank_dash(subscription.content)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="credit_card"
              title={gettext("No matching paying subscriptions")}
              subtitle={
                gettext(
                  "Pro and Enterprise subscriptions of the range's signups show up here with their ad."
                )
              }
            />
          </:empty_state>
        </.table>
        <.pagination_group
          :if={@page.total_pages > 1}
          id="acquisition-subscriptions-pagination"
          current_page={@page.number}
          number_of_pages={@page.total_pages}
          page_patch={fn page -> @path.(%{"subscriptions_page" => to_string(page)}) end}
        />
        """

      true ->
        ~H"""
        <.table id="acquisition-subscriptions-table" rows={[]}>
          <:col label={gettext("Account")}></:col>
          <:col label={gettext("Plan")}></:col>
          <:col label={gettext("Source")}></:col>
          <:col label={gettext("Ad")}></:col>
          <:empty_state>
            <.table_empty_state
              icon="credit_card"
              title={unavailable_label(@funnel)}
              subtitle={unavailable_subtitle(@funnel)}
            />
          </:empty_state>
        </.table>
        """
    end
  end

  defp plan_label("enterprise"), do: gettext("Enterprise")
  defp plan_label(_plan), do: gettext("Pro")

  defp status_label("past_due"), do: gettext("Past due")
  defp status_label(_status), do: gettext("Active")

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  defp format_date(_date), do: "–"

  defp widgets, do: @widgets

  defp loading?(%AsyncResult{loading: loading}), do: not is_nil(loading)
  defp ready?(%AsyncResult{ok?: true, result: {:ok, _funnel}} = result), do: not loading?(result)
  defp ready?(_funnel), do: false
  defp funnel(%AsyncResult{result: {:ok, funnel}}), do: funnel

  defp selected_points(assigns),
    do: Map.fetch!(funnel(assigns.funnel).series, String.to_existing_atom(assigns.selected_widget))

  # The filtered source stays listed even when the window has no rows for it.
  defp source_choices(funnel, selected) do
    sources = if ready?(funnel), do: funnel(funnel).sources, else: []
    if selected && selected not in sources, do: Enum.sort([selected | sources]), else: sources
  end

  defp trend(%{totals: totals, previous: previous}, widget) do
    key = String.to_existing_atom(widget)

    case Map.fetch!(previous, key) do
      0 -> nil
      before -> (Map.fetch!(totals, key) - before) / before * 100
    end
  end

  defp trend_label(start_date, end_date),
    do: gettext("vs previous %{days} days", days: Date.diff(end_date, start_date) + 1)

  defp empty_chart_title(funnel) do
    if ready?(funnel), do: gettext("No data in this range"), else: unavailable_label(funnel)
  end

  defp unavailable_subtitle(%AsyncResult{ok?: true, result: {:error, :not_configured}}),
    do: gettext("Atlas reads the funnel from the Tuist server, which is not reachable from this environment.")

  defp unavailable_subtitle(_funnel), do: gettext("The Tuist server could not measure the funnel. Try again later.")

  defp unavailable_label(%AsyncResult{ok?: true, result: {:error, :not_configured}}), do: gettext("Not connected")
  defp unavailable_label(_funnel), do: gettext("Unavailable")

  defp widget_title("landings"), do: gettext("Campaign landings")
  defp widget_title("signups"), do: gettext("Signups")
  defp widget_title("attributed_signups"), do: gettext("Attributed signups")
  defp widget_title("customers"), do: gettext("Customers")

  defp widget_description("landings"),
    do: gettext("Visits that arrived from a link tagged with utm_source (or ref) on another site.")

  defp widget_description("signups"),
    do:
      gettext(
        "People who signed up on their own in the selected range, attributed or not. Teammates joining an existing organization don't count."
      )

  defp widget_description("attributed_signups"),
    do:
      gettext(
        "Signups whose visit to the sign-up page carried a campaign, or came from another site. The first touch counts."
      )

  defp widget_description("customers"),
    do:
      gettext(
        "Signups from the selected range whose account, or an organization they administer, now pays for Pro or Enterprise."
      )

  defp legend_color("landings"), do: "primary"
  defp legend_color("signups"), do: "secondary"
  defp legend_color("attributed_signups"), do: "quaternary"
  defp legend_color("customers"), do: "tertiary"

  defp source_label(""), do: gettext("Direct or unknown")
  defp source_label(source), do: source

  defp blank_dash(""), do: "–"
  defp blank_dash(value), do: value

  defp rate(_count, 0), do: nil
  defp rate(count, total), do: "#{Float.round(count / total * 100, 1)}%"

  defp chart_options(dates, granularity) do
    format = "{value}"

    %{
      grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
      legend: %{show: false},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:atlasUTCDate",
          interval: 0,
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        minInterval: 1,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{formatter: format, color: "var:noora-surface-label-secondary"}
      },
      tooltip: %{valueFormat: format, dateFormat: if(granularity == :month, do: "month", else: "day")}
    }
  end

  defp date_picker_presets do
    Enum.map(TuistOverview.presets(), fn preset ->
      %{id: preset.id, label: preset.label, period: {preset.days, :day}}
    end) ++ [%{id: "custom", label: gettext("Custom")}]
  end

  # A custom range spans at most a year, as in the MCP tool: every query
  # also reads the equally long range before it.
  defp window_from_params(%{"range" => "custom", "start" => start_iso, "end" => end_iso}) do
    with {:ok, start_date} <- parse_date(start_iso),
         {:ok, end_date} <- parse_date(end_iso),
         true <- Date.compare(end_date, start_date) != :lt do
      {"custom", {Enum.max([start_date, Date.add(end_date, -(@max_days - 1))], Date), end_date}}
    else
      _other -> default_window()
    end
  end

  defp window_from_params(%{"range" => preset}) when is_binary(preset) do
    case TuistOverview.preset(preset) do
      %{id: id, days: days} -> {id, window_for_days(days)}
      nil -> default_window()
    end
  end

  defp window_from_params(_params), do: default_window()

  defp default_window do
    preset = TuistOverview.default_preset()
    %{days: days} = TuistOverview.preset(preset)
    {preset, window_for_days(days)}
  end

  defp window_for_days(days) do
    today = Date.utc_today()
    {Date.add(today, -(days - 1)), today}
  end

  defp parse_date(value) when is_binary(value), do: value |> String.slice(0, 10) |> Date.from_iso8601()
  defp parse_date(_value), do: :error

  defp normalize_widget(value) when value in @widgets, do: value
  defp normalize_widget(_value), do: @default_widget

  defp normalize_source(source) when is_binary(source) and source != "", do: source
  defp normalize_source(_source), do: nil

  # The page's path and query with `changes` applied; a nil or empty value
  # removes its key. `replace: true` replaces the whole query with `changes`.
  defp page_path(socket_or_assigns, changes, opts \\ [])
  defp page_path(%Socket{assigns: assigns}, changes, opts), do: page_path(assigns, changes, opts)

  defp page_path(assigns, changes, opts) do
    base =
      cond do
        opts[:keep_range] -> Map.take(assigns.query_params, ~w(range start end))
        opts[:replace] -> %{}
        true -> assigns.query_params
      end

    query =
      base
      |> Map.merge(changes)
      |> reset_pages(assigns.query_params, changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    base_path(assigns.campaign) <> if(query == %{}, do: "", else: "?" <> URI.encode_query(query))
  end

  # A table goes back to its first page when its rows change: its search, sort
  # or filters, or the range or source of the whole page. Moving between its
  # pages keeps the others where they are.
  defp reset_pages(query, previous, changes) do
    Enum.reduce(Tables.tables(), query, fn table, query ->
      page_key = table <> "_page"

      rows_changed? =
        Enum.any?(changes, fn {key, value} ->
          key != page_key and previous[key] != value and
            (key in ~w(range start end source) or String.starts_with?(key, [table <> "_", "filter_" <> table <> "_"]))
        end)

      page_moved? = Map.has_key?(changes, page_key) and changes[page_key] != previous[page_key]
      if rows_changed? and not page_moved?, do: Map.delete(query, page_key), else: query
    end)
  end

  defp base_path(nil), do: ~p"/commercial/gtm/acquisition"
  defp base_path(campaign), do: ~p"/commercial/gtm/acquisition/campaigns/#{campaign}"

  defp date_start_of(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp date_end_of(%Date{} = date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

  defp format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end
end
