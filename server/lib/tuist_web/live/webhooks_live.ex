defmodule TuistWeb.WebhooksLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Webhooks

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    socket =
      socket
      |> assign(:selected_tab, "webhooks")
      |> assign(:head_title, "#{dgettext("dashboard_account", "Webhooks")} · #{selected_account.name} · Tuist")
      |> assign_endpoints()
      |> reset_create_form()
      |> reset_disclosure()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_create_form_name", %{"value" => name}, socket),
    do: {:noreply, assign(socket, :create_form_name, name)}

  def handle_event("update_create_form_url", %{"value" => url}, socket),
    do: {:noreply, socket |> assign(:create_form_url, url) |> assign(:create_form_error, nil)}

  def handle_event("create_endpoint", _params, %{assigns: assigns} = socket) do
    case Webhooks.create_endpoint(assigns.selected_account.id, %{
           "name" => assigns.create_form_name,
           "url" => assigns.create_form_url
         }) do
      {:ok, endpoint, plaintext_secret} ->
        socket =
          socket
          |> assign_endpoints()
          |> reset_create_form()
          |> assign(:disclosure, %{endpoint: endpoint, plaintext_secret: plaintext_secret, mode: :created})

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :create_form_error, humanize_errors(changeset))}
    end
  end

  def handle_event("rotate_endpoint_signing_secret", %{"id" => id}, %{assigns: %{selected_account: account}} = socket) do
    with {:ok, endpoint} <- Webhooks.get_account_endpoint(id, account.id),
         {:ok, updated, plaintext} <- Webhooks.rotate_signing_secret(endpoint) do
      socket =
        socket
        |> assign_endpoints()
        |> assign(:disclosure, %{endpoint: updated, plaintext_secret: plaintext, mode: :rotated})

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_endpoint", %{"id" => id}, %{assigns: %{selected_account: account}} = socket) do
    with {:ok, endpoint} <- Webhooks.get_account_endpoint(id, account.id),
         {:ok, _} <- Webhooks.delete_endpoint(endpoint) do
      {:noreply, assign_endpoints(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("dismiss_disclosure", _params, socket), do: {:noreply, reset_disclosure(socket)}

  # Catches close-on-Escape and close-on-interact-outside (Zag dialog state),
  # neither of which triggers `on_dismiss`. Resetting on every close keeps the
  # form clean for the next open and ensures the secret can't leak into a
  # subsequent unrelated render.
  def handle_event("create_modal_open_change", %{"open" => false}, socket),
    do: {:noreply, socket |> reset_create_form() |> reset_disclosure()}

  def handle_event("create_modal_open_change", _params, socket), do: {:noreply, socket}

  defp assign_endpoints(%{assigns: %{selected_account: account}} = socket),
    do: assign(socket, :endpoints, Webhooks.list_endpoints(account.id))

  defp reset_create_form(socket) do
    socket
    |> assign(:create_form_name, "")
    |> assign(:create_form_url, "")
    |> assign(:create_form_error, nil)
  end

  defp reset_disclosure(socket), do: assign(socket, :disclosure, nil)

  defp humanize_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, errs} -> "#{field}: #{Enum.join(errs, ", ")}" end)
  end
end
