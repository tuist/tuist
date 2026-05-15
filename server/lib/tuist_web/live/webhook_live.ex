defmodule TuistWeb.WebhookLive do
  @moduledoc """
  Detail page for a single webhook endpoint. Surfaces overview info
  (URL, signing secret, subscribed events), the daily delivery chart,
  and a filterable list of recent delivery attempts pulled from the Oban
  jobs table.
  """
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.WebhookEndpointForm

  alias Noora.Filter
  alias Tuist.Authorization
  alias Tuist.Webhooks
  alias Tuist.Webhooks.WebhookEndpoint
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @date_picker_prefix "deliveries"

  @impl true
  def mount(%{"id" => id}, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    case Webhooks.get_account_endpoint(id, selected_account.id) do
      {:ok, endpoint} ->
        {:ok,
         socket
         |> assign(:selected_tab, "webhooks")
         |> assign(:endpoint, endpoint)
         |> assign(:head_title, "#{endpoint.name} · #{dgettext("dashboard_account", "Webhooks")} · Tuist")
         |> assign(:event_groups, WebhookEndpoint.event_groups())
         |> assign(:available_filters, available_filters(endpoint))
         |> reset_edit_form()
         |> reset_disclosure()}

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_account", "Webhook endpoint not found.")
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri_struct = URI.new!("?" <> URI.encode_query(params))

    {:noreply,
     socket
     |> assign(:current_params, params)
     |> assign(:uri, uri_struct)
     |> assign_deliveries(params)}
  end

  @impl true
  def handle_event("rotate_endpoint_signing_secret", _params, socket) do
    case Webhooks.rotate_signing_secret(socket.assigns.endpoint) do
      {:ok, updated, plaintext} ->
        {:noreply,
         socket
         |> assign(:endpoint, updated)
         |> assign(:disclosure, %{plaintext_secret: plaintext})
         |> push_event("open-modal", %{id: "webhook-signing-secret-modal"})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("dismiss_disclosure", _params, socket) do
    {:noreply,
     socket
     |> reset_disclosure()
     |> push_event("close-modal", %{id: "webhook-signing-secret-modal"})}
  end

  def handle_event("disclosure_modal_open_change", %{"open" => false}, socket), do: {:noreply, reset_disclosure(socket)}

  def handle_event("disclosure_modal_open_change", _params, socket), do: {:noreply, socket}

  def handle_event("delete_endpoint", _params, %{assigns: %{endpoint: endpoint, selected_account: account}} = socket) do
    {:ok, _} = Webhooks.delete_endpoint(endpoint)
    {:noreply, push_navigate(socket, to: ~p"/#{account.name}/webhooks")}
  end

  # Prime the form with the endpoint's current values before showing the
  # modal so it feels like a true edit instead of a freshly filled form.
  def handle_event("open_edit_form", _params, %{assigns: %{endpoint: endpoint}} = socket) do
    {:noreply,
     socket
     |> assign(:edit_form_name, endpoint.name)
     |> assign(:edit_form_url, endpoint.url)
     |> assign(:edit_form_event_types, endpoint.event_types)
     |> assign(:edit_form_error, nil)
     |> push_event("open-modal", %{id: "webhook-edit-endpoint-modal"})}
  end

  def handle_event("update_edit_form_name", %{"value" => name}, socket),
    do: {:noreply, socket |> assign(:edit_form_name, name) |> assign(:edit_form_error, nil)}

  def handle_event("update_edit_form_url", %{"value" => url}, socket),
    do: {:noreply, socket |> assign(:edit_form_url, url) |> assign(:edit_form_error, nil)}

  def handle_event("toggle_edit_form_event_type", %{"data" => event_type}, socket) do
    selected = socket.assigns.edit_form_event_types

    next =
      if event_type in selected do
        List.delete(selected, event_type)
      else
        [event_type | selected]
      end

    {:noreply, socket |> assign(:edit_form_event_types, next) |> assign(:edit_form_error, nil)}
  end

  def handle_event("toggle_edit_form_event_group", %{"data" => group_key}, socket) do
    case Enum.find(socket.assigns.event_groups, &(&1.key == group_key)) do
      nil ->
        {:noreply, socket}

      group ->
        group_types = Enum.map(group.events, & &1.type)
        selected = socket.assigns.edit_form_event_types

        next =
          if Enum.all?(group_types, &(&1 in selected)) do
            selected -- group_types
          else
            Enum.uniq(group_types ++ selected)
          end

        {:noreply, socket |> assign(:edit_form_event_types, next) |> assign(:edit_form_error, nil)}
    end
  end

  def handle_event("update_endpoint", _params, %{assigns: assigns} = socket) do
    attrs = %{
      "name" => assigns.edit_form_name,
      "url" => assigns.edit_form_url,
      "event_types" => assigns.edit_form_event_types
    }

    case Webhooks.update_endpoint(assigns.endpoint, attrs) do
      {:ok, endpoint} ->
        {:noreply,
         socket
         |> assign(:endpoint, endpoint)
         |> assign(:available_filters, available_filters(endpoint))
         |> reset_edit_form()
         |> push_event("close-modal", %{id: "webhook-edit-endpoint-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :edit_form_error, humanize_errors(changeset))}
    end
  end

  def handle_event("dismiss_edit_form", _params, socket) do
    {:noreply,
     socket
     |> reset_edit_form()
     |> push_event("close-modal", %{id: "webhook-edit-endpoint-modal"})}
  end

  def handle_event("edit_modal_open_change", %{"open" => false}, socket),
    do: {:noreply, reset_edit_form(socket)}

  def handle_event("edit_modal_open_change", _params, socket), do: {:noreply, socket}

  def handle_event(
        "deliveries_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("#{@date_picker_prefix}-date-range", "custom")
        |> Query.put("#{@date_picker_prefix}-start-date", start_date)
        |> Query.put("#{@date_picker_prefix}-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "#{@date_picker_prefix}-date-range", preset)
      end

    {:noreply, push_patch(socket, to: detail_path(socket, query))}
  end

  def handle_event("search_deliveries", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("search", search)

    {:noreply, push_patch(socket, to: detail_path(socket, query), replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: detail_path(socket, URI.encode_query(updated_params)))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: detail_path(socket, URI.encode_query(updated_params)))
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  @doc """
  Same partial-mask format as the index page, so users can match the
  suffix against a secret they've stored elsewhere.
  """
  def masked_signing_secret(secret), do: TuistWeb.WebhooksLive.masked_signing_secret(secret)

  @doc """
  Human label for a delivery attempt's status.
  """
  def delivery_state_label("delivered"), do: dgettext("dashboard_account", "Delivered")
  def delivery_state_label("failed"), do: dgettext("dashboard_account", "Failed")
  def delivery_state_label(other), do: other

  @doc """
  Maps a delivery attempt's status to a Noora status-badge color.
  """
  def delivery_state_status("delivered"), do: "success"
  def delivery_state_status("failed"), do: "error"
  def delivery_state_status(_), do: "information"

  @doc """
  Presets exposed by the chart's date picker. Hard-coded to a small set
  because oban_jobs are pruned aggressively; charting further back would
  show mostly empty buckets.
  """
  def date_picker_presets do
    [
      %{id: "last-24-hours", label: dgettext("dashboard_account", "Last 24 hours"), period: {24, :hour}},
      %{id: "last-7-days", label: dgettext("dashboard_account", "Last 7 days"), period: {7, :day}},
      %{id: "last-30-days", label: dgettext("dashboard_account", "Last 30 days"), period: {30, :day}},
      %{id: "custom", label: dgettext("dashboard_account", "Custom")}
    ]
  end

  # Event-type options are scoped to the types this endpoint subscribes to —
  # other types could never appear in its delivery log, so they'd just be
  # dead choices in the dropdown.
  defp available_filters(endpoint) do
    [
      %Filter.Filter{
        id: "status",
        field: "status",
        display_name: dgettext("dashboard_account", "Status"),
        type: :option,
        options: ["delivered", "failed"],
        options_display_names: %{
          "delivered" => dgettext("dashboard_account", "Delivered"),
          "failed" => dgettext("dashboard_account", "Failed")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "event_type",
        field: "event_type",
        display_name: dgettext("dashboard_account", "Event"),
        type: :option,
        options: endpoint.event_types,
        options_display_names: Map.new(endpoint.event_types, &{&1, &1}),
        operator: :==,
        value: nil
      }
    ]
  end

  defp assign_deliveries(%{assigns: %{endpoint: endpoint, available_filters: available}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, @date_picker_prefix, default_preset: "last-7-days", default_days: 7)

    active_filters = Filter.Operations.decode_filters_from_query(params, available)
    status = filter_value(active_filters, "status")
    event_type = filter_value(active_filters, "event_type")
    search = params["search"] || ""

    list_opts = [
      start_datetime: start_datetime,
      end_datetime: end_datetime,
      status: status && String.to_existing_atom(status),
      event_type: event_type,
      event_id_search: search
    ]

    socket
    |> assign(:deliveries_preset, preset)
    |> assign(:deliveries_period, period)
    |> assign(:active_filters, active_filters)
    |> assign(:deliveries_search, search)
    |> assign(:deliveries, Webhooks.list_deliveries(endpoint.id, list_opts))
    |> assign(
      :delivery_stats,
      Webhooks.delivery_stats(endpoint.id, start_datetime: start_datetime, end_datetime: end_datetime)
    )
    |> assign(
      :deliveries_timeseries,
      Webhooks.deliveries_timeseries(endpoint.id, start_datetime: start_datetime, end_datetime: end_datetime)
    )
  end

  defp reset_edit_form(socket) do
    socket
    |> assign(:edit_form_name, "")
    |> assign(:edit_form_url, "")
    |> assign(:edit_form_event_types, [])
    |> assign(:edit_form_error, nil)
  end

  defp humanize_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, errs} -> "#{field}: #{Enum.join(errs, ", ")}" end)
  end

  defp filter_value(filters, id) do
    Enum.find_value(filters, fn
      %Filter.Filter{id: ^id, value: value} when value not in [nil, ""] -> value
      _ -> nil
    end)
  end

  defp detail_path(socket, query) when is_binary(query) do
    "/#{socket.assigns.selected_account.name}/webhooks/#{socket.assigns.endpoint.id}?#{query}"
  end

  defp reset_disclosure(socket), do: assign(socket, :disclosure, nil)
end
