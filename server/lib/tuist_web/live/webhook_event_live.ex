defmodule TuistWeb.WebhookEventLive do
  @moduledoc """
  Detail page for a single webhook delivery attempt. Shows the
  request body, response status, response headers, response body, and
  any error captured by the delivery worker — the dashboard's view into
  what we actually sent over the wire.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Webhooks

  @impl true
  def mount(
        %{"id" => endpoint_id, "attempt_id" => attempt_id},
        _uri,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    with {:ok, endpoint} <- Webhooks.get_account_endpoint(endpoint_id, selected_account.id),
         {:ok, attempt} <- Webhooks.get_delivery_attempt(endpoint.id, attempt_id) do
      {:ok,
       socket
       |> assign(:selected_tab, "webhooks")
       |> assign(:endpoint, endpoint)
       |> assign(:attempt, attempt)
       |> assign(
         :head_title,
         "#{attempt.event_id} · #{endpoint.name} · #{dgettext("dashboard_account", "Webhooks")} · Tuist"
       )}
    else
      _ ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_account", "Webhook delivery attempt not found.")
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @doc """
  Pretty-prints a JSON request body for the dashboard. The worker stores
  the exact bytes we sent, so a re-encode keeps timing identical without
  rewriting the schema. Falls back to the raw string if the body isn't
  JSON.
  """
  def format_body(nil), do: ""

  def format_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  def delivery_state_label(status), do: TuistWeb.WebhookLive.delivery_state_label(status)
  def delivery_state_status(status), do: TuistWeb.WebhookLive.delivery_state_status(status)

  @doc """
  Returns request and response headers as a sorted list of {name, value}
  tuples so the table renders deterministically.
  """
  def header_list(nil), do: []
  def header_list(headers) when is_map(headers), do: headers |> Enum.to_list() |> Enum.sort_by(fn {k, _} -> k end)
  def header_list(_), do: []
end
