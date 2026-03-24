defmodule TuistWeb.SSOSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Tuist.Accounts
  alias Tuist.Accounts.CustomOAuth2
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
      |> assign(sso_enforced: organization.sso_enforced)
      |> assign(flash_message: nil)
      |> assign_form_from_organization(organization)
      |> assign_saved_state()
      |> assign(:head_title, "#{dgettext("dashboard_account", "SSO")} · #{selected_account.name} · Tuist")

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_sso", _params, socket) do
    sso_enabled = not socket.assigns.sso_enabled

    socket
    |> assign(sso_enabled: sso_enabled, sso_enforced: sso_enabled and socket.assigns.sso_enforced, flash_message: nil)
    |> compute_form_valid()
    |> compute_has_changes()
    |> then(&{:noreply, &1})
  end

  def handle_event("toggle_sso_enforced", _params, socket) do
    socket
    |> assign(sso_enforced: not socket.assigns.sso_enforced, flash_message: nil)
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

  def handle_event("select_provider", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_sso", %{"sso" => form_params}, socket) do
    socket
    |> assign(current_form_params: form_params)
    |> compute_form_valid()
    |> compute_has_changes()
    |> then(&{:noreply, &1})
  end

  def handle_event("validate_sso", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_sso", _params, %{assigns: %{sso_enabled: false}} = socket) do
    disable_sso(socket)
  end

  def handle_event("save_sso", params, socket) do
    case validate_sso_enforcement(socket) do
      :ok ->
        case socket.assigns.selected_provider do
          "google" -> save_google_sso(socket, params)
          provider when provider in ["okta", "oauth2"] -> save_oauth2_sso(socket, params)
        end

      {:error, message} ->
        {:noreply, assign(socket, flash_message: {"error", message})}
    end
  end

  defp disable_sso(%{assigns: %{organization: organization}} = socket) do
    if is_nil(organization.sso_provider) and not organization.sso_enforced do
      {:noreply, socket}
    else
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: nil,
          sso_organization_id: nil,
          sso_enforced: false,
          oauth2_client_id: nil,
          oauth2_encrypted_client_secret: nil,
          oauth2_authorize_url: nil,
          oauth2_token_url: nil,
          oauth2_user_info_url: nil
        })

      {:noreply,
       socket
       |> assign(organization: updated_organization)
       |> assign(sso_enforced: false)
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
            sso_enforced: socket.assigns.sso_enforced
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

  defp save_oauth2_sso(%{assigns: %{organization: organization, selected_provider: selected_provider}} = socket, params) do
    sso_provider = String.to_existing_atom(selected_provider)
    attrs = build_oauth2_attrs(selected_provider, params["sso"] || %{}, socket.assigns.sso_enforced)

    {:ok, updated_organization} = Accounts.update_sso_configuration(organization.id, sso_provider, attrs)

    {:noreply,
     socket
     |> assign(organization: updated_organization)
     |> assign_form_from_organization(updated_organization)
     |> assign_saved_state()
     |> assign(flash_message: nil)}
  end

  defp build_oauth2_attrs(selected_provider, form, sso_enforced) do
    {sso_organization_id, authorize_url, token_url, user_info_url} =
      extract_oauth2_urls(selected_provider, form)

    attrs = %{
      sso_organization_id: sso_organization_id,
      sso_enforced: sso_enforced,
      oauth2_client_id: String.trim(form["oauth2_client_id"] || ""),
      oauth2_authorize_url: authorize_url,
      oauth2_token_url: token_url,
      oauth2_user_info_url: user_info_url
    }

    client_secret = String.trim(form["oauth2_client_secret"] || "")

    if client_secret == "",
      do: attrs,
      else: Map.put(attrs, :oauth2_client_secret, client_secret)
  end

  defp extract_oauth2_urls("okta", form) do
    domain = String.trim(form["okta_domain"] || "")

    {domain, CustomOAuth2.okta_authorize_url(domain), CustomOAuth2.okta_token_url(domain),
     CustomOAuth2.okta_userinfo_url(domain)}
  end

  defp extract_oauth2_urls("oauth2", form) do
    {String.trim(form["oauth2_site"] || ""), String.trim(form["oauth2_authorize_url"] || ""),
     String.trim(form["oauth2_token_url"] || ""), String.trim(form["oauth2_user_info_url"] || "")}
  end

  defp validate_sso_enforcement(%{assigns: %{sso_enforced: false}}), do: :ok

  defp validate_sso_enforcement(%{assigns: %{current_user: current_user}} = socket) do
    provider = String.to_atom(socket.assigns.selected_provider)

    sso_organization_id =
      case socket.assigns.selected_provider do
        "google" -> String.trim(socket.assigns.current_form_params["google_domain"] || "")
        "okta" -> String.trim(socket.assigns.current_form_params["okta_domain"] || "")
        "oauth2" -> String.trim(socket.assigns.current_form_params["oauth2_site"] || "")
      end

    has_identity =
      not is_nil(
        Accounts.find_oauth2_identity(%{user: current_user, provider: provider},
          provider_organization_id: sso_organization_id
        )
      )

    if has_identity do
      :ok
    else
      {:error,
       dgettext(
         "dashboard_account",
         "You must authenticate with the SSO provider before enforcing SSO. Please sign in with your SSO provider first."
       )}
    end
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
        sso_enforced: socket.assigns.sso_enforced,
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
    field_present?(params, "okta_domain") and
      oauth2_credentials_valid?(params, organization)
  end

  defp form_fields_valid?("oauth2", params, organization) do
    oauth2_credentials_valid?(params, organization) and
      required_fields_present?(params, [
        "oauth2_site",
        "oauth2_authorize_url",
        "oauth2_token_url",
        "oauth2_user_info_url"
      ])
  end

  defp form_fields_valid?(_provider, _params, _organization), do: true

  defp oauth2_credentials_valid?(params, organization) do
    field_present?(params, "oauth2_client_id") and
      (field_present?(params, "oauth2_client_secret") or has_existing_secret?(organization))
  end

  defp has_existing_secret?(organization) do
    organization.sso_provider in [:okta, :oauth2] and
      not is_nil(organization.oauth2_encrypted_client_secret)
  end

  defp field_present?(params, field), do: String.trim(params[field] || "") != ""

  defp required_fields_present?(params, fields) do
    Enum.all?(fields, fn field ->
      String.trim(params[field] || "") != ""
    end)
  end

  defp compute_has_changes(socket) do
    saved = socket.assigns.saved_state

    has_changes =
      socket.assigns.sso_enabled != saved.sso_enabled or
        socket.assigns.sso_enforced != saved.sso_enforced or
        socket.assigns.selected_provider != saved.selected_provider or
        socket.assigns.current_form_params != saved.form_params

    assign(socket, has_changes: has_changes)
  end

  defp build_form_data("google", organization) do
    Map.merge(default_form_data(), %{"provider" => "google", "google_domain" => organization.sso_organization_id || ""})
  end

  defp build_form_data("okta", organization) do
    Map.merge(default_form_data(), %{
      "provider" => "okta",
      "okta_domain" => organization.sso_organization_id || "",
      "oauth2_client_id" => organization.oauth2_client_id || "",
      "oauth2_client_secret" => ""
    })
  end

  defp build_form_data("oauth2", organization) do
    Map.merge(default_form_data(), %{
      "provider" => "oauth2",
      "oauth2_site" => organization.sso_organization_id || "",
      "oauth2_client_id" => organization.oauth2_client_id || "",
      "oauth2_client_secret" => "",
      "oauth2_authorize_url" => organization.oauth2_authorize_url || "",
      "oauth2_token_url" => organization.oauth2_token_url || "",
      "oauth2_user_info_url" => organization.oauth2_user_info_url || ""
    })
  end

  defp build_form_data(_provider, _organization) do
    default_form_data()
  end

  defp default_form_data do
    %{
      "provider" => "google",
      "google_domain" => "",
      "okta_domain" => "",
      "oauth2_client_id" => "",
      "oauth2_client_secret" => "",
      "oauth2_site" => "",
      "oauth2_authorize_url" => "",
      "oauth2_token_url" => "",
      "oauth2_user_info_url" => ""
    }
  end
end
