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

  alias Noora.Filter
  alias Tuist.Authorization
  alias Tuist.Webhooks
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
         |> assign(:available_filters, available_filters())
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
  Human label for a delivery row's state, taken straight from Oban so the
  status badge stays meaningful even as new states get introduced.
  """
  def delivery_state_label("completed"), do: dgettext("dashboard_account", "Delivered")
  def delivery_state_label("discarded"), do: dgettext("dashboard_account", "Failed")
  def delivery_state_label("cancelled"), do: dgettext("dashboard_account", "Cancelled")
  def delivery_state_label("retryable"), do: dgettext("dashboard_account", "Retrying")
  def delivery_state_label("scheduled"), do: dgettext("dashboard_account", "Scheduled")
  def delivery_state_label("available"), do: dgettext("dashboard_account", "Queued")
  def delivery_state_label("executing"), do: dgettext("dashboard_account", "Sending")
  def delivery_state_label(other), do: other

  @doc """
  Maps the Oban state to a Noora status-badge color.
  """
  def delivery_state_status("completed"), do: "success"
  def delivery_state_status(state) when state in ["discarded", "cancelled"], do: "error"
  def delivery_state_status("retryable"), do: "warning"
  def delivery_state_status(_), do: "information"

  @doc """
  Most recent timestamp on the job, used as the "Last attempt" column.
  Falls back to `inserted_at` for jobs that haven't run yet.
  """
  def last_activity_at(%{completed_at: ts}) when not is_nil(ts), do: ts
  def last_activity_at(%{discarded_at: ts}) when not is_nil(ts), do: ts
  def last_activity_at(%{cancelled_at: ts}) when not is_nil(ts), do: ts
  def last_activity_at(%{attempted_at: ts}) when not is_nil(ts), do: ts
  def last_activity_at(%{inserted_at: ts}), do: ts

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

  defp available_filters do
    [
      %Filter.Filter{
        id: "status",
        field: "status",
        display_name: dgettext("dashboard_account", "Status"),
        type: :option,
        options: ["delivered", "failed", "retrying", "pending"],
        options_display_names: %{
          "delivered" => dgettext("dashboard_account", "Delivered"),
          "failed" => dgettext("dashboard_account", "Failed"),
          "retrying" => dgettext("dashboard_account", "Retrying"),
          "pending" => dgettext("dashboard_account", "Pending")
        },
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
    search = params["search"] || ""

    list_opts = [
      start_datetime: start_datetime,
      end_datetime: end_datetime,
      status: status && String.to_existing_atom(status),
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
