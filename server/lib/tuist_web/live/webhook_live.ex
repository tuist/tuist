defmodule TuistWeb.WebhookLive do
  @moduledoc """
  Detail page for a single webhook endpoint. Surfaces overview info
  (URL, signing secret, subscribed events) and a list of recent delivery
  attempts pulled from the Oban jobs table.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Webhooks

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
         |> assign_deliveries()
         |> reset_disclosure()}

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_account", "Webhook endpoint not found.")
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

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

  defp assign_deliveries(%{assigns: %{endpoint: endpoint}} = socket) do
    socket
    |> assign(:deliveries, Webhooks.list_deliveries(endpoint.id))
    |> assign(:delivery_stats, Webhooks.delivery_stats(endpoint.id))
    |> assign(:deliveries_timeseries, Webhooks.deliveries_timeseries(endpoint.id))
  end

  defp reset_disclosure(socket), do: assign(socket, :disclosure, nil)
end
