defmodule TuistWeb.SSOSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Tuist.Accounts
  alias Tuist.Authorization

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    if is_nil(selected_account.organization_id) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_account", "SSO settings are only available for organizations.")
    end

    {:ok, organization} = Accounts.get_organization_by_id(selected_account.organization_id)

    sso_enabled = not is_nil(organization.sso_provider)

    socket =
      socket
      |> assign(selected_tab: "sso")
      |> assign(organization: organization)
      |> assign(sso_enabled: sso_enabled)
      |> assign(flash_message: nil)
      |> assign_form_from_organization(organization)
      |> assign(:head_title, "#{dgettext("dashboard_account", "SSO")} · #{selected_account.name} · Tuist")

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_sso", _params, socket) do
    {:noreply, assign(socket, sso_enabled: not socket.assigns.sso_enabled, flash_message: nil)}
  end

  def handle_event("select_provider", %{"value" => [provider]}, socket) do
    {:noreply, assign(socket, selected_provider: provider, flash_message: nil)}
  end

  def handle_event("validate_sso", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_sso", _params, %{assigns: %{sso_enabled: false}} = socket) do
    disable_sso(socket)
  end

  def handle_event("save_sso", params, socket) do
    case socket.assigns.selected_provider do
      "google" -> save_google_sso(socket, params)
      "okta" -> save_okta_sso(socket, params)
    end
  end

  defp disable_sso(%{assigns: %{organization: organization}} = socket) do
    if is_nil(organization.sso_provider) do
      {:noreply, socket}
    else
      case Accounts.update_organization(organization, %{
             sso_provider: nil,
             sso_organization_id: nil,
             okta_client_id: nil,
             okta_encrypted_client_secret: nil
           }) do
        {:ok, updated_organization} ->
          {:noreply,
           socket
           |> assign(organization: updated_organization)
           |> assign_form_from_organization(updated_organization)
           |> assign(flash_message: {"success", dgettext("dashboard_account", "SSO has been disabled.")})}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  defp save_google_sso(%{assigns: %{organization: organization, current_user: current_user}} = socket, params) do
    domain = String.trim(params["sso"]["google_domain"] || "")

    case validate_google_sso(domain, current_user) do
      :ok ->
        case Accounts.update_organization(organization, %{
               sso_provider: :google,
               sso_organization_id: domain,
               okta_client_id: nil,
               okta_encrypted_client_secret: nil
             }) do
          {:ok, updated_organization} ->
            {:noreply,
             socket
             |> assign(organization: updated_organization)
             |> assign_form_from_organization(updated_organization)
             |> assign(
               flash_message: {"success", dgettext("dashboard_account", "Google SSO has been configured successfully.")}
             )}

          {:error, _changeset} ->
            {:noreply,
             assign(socket,
               flash_message:
                 {"error",
                  dgettext(
                    "dashboard_account",
                    "Failed to configure Google SSO. Please try again."
                  )}
             )}
        end

      {:error, message} ->
        {:noreply, assign(socket, flash_message: {"error", message})}
    end
  end

  defp save_okta_sso(%{assigns: %{organization: organization}} = socket, params) do
    domain = String.trim(params["sso"]["okta_domain"] || "")
    client_id = String.trim(params["sso"]["okta_client_id"] || "")
    client_secret = String.trim(params["sso"]["okta_client_secret"] || "")

    case validate_okta_sso(domain, client_id, client_secret, organization) do
      :ok ->
        attrs = %{sso_organization_id: domain, okta_client_id: client_id}

        attrs =
          if client_secret == "",
            do: attrs,
            else: Map.put(attrs, :okta_client_secret, client_secret)

        case Accounts.update_okta_configuration(organization.id, attrs) do
          {:ok, updated_organization} ->
            {:noreply,
             socket
             |> assign(organization: updated_organization)
             |> assign_form_from_organization(updated_organization)
             |> assign(
               flash_message: {"success", dgettext("dashboard_account", "Okta SSO has been configured successfully.")}
             )}

          {:error, _} ->
            {:noreply,
             assign(socket,
               flash_message:
                 {"error",
                  dgettext(
                    "dashboard_account",
                    "Failed to configure Okta SSO. Please try again."
                  )}
             )}
        end

      {:error, message} ->
        {:noreply, assign(socket, flash_message: {"error", message})}
    end
  end

  defp validate_google_sso("", _current_user) do
    {:error, dgettext("dashboard_account", "Please enter your Google Workspace domain.")}
  end

  defp validate_google_sso(domain, current_user) do
    if is_nil(
         Accounts.find_oauth2_identity(%{user: current_user, provider: :google},
           provider_organization_id: domain
         )
       ) do
      {:error,
       dgettext(
         "dashboard_account",
         "You must be authenticated with Google using an email tied to this domain. Please sign in with Google first."
       )}
    else
      :ok
    end
  end

  defp validate_okta_sso(domain, client_id, _client_secret, _organization) when domain == "" or client_id == "" do
    {:error, dgettext("dashboard_account", "Please fill in all required fields.")}
  end

  defp validate_okta_sso(_domain, _client_id, "", %{okta_encrypted_client_secret: nil}) do
    {:error, dgettext("dashboard_account", "Please enter the client secret.")}
  end

  defp validate_okta_sso(_domain, _client_id, _client_secret, _organization), do: :ok

  defp assign_form_from_organization(socket, organization) do
    provider = provider_to_string(organization.sso_provider)
    form_data = build_form_data(provider, organization)

    socket
    |> assign(selected_provider: provider)
    |> assign(form: to_form(form_data, as: "sso"))
  end

  defp provider_to_string(:google), do: "google"
  defp provider_to_string(:okta), do: "okta"
  defp provider_to_string(_), do: "google"

  defp build_form_data("google", organization) do
    %{
      "provider" => "google",
      "google_domain" => organization.sso_organization_id || "",
      "okta_domain" => "",
      "okta_client_id" => "",
      "okta_client_secret" => ""
    }
  end

  defp build_form_data("okta", organization) do
    %{
      "provider" => "okta",
      "google_domain" => "",
      "okta_domain" => organization.sso_organization_id || "",
      "okta_client_id" => organization.okta_client_id || "",
      "okta_client_secret" => ""
    }
  end

  defp build_form_data(_provider, _organization) do
    %{
      "provider" => "google",
      "google_domain" => "",
      "okta_domain" => "",
      "okta_client_id" => "",
      "okta_client_secret" => ""
    }
  end
end
