defmodule AtlasWeb.Admin.InferenceProvidersLive do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Inference
  alias Atlas.Inference.Provider

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(
         :error,
         gettext("Log in to review inference providers.")
       )
       |> redirect(to: ~p"/login")}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("Inference providers · Atlas"))
       |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
       |> assign_providers()}
    end
  end

  @impl true
  def handle_event("validate_provider", %{"provider" => params}, socket) do
    changeset =
      %Provider{}
      |> Inference.change_provider(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_provider_form(socket, changeset)}
  end

  def handle_event("create_provider", %{"provider" => params}, socket) do
    case Inference.create_provider(params) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Provider created."))
         |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
         |> assign_providers()
         |> push_event("close-modal", %{id: "new-inference-provider-modal"})}

      {:error, changeset} ->
        {:noreply, assign_provider_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("open_new_provider", _params, socket) do
    {:noreply,
     socket
     |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
     |> push_event("open-modal", %{id: "new-inference-provider-modal"})}
  end

  def handle_event("close_new_provider", _params, socket) do
    {:noreply,
     socket
     |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
     |> push_event("close-modal", %{id: "new-inference-provider-modal"})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="admin-inference-providers">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{gettext("Providers")}</h1>
          <p>
            {gettext(
              "Create upstream endpoints that profiles can target. Credentials are encrypted and are never shown after saving."
            )}
          </p>
        </div>
      </div>

      <.card title={gettext("Providers")} icon="server" data-part="providers-card">
        <:actions>
          <.new_provider_modal provider_form={@provider_form} />
        </:actions>
        <.card_section>
          <p data-part="card-intro">
            {gettext("Runtime-managed and environment-backed endpoints with profile references.")}
          </p>

          <.table id="inference-providers-table" rows={@providers}>
            <:col :let={provider} label={gettext("Provider")}>
              <.text_and_description_cell
                icon="server"
                label={provider.id}
                description={provider_description(provider)}
              />
            </:col>
            <:col :let={provider} label={gettext("Status")}>
              <% status = provider_status(provider) %>
              <.badge_cell label={status.label} color={status.color} style="light-fill" />
            </:col>
            <:col :let={provider} label={gettext("Endpoint")}>
              <div data-part="route-cell">
                <code :if={provider.base_url}>{provider.base_url}</code>
                <span :if={!provider.base_url}>{gettext("Not configured")}</span>
              </div>
            </:col>
            <:col :let={provider} label={gettext("Credential")}>
              <.text_cell label={credential_label(provider)} />
            </:col>
            <:col :let={provider} label={gettext("Timeout")}>
              <.text_cell label={timeout_label(provider.timeout)} />
            </:col>
            <:col :let={provider} label={gettext("Profiles")}>
              <.text_cell label={profile_count_label(provider.profile_count)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="server"
                title={gettext("No inference providers")}
                subtitle={gettext("Create a provider before creating profiles that route to it.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :provider_form, :map, required: true

  defp new_provider_modal(assigns) do
    ~H"""
    <.modal
      id="new-inference-provider-modal"
      title={gettext("Create provider")}
      description={gettext("Add an upstream endpoint that profiles can route requests to.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_provider"
    >
      <:trigger :let={attrs}>
        <.button
          label={gettext("Create provider")}
          size="medium"
          variant="primary"
          phx-click="open_new_provider"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="server" />
      </:header_icon>

      <.form
        id="new-inference-provider-form"
        for={@provider_form}
        phx-change="validate_provider"
        phx-submit="create_provider"
        data-part="form"
      >
        <.text_input
          id="new-inference-provider-key"
          field={@provider_form[:key]}
          label={gettext("Provider key")}
          placeholder="togetherai"
        />
        <.text_input
          id="new-inference-provider-endpoint"
          field={@provider_form[:base_url]}
          label={gettext("Endpoint")}
          input_type="url"
          placeholder="https://api.together.ai/v1"
        />
        <.text_input
          id="new-inference-provider-credential"
          field={@provider_form[:api_key]}
          label={gettext("Credential")}
          input_type="password"
          placeholder="provider-token"
        />
        <.text_input
          id="new-inference-provider-timeout"
          field={@provider_form[:timeout]}
          label={gettext("Timeout in milliseconds")}
          input_type="number"
          min="1"
          step="1"
          placeholder="300000"
        />
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_new_provider"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Create")}
              size="medium"
              variant="primary"
              type="submit"
              form="new-inference-provider-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp provider_status(%{configured?: false}), do: %{label: gettext("Missing"), color: "warning"}

  defp provider_status(%{endpoint_configured?: false}), do: %{label: gettext("No endpoint"), color: "destructive"}

  defp provider_status(%{credential_configured?: false}), do: %{label: gettext("No credential"), color: "warning"}

  defp provider_status(_provider), do: %{label: gettext("Ready"), color: "success"}

  defp provider_description(%{source: :database}), do: gettext("Managed in Atlas")

  defp provider_description(%{source: :environment}), do: gettext("Configured from the environment")

  defp provider_description(_provider), do: gettext("Referenced by profiles but not configured")

  defp credential_label(%{credential_configured?: true}), do: gettext("Configured")

  defp credential_label(_provider), do: gettext("Missing")

  defp timeout_label(nil), do: gettext("Not configured")

  defp timeout_label(timeout) when is_integer(timeout) and rem(timeout, 1_000) == 0 do
    seconds = div(timeout, 1_000)

    if seconds == 1 do
      gettext("1 second")
    else
      gettext("%{count} seconds", count: seconds)
    end
  end

  defp timeout_label(timeout) when is_integer(timeout) do
    if timeout == 1 do
      gettext("1 millisecond")
    else
      gettext("%{count} milliseconds", count: timeout)
    end
  end

  defp profile_count_label(1), do: gettext("1 profile")

  defp profile_count_label(count), do: gettext("%{count} profiles", count: count)

  defp assign_providers(socket) do
    assign(socket, :providers, Inference.list_provider_configs())
  end

  defp assign_provider_form(socket, changeset) do
    assign(socket, :provider_form, to_form(changeset, as: :provider))
  end
end
