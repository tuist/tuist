defmodule TuistWeb.Components.WorkloadIdentities do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import Phoenix.LiveView, only: [put_flash: 3]
  import TuistWeb.Components.JSONInput

  alias Ecto.Changeset
  alias Tuist.Accounts
  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.Authorization
  alias TuistWeb.Errors.UnauthorizedError

  @policy_fields [:name, :issuer, :jwks_url, :audience, :claims]

  embed_templates "workload_identities.html"

  def initialize(socket) do
    account = authorize_account_update!(socket)
    policies = Accounts.list_oidc_trust_policies(account)

    socket
    |> assign(oidc_trust_policies: policies, oidc_configuration_visible: policies != [])
    |> assign_empty_form()
  end

  def handle_event("toggle_oidc_configuration", %{"checked" => checked}, socket) when is_boolean(checked) do
    {:noreply, assign(socket, :oidc_configuration_visible, checked)}
  end

  def handle_event("toggle_oidc_configuration", _params, socket), do: {:noreply, socket}

  def handle_event("select_oidc_template", %{"value" => [template]}, socket) when template in ["custom", "fly"] do
    socket = assign(socket, :oidc_template, template)

    socket =
      if template == "fly",
        do: populate_fly_template(socket, socket.assigns.policy_params, socket.assigns.fly_template),
        else: socket

    {:noreply, socket}
  end

  def handle_event("select_oidc_template", _params, socket), do: {:noreply, socket}

  def handle_event("change_oidc_trust_policy", %{"oidc_trust_policy" => attrs} = params, socket) when is_map(attrs) do
    {:noreply, update_policy_form(socket, attrs, params)}
  end

  def handle_event("create_oidc_trust_policy", %{"oidc_trust_policy" => attrs} = params, socket) when is_map(attrs) do
    account = authorize_account_update!(socket)
    socket = update_policy_form(socket, attrs, params)
    attrs = socket.assigns.policy_params
    claims_input = Map.get(attrs, "claims", "")

    with :ok <- validate_template(socket),
         {:ok, claims} <- decode_claims(claims_input),
         {:ok, _policy} <- Accounts.create_oidc_trust_policy(account, Map.put(attrs, "claims", claims)) do
      {:noreply,
       socket
       |> assign(oidc_trust_policies: Accounts.list_oidc_trust_policies(account))
       |> assign_empty_form()
       |> put_flash(:info, dgettext("dashboard_account", "Trust policy added."))}
    else
      {:error, :invalid_template} ->
        {:noreply,
         assign(socket,
           form_errors: [
             dgettext(
               "dashboard_account",
               "Enter a valid Fly.io organization slug and numeric organization and application IDs."
             )
           ]
         )}

      {:error, :invalid_claims_json, message} ->
        changeset =
          attrs
          |> Map.delete("claims")
          |> OIDCTrustPolicy.changeset()
          |> Changeset.add_error(:claims, message)
          |> Map.put(:action, :insert)

        {:noreply, assign_form(socket, changeset, claims_input)}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, %{changeset | action: changeset.action || :insert}, claims_input)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(claims_input: claims_input)
         |> put_flash(:error, dgettext("dashboard_account", "The trust policy could not be added."))}
    end
  end

  def handle_event("delete_oidc_trust_policy", %{"policy-id" => policy_id}, socket) do
    account = authorize_account_update!(socket)

    with {id, ""} <- Integer.parse(to_string(policy_id)),
         {:ok, _policy} <- Accounts.delete_oidc_trust_policy(account, id) do
      {:noreply,
       socket
       |> assign(oidc_trust_policies: Accounts.list_oidc_trust_policies(account))
       |> put_flash(:info, dgettext("dashboard_account", "Trust policy removed."))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_account", "Trust policy not found."))}
    end
  end

  attr :form, :any, required: true
  attr :claims_input, :string, required: true

  defp identity_fields(assigns) do
    ~H"""
    <div data-part="identity-fields">
      <.text_input
        label={dgettext("dashboard_account", "Issuer URL")}
        field={@form[:issuer]}
        error={field_error(@form[:issuer])}
        type="basic"
        placeholder="https://identity.example.com"
      />
      <.text_input
        label={dgettext("dashboard_account", "JWKS URL")}
        field={@form[:jwks_url]}
        error={field_error(@form[:jwks_url])}
        type="basic"
        placeholder="https://identity.example.com/.well-known/jwks.json"
      />
      <.json_input
        id="oidc-trust-policy-claims"
        label={dgettext("dashboard_account", "Claims")}
        name={@form[:claims].name}
        value={@claims_input}
        error={field_error(@form[:claims])}
        hint={
          dgettext(
            "dashboard_account",
            "A JSON object with 1 to 10 claims. Values must be strings, integers, or booleans and match exactly."
          )
        }
        placeholder={~s({"sub": "service:production"})}
      />
    </div>
    """
  end

  defp decode_claims(input) when is_binary(input) and byte_size(input) <= 8192 do
    case input |> String.trim() |> JSON.decode() do
      {:ok, claims} when is_map(claims) ->
        {:ok, claims}

      {:ok, _other} ->
        {:error, :invalid_claims_json, dgettext("dashboard_account", "Claims must be a JSON object.")}

      {:error, _reason} ->
        {:error, :invalid_claims_json, dgettext("dashboard_account", "Claims must be valid JSON.")}
    end
  end

  defp decode_claims(_input) do
    {:error, :invalid_claims_json, dgettext("dashboard_account", "Claims must be valid JSON of at most 8 KiB.")}
  end

  defp assign_empty_form(socket) do
    socket
    |> assign(
      oidc_template: "custom",
      fly_template: empty_fly_template(),
      edited_fields: MapSet.new(),
      identity_overridden?: false
    )
    |> assign_form(OIDCTrustPolicy.changeset(%{}), "")
  end

  defp empty_fly_template, do: %{"organization_slug" => "", "organization_id" => "", "application_id" => ""}

  defp update_policy_form(socket, attrs, params) do
    attrs = Map.take(attrs, Enum.map(@policy_fields, &Atom.to_string/1))
    fly = normalize_fly_template(Map.get(params, "fly_template", socket.assigns.fly_template))
    helper_changed? = fly != socket.assigns.fly_template
    edited = socket.assigns.edited_fields

    edited =
      case params["_target"] do
        ["oidc_trust_policy", field] when is_map_key(attrs, field) ->
          MapSet.put(edited, field)

        nil when not helper_changed? ->
          Enum.reduce(attrs, edited, fn {field, value}, edited ->
            if value == socket.assigns.policy_params[field], do: edited, else: MapSet.put(edited, field)
          end)

        _ ->
          edited
      end

    socket = assign(socket, :edited_fields, edited)

    if socket.assigns.oidc_template == "fly" do
      populate_fly_template(socket, attrs, fly)
    else
      assign_form(socket, OIDCTrustPolicy.changeset(Map.delete(attrs, "claims")), Map.get(attrs, "claims", ""))
    end
  end

  defp normalize_fly_template(params) when is_map(params) do
    Map.new(empty_fly_template(), fn {key, _} ->
      value = Map.get(params, key, "")
      {key, if(is_binary(value) and byte_size(value) <= 255, do: String.trim(value), else: "")}
    end)
  end

  defp normalize_fly_template(_), do: empty_fly_template()

  defp populate_fly_template(socket, params, fly) do
    issuer =
      if valid_fly_slug?(fly["organization_slug"]), do: "https://oidc.fly.io/" <> fly["organization_slug"], else: ""

    claims =
      if valid_fly_id?(fly["organization_id"]) and valid_fly_id?(fly["application_id"]) do
        JSON.encode!(%{"org_id" => fly["organization_id"], "app_id" => fly["application_id"]})
      else
        ""
      end

    values = %{
      "name" => "Fly.io Machines",
      "issuer" => issuer,
      "jwks_url" => if(issuer == "", do: "", else: issuer <> "/.well-known/jwks"),
      "audience" => "tuist",
      "claims" => claims
    }

    # Queued helper events may contain stale generated browser values.
    params =
      Enum.reduce(values, params, fn {key, value}, params ->
        if MapSet.member?(socket.assigns.edited_fields, key), do: params, else: Map.put(params, key, value)
      end)

    identity_overridden? = Enum.any?(~w(issuer jwks_url claims), &(params[&1] != values[&1]))

    socket
    |> assign(fly_template: fly, identity_overridden?: identity_overridden?)
    |> assign_form(OIDCTrustPolicy.changeset(Map.delete(params, "claims")), Map.get(params, "claims", ""))
  end

  defp validate_template(%{assigns: %{oidc_template: "custom"}}), do: :ok

  defp validate_template(%{assigns: %{fly_template: fly}}) do
    if valid_fly_slug?(fly["organization_slug"]) and valid_fly_id?(fly["organization_id"]) and
         valid_fly_id?(fly["application_id"]), do: :ok, else: {:error, :invalid_template}
  end

  defp valid_fly_slug?(value), do: Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, value)
  defp valid_fly_id?(value), do: byte_size(value) in 1..64 and Regex.match?(~r/\A[0-9]+\z/, value)

  defp assign_form(socket, changeset, claims_input) do
    defaults = %{"name" => "", "issuer" => "", "jwks_url" => "", "audience" => "tuist"}
    params = defaults |> Map.merge(changeset.params || %{}) |> Map.put("claims", claims_input)

    socket
    |> assign(oidc_trust_policy_form: to_form(changeset, as: :oidc_trust_policy))
    |> assign(claims_input: claims_input)
    |> assign(policy_params: params)
    |> assign(form_errors: unrendered_errors(changeset))
  end

  defp unrendered_errors(%Changeset{action: nil}), do: []

  defp unrendered_errors(%Changeset{errors: errors}) do
    for {field, error} <- errors, field not in @policy_fields, do: translate_error(error)
  end

  defp identity_errors?(form), do: Enum.any?([:issuer, :jwks_url, :claims], &(form[&1].errors != []))
  defp field_error(%Phoenix.HTML.FormField{errors: [error | _]}), do: translate_error(error)
  defp field_error(_field), do: nil

  defp format_claims(claims) when is_map(claims) do
    IO.iodata_to_binary(:json.format(claims))
  end

  defp authorize_account_update!(socket) do
    {:ok, account} = Accounts.get_account_by_id(socket.assigns.selected_account.id)

    if Authorization.authorize(:account_update, socket.assigns.current_user, account) != :ok do
      raise UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    account
  end
end
