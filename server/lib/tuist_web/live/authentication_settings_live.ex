defmodule TuistWeb.AuthenticationSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.SCIM

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    if is_nil(selected_account.organization_id) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_account", "Authentication settings are only available for organizations.")
    end

    {:ok, organization} = Accounts.get_organization_by_id(selected_account.organization_id)

    sso_enabled = not is_nil(organization.sso_provider)

    socket =
      socket
      |> assign(organization: organization)
      |> assign(sso_enabled: sso_enabled)
      |> assign(sso_enforced: organization.sso_enforced)
      |> assign(sso_automatic_enrollment: organization.sso_automatic_enrollment)
      |> assign(flash_message: nil, field_errors: %{})
      |> assign_form_from_organization(organization)
      |> assign_saved_state()
      |> assign(:scim_base_url, Environment.app_url(path: "/scim/v2"))
      |> assign(:scim_tokens, SCIM.list_tokens(organization))
      |> assign(:new_scim_token_plaintext, nil)
      |> assign(:new_scim_token_form, to_form(%{"name" => ""}, as: "scim_token"))
      |> assign(
        :head_title,
        "#{dgettext("dashboard_account", "Authentication")} · #{selected_account.name} · Tuist"
      )

    {:ok, socket}
  end

  ## SSO events ----------------------------------------------------------

  @impl true
  def handle_event("toggle_sso", _params, socket) do
    sso_enabled = not socket.assigns.sso_enabled

    socket
    |> assign(
      sso_enabled: sso_enabled,
      sso_enforced: sso_enabled and socket.assigns.sso_enforced,
      sso_automatic_enrollment:
        cond do
          not sso_enabled -> false
          is_nil(socket.assigns.organization.sso_provider) and socket.assigns.selected_provider == "google" -> true
          true -> socket.assigns.sso_automatic_enrollment
        end,
      flash_message: nil,
      field_errors: %{}
    )
    |> compute_form_valid()
    |> compute_has_changes()
    |> then(&{:noreply, &1})
  end

  def handle_event("toggle_sso_enforced", _params, socket) do
    if sso_enforcement_toggle_disabled?(
         socket.assigns.selected_provider,
         socket.assigns.organization,
         socket.assigns.current_form_params,
         socket.assigns.sso_enforced
       ) do
      {:noreply, socket}
    else
      socket
      |> assign(sso_enforced: not socket.assigns.sso_enforced, flash_message: nil, field_errors: %{})
      |> compute_has_changes()
      |> then(&{:noreply, &1})
    end
  end

  def handle_event("toggle_sso_automatic_enrollment", _params, socket) do
    if automatic_enrollment_toggle_disabled?(
         socket.assigns.selected_provider,
         socket.assigns.organization,
         socket.assigns.current_form_params,
         socket.assigns.sso_automatic_enrollment
       ) do
      {:noreply, socket}
    else
      socket
      |> assign(
        sso_automatic_enrollment: not socket.assigns.sso_automatic_enrollment,
        flash_message: nil,
        field_errors: %{}
      )
      |> compute_has_changes()
      |> then(&{:noreply, &1})
    end
  end

  def handle_event("select_provider", %{"value" => [provider]}, socket) when provider in ["google", "okta", "oauth2"] do
    form_params = Map.put(socket.assigns.current_form_params, "provider", provider)

    verified_domain? =
      verified_login_domain_selected?(provider, socket.assigns.organization, form_params)

    legacy_enforcement? =
      legacy_sso_enforcement?(provider, socket.assigns.organization)

    socket
    |> assign(
      selected_provider: provider,
      sso_automatic_enrollment:
        cond do
          provider == "google" and socket.assigns.selected_provider != "google" -> true
          provider in ["okta", "oauth2"] and not verified_domain? -> false
          true -> socket.assigns.sso_automatic_enrollment
        end,
      sso_enforced:
        if(provider in ["okta", "oauth2"] and not verified_domain? and not legacy_enforcement?,
          do: false,
          else: socket.assigns.sso_enforced
        ),
      flash_message: nil,
      field_errors: %{}
    )
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
    verified_domain? =
      verified_login_domain_selected?(
        socket.assigns.selected_provider,
        socket.assigns.organization,
        form_params
      )

    custom_provider_without_verified_domain? =
      socket.assigns.selected_provider in ["okta", "oauth2"] and not verified_domain?

    legacy_enforcement? =
      legacy_sso_enforcement?(
        socket.assigns.selected_provider,
        socket.assigns.organization
      )

    socket
    |> assign(
      current_form_params: form_params,
      sso_automatic_enrollment:
        if(custom_provider_without_verified_domain?,
          do: false,
          else: socket.assigns.sso_automatic_enrollment
        ),
      sso_enforced:
        if(custom_provider_without_verified_domain? and not legacy_enforcement?,
          do: false,
          else: socket.assigns.sso_enforced
        )
    )
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

  def handle_event("verify_sso_login_domain", _params, socket) do
    form_domain = normalize_domain(socket.assigns.current_form_params["sso_login_domain"])

    case Accounts.get_organization_by_id(socket.assigns.organization.id) do
      {:ok, organization} when organization.sso_login_domain == form_domain ->
        case Accounts.verify_sso_login_domain(organization) do
          {:ok, organization} ->
            {:noreply,
             socket
             |> assign(:organization, organization)
             |> assign(
               :flash_message,
               {"success", dgettext("dashboard_account", "The login domain has been verified.")}
             )}

          {:error, :verification_record_not_found} ->
            {:noreply,
             assign(
               socket,
               :flash_message,
               {"error",
                dgettext(
                  "dashboard_account",
                  "The verification text record was not found. Domain record changes can take time to become available."
                )}
             )}

          {:error, :login_domain_not_configured} ->
            {:noreply,
             assign(
               socket,
               :flash_message,
               {"error", dgettext("dashboard_account", "Configure and save a login domain first.")}
             )}

          {:error, changeset} ->
            {:noreply,
             assign(
               socket,
               :flash_message,
               {"error", changeset_error_message(changeset)}
             )}
        end

      _ ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "Save the login domain before verifying it.")}
         )}
    end
  end

  ## SCIM events ---------------------------------------------------------

  def handle_event("generate_scim_token", %{"scim_token" => params}, socket) do
    name = params |> Map.get("name", "") |> String.trim()

    if name == "" do
      {:noreply,
       assign(
         socket,
         :flash_message,
         {"error", dgettext("dashboard_account", "Token name is required.")}
       )}
    else
      case SCIM.create_token(socket.assigns.organization, %{name: name}) do
        {:ok, {_token, plaintext}} ->
          {:noreply,
           socket
           |> assign(:new_scim_token_plaintext, plaintext)
           |> assign(:new_scim_token_form, to_form(%{"name" => ""}, as: "scim_token"))
           |> assign(:scim_tokens, SCIM.list_tokens(socket.assigns.organization))
           |> assign(:flash_message, nil)}

        {:error, changeset} ->
          message =
            changeset
            |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
            |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

          {:noreply, assign(socket, :flash_message, {"error", message})}
      end
    end
  end

  def handle_event("dismiss_scim_token", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_scim_token_plaintext, nil)
     |> push_event("close-modal", %{id: "generate-scim-token-modal"})}
  end

  # Reset the modal to its blank form when closed via Escape, backdrop click, or
  # the X icon. The `details.open` flag is sent by Zag.js dialog state machine.
  def handle_event("scim_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:new_scim_token_plaintext, nil)
     |> assign(:new_scim_token_form, to_form(%{"name" => ""}, as: "scim_token"))}
  end

  def handle_event("scim_modal_open_change", _params, socket), do: {:noreply, socket}

  def handle_event("revoke_scim_token", %{"id" => id}, socket) do
    case SCIM.revoke_token(socket.assigns.organization, id) do
      {:ok, _} ->
        {:noreply, assign(socket, :scim_tokens, SCIM.list_tokens(socket.assigns.organization))}

      {:error, :not_found} ->
        {:noreply, assign(socket, :flash_message, {"error", dgettext("dashboard_account", "Token not found.")})}
    end
  end

  ## SSO helpers ---------------------------------------------------------

  defp disable_sso(%{assigns: %{organization: organization}} = socket) do
    if is_nil(organization.sso_provider) and not organization.sso_enforced do
      {:noreply, socket}
    else
      {:ok, updated_organization} =
        Accounts.update_organization(organization, %{
          sso_provider: nil,
          sso_organization_id: nil,
          sso_enforced: false,
          sso_login_domain: nil,
          sso_automatic_enrollment: false,
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
       |> assign(sso_automatic_enrollment: false)
       |> assign_form_from_organization(updated_organization)
       |> assign_saved_state()
       |> assign(flash_message: nil, field_errors: %{})}
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
            sso_enforced: socket.assigns.sso_enforced,
            sso_automatic_enrollment: socket.assigns.sso_automatic_enrollment
          })

        {:noreply,
         socket
         |> assign(organization: updated_organization)
         |> assign_form_from_organization(updated_organization)
         |> assign_saved_state()
         |> assign(flash_message: nil, field_errors: %{})}

      {:error, message} ->
        {:noreply, assign(socket, flash_message: {"error", message})}
    end
  end

  defp save_oauth2_sso(%{assigns: %{organization: organization, selected_provider: selected_provider}} = socket, params) do
    form_params = params["sso"] || %{}
    sso_provider = String.to_existing_atom(selected_provider)

    attrs =
      build_oauth2_attrs(
        selected_provider,
        form_params,
        socket.assigns.sso_enforced,
        socket.assigns.sso_automatic_enrollment
      )

    case Accounts.update_sso_configuration(organization.id, sso_provider, attrs) do
      {:ok, updated_organization} ->
        {:noreply,
         socket
         |> assign(organization: updated_organization)
         |> assign_form_from_organization(updated_organization)
         |> assign_saved_state()
         |> assign(flash_message: nil, field_errors: %{})}

      {:error, changeset} ->
        form_params =
          default_form_data()
          |> Map.merge(form_params)
          |> Map.put("provider", selected_provider)

        {:noreply,
         socket
         |> assign(current_form_params: form_params)
         |> assign(form: to_form(form_params, as: "sso"))
         |> assign(field_errors: changeset_to_field_errors(changeset, selected_provider))
         |> assign(flash_message: {"error", changeset_error_message(changeset)})
         |> compute_form_valid()
         |> compute_has_changes()}
    end
  end

  @changeset_to_form_field %{
    sso_organization_id: %{"okta" => "okta_domain", "oauth2" => "oauth2_site"},
    sso_login_domain: "sso_login_domain",
    oauth2_authorize_url: "oauth2_authorize_url",
    oauth2_token_url: "oauth2_token_url",
    oauth2_user_info_url: "oauth2_user_info_url",
    oauth2_client_id: "oauth2_client_id",
    oauth2_encrypted_client_secret: "oauth2_client_secret"
  }

  defp changeset_to_field_errors(changeset, provider) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.reduce(%{}, fn {field, msgs}, acc ->
      form_field =
        case Map.get(@changeset_to_form_field, field) do
          %{} = per_provider -> Map.get(per_provider, provider, to_string(field))
          name when is_binary(name) -> name
          nil -> to_string(field)
        end

      Map.put(acc, form_field, Enum.join(msgs, ", "))
    end)
  end

  defp build_oauth2_attrs(selected_provider, form, sso_enforced, sso_automatic_enrollment) do
    {sso_organization_id, authorize_url, token_url, user_info_url} =
      extract_oauth2_urls(selected_provider, form)

    attrs = %{
      sso_organization_id: sso_organization_id,
      sso_enforced: sso_enforced,
      sso_login_domain: normalize_domain(form["sso_login_domain"]),
      sso_automatic_enrollment: sso_automatic_enrollment,
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

    {domain, Accounts.okta_authorize_url(domain), Accounts.okta_token_url(domain), Accounts.okta_userinfo_url(domain)}
  end

  defp extract_oauth2_urls("oauth2", form) do
    {String.trim(form["oauth2_site"] || ""), String.trim(form["oauth2_authorize_url"] || ""),
     String.trim(form["oauth2_token_url"] || ""), String.trim(form["oauth2_user_info_url"] || "")}
  end

  defp validate_sso_enforcement(%{assigns: %{sso_enforced: false}}), do: :ok

  defp validate_sso_enforcement(%{assigns: %{current_user: current_user}} = socket) do
    provider = provider_atom(socket.assigns.selected_provider)

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

  defp provider_atom("google"), do: :google
  defp provider_atom("okta"), do: :okta
  defp provider_atom("oauth2"), do: :oauth2

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
        sso_automatic_enrollment: socket.assigns.sso_automatic_enrollment,
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
        socket.assigns.sso_automatic_enrollment != saved.sso_automatic_enrollment or
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
      "oauth2_client_secret" => "",
      "sso_login_domain" => organization.sso_login_domain || ""
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
      "oauth2_user_info_url" => organization.oauth2_user_info_url || "",
      "sso_login_domain" => organization.sso_login_domain || ""
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
      "sso_login_domain" => "",
      "oauth2_authorize_url" => "",
      "oauth2_token_url" => "",
      "oauth2_user_info_url" => ""
    }
  end

  defp normalize_domain(nil), do: nil

  defp normalize_domain(domain) do
    case domain |> String.trim() |> String.trim_trailing(".") |> String.downcase() do
      "" -> nil
      normalized_domain -> normalized_domain
    end
  end

  defp changeset_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  defp automatic_enrollment_toggle_disabled?(selected_provider, organization, form_params, automatic_enrollment) do
    selected_provider in ["okta", "oauth2"] and
      not verified_login_domain_selected?(selected_provider, organization, form_params) and
      not automatic_enrollment
  end

  defp sso_enforcement_toggle_disabled?(selected_provider, organization, form_params, enforced) do
    legacy_enforcement? = legacy_sso_enforcement?(selected_provider, organization)

    selected_provider in ["okta", "oauth2"] and
      not verified_login_domain_selected?(selected_provider, organization, form_params) and
      not legacy_enforcement? and
      not enforced
  end

  defp verified_login_domain_selected?(selected_provider, organization, form_params) do
    selected_provider in ["okta", "oauth2"] and
      not is_nil(organization.sso_login_domain_verified_at) and
      normalize_domain(form_params["sso_login_domain"]) == organization.sso_login_domain
  end

  defp legacy_sso_enforcement?(selected_provider, organization) do
    organization.sso_legacy_email_domain_fallback and
      selected_provider == provider_name(organization.sso_provider)
  end

  defp provider_name(nil), do: nil
  defp provider_name(provider), do: Atom.to_string(provider)
end
