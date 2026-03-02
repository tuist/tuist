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
      |> assign_saved_state()
      |> assign(:head_title, "#{dgettext("dashboard_account", "SSO")} · #{selected_account.name} · Tuist")

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_sso", _params, socket) do
    socket
    |> assign(sso_enabled: not socket.assigns.sso_enabled, flash_message: nil)
    |> compute_form_valid()
    |> compute_has_changes()
    |> then(&{:noreply, &1})
  end

  def handle_event("select_provider", %{"value" => [provider]}, socket) do
    form_params = Map.put(socket.assigns.current_form_params, "provider", provider)

    socket
    |> assign(selected_provider: provider, flash_message: nil)
    |> assign(current_form_params: form_params)
    |> assign(form: to_form(form_params, as: "sso"))
    |> compute_form_valid()
    |> compute_has_changes()
    |> then(&{:noreply, &1})
  end

  def handle_event("validate_sso", %{"sso" => form_params}, socket) do
    socket
    |> assign(current_form_params: form_params)
    |> compute_form_valid()
    |> compute_has_changes()
    |> then(&{:noreply, &1})
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
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: nil,
          sso_organization_id: nil,
          okta_client_id: nil,
          okta_encrypted_client_secret: nil
        })

      {:noreply,
       socket
       |> assign(organization: updated_organization)
       |> assign_form_from_organization(updated_organization)
       |> assign_saved_state()
       |> assign(flash_message: nil)}
    end
  end

  defp save_google_sso(%{assigns: %{organization: organization, current_user: current_user}} = socket, params) do
    domain = String.trim(params["sso"]["google_domain"] || "")

    case validate_google_sso(domain, current_user) do
      :ok ->
        {:ok, updated_organization} =
          Accounts.update_organization(organization, %{
            sso_provider: :google,
            sso_organization_id: domain,
            okta_client_id: nil,
            okta_encrypted_client_secret: nil
          })

        {:noreply,
         socket
         |> assign(organization: updated_organization)
         |> assign_form_from_organization(updated_organization)
         |> assign_saved_state()
         |> assign(flash_message: nil)}

      {:error, message} ->
        {:noreply, assign(socket, flash_message: {"error", message})}
    end
  end

  defp save_okta_sso(%{assigns: %{organization: organization}} = socket, params) do
    domain = String.trim(params["sso"]["okta_domain"] || "")
    client_id = String.trim(params["sso"]["okta_client_id"] || "")
    client_secret = String.trim(params["sso"]["okta_client_secret"] || "")

    attrs = %{sso_organization_id: domain, okta_client_id: client_id}

    attrs =
      if client_secret == "",
        do: attrs,
        else: Map.put(attrs, :okta_client_secret, client_secret)

    {:ok, updated_organization} = Accounts.update_okta_configuration(organization.id, attrs)

    {:noreply,
     socket
     |> assign(organization: updated_organization)
     |> assign_form_from_organization(updated_organization)
     |> assign_saved_state()
     |> assign(flash_message: nil)}
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

  defp assign_form_from_organization(socket, organization) do
    provider = if organization.sso_provider, do: Atom.to_string(organization.sso_provider), else: "google"
    form_data = build_form_data(provider, organization)

    socket
    |> assign(selected_provider: provider)
    |> assign(current_form_params: form_data)
    |> assign(form: to_form(form_data, as: "sso"))
  end

  defp assign_saved_state(socket) do
    socket
    |> compute_form_valid()
    |> assign(
      saved_state: %{
        sso_enabled: socket.assigns.sso_enabled,
        selected_provider: socket.assigns.selected_provider,
        form_params: socket.assigns.current_form_params
      },
      has_changes: false
    )
  end

  defp compute_form_valid(socket) do
    valid =
      if socket.assigns.sso_enabled do
        form_fields_valid?(
          socket.assigns.selected_provider,
          socket.assigns.current_form_params,
          socket.assigns.organization
        )
      else
        true
      end

    assign(socket, form_valid: valid)
  end

  defp form_fields_valid?("google", params, _organization) do
    String.trim(params["google_domain"] || "") != ""
  end

  defp form_fields_valid?("okta", params, organization) do
    domain = String.trim(params["okta_domain"] || "")
    client_id = String.trim(params["okta_client_id"] || "")
    client_secret = String.trim(params["okta_client_secret"] || "")

    has_existing_secret =
      organization.sso_provider == :okta and
        not is_nil(organization.okta_encrypted_client_secret)

    domain != "" and client_id != "" and (client_secret != "" or has_existing_secret)
  end

  defp form_fields_valid?(_provider, _params, _organization), do: true

  defp compute_has_changes(socket) do
    saved = socket.assigns.saved_state

    has_changes =
      socket.assigns.sso_enabled != saved.sso_enabled or
        socket.assigns.selected_provider != saved.selected_provider or
        socket.assigns.current_form_params != saved.form_params

    assign(socket, has_changes: has_changes)
  end

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
