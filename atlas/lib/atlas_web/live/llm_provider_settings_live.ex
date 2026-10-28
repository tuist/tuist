defmodule AtlasWeb.LLMProviderSettingsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.LLMs.Connections

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("AI accounts"))
     |> assign(:login, nil)
     |> assign(:busy, false)
     |> assign(:cancel_start?, false)
     |> assign(:selected_provider, nil)
     |> assign(:provider_modal_open?, false)
     |> assign(:disconnect_provider, nil)
     |> assign(:claude_form, empty_form())
     |> stream_configure(:providers, dom_id: &"provider-#{&1.provider}")
     |> assign_providers()}
  end

  def handle_event("open_provider_modal", _params, socket) do
    {:noreply, socket |> reset_provider_modal() |> assign(:provider_modal_open?, true)}
  end

  def handle_event("configure_provider", %{"provider" => provider}, socket) when provider in ["claude", "chatgpt"] do
    {:noreply,
     socket
     |> reset_provider_modal()
     |> assign(selected_provider: provider, provider_modal_open?: true)
     |> push_event("open-modal", %{id: "add-provider-modal"})}
  end

  def handle_event("select_provider", %{"value" => [provider]}, socket) when provider in ["claude", "chatgpt"] do
    if socket.assigns.selected_provider == provider do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> reset_provider_modal()
       |> assign(selected_provider: provider, provider_modal_open?: true)}
    end
  end

  def handle_event("select_provider", _params, socket), do: {:noreply, socket}

  def handle_event("provider_modal_changed", %{"open" => false}, socket), do: {:noreply, reset_provider_modal(socket)}
  def handle_event("provider_modal_changed", _params, socket), do: {:noreply, socket}

  def handle_event("close_provider_modal", _params, socket) do
    {:noreply, socket |> reset_provider_modal() |> push_event("close-modal", %{id: "add-provider-modal"})}
  end

  def handle_event("start_chatgpt", _params, %{assigns: %{selected_provider: "chatgpt", busy: false}} = socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:chatgpt_start, fn -> audited(user, fn -> Connections.start_chatgpt(user) end) end)}
  end

  def handle_event("start_chatgpt", _params, socket), do: {:noreply, socket}

  def handle_event("request_disconnect", %{"provider" => provider}, socket) when provider in ["claude", "chatgpt"] do
    {:noreply,
     socket
     |> assign(:disconnect_provider, provider)
     |> push_event("open-modal", %{id: "disconnect-provider-modal"})}
  end

  def handle_event("cancel_disconnect", _params, socket) do
    {:noreply,
     socket
     |> assign(:disconnect_provider, nil)
     |> push_event("close-modal", %{id: "disconnect-provider-modal"})}
  end

  def handle_event("disconnect", _params, %{assigns: %{disconnect_provider: nil}} = socket), do: {:noreply, socket}

  def handle_event("disconnect", _params, socket) do
    case Connections.disconnect(socket.assigns.current_user, socket.assigns.disconnect_provider) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(:disconnect_provider, nil)
         |> assign_providers()
         |> push_event("close-modal", %{id: "disconnect-provider-modal"})
         |> put_flash(:info, gettext("Account disconnected from Atlas."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not disconnect the account."))}
    end
  end

  def handle_event("cancel_chatgpt", _params, socket) do
    {:noreply,
     socket
     |> reset_provider_modal()
     |> assign(selected_provider: "chatgpt", provider_modal_open?: true)}
  end

  def handle_async(:chatgpt_start, result, %{assigns: %{cancel_start?: true}} = socket) do
    case result do
      {:ok, {:ok, login}} -> Connections.cancel_chatgpt(socket.assigns.current_user, login.login_id)
      _result -> :ok
    end

    {:noreply, assign(socket, busy: false, cancel_start?: false)}
  end

  def handle_async(:chatgpt_poll, _result, %{assigns: %{login: nil}} = socket), do: {:noreply, socket}

  def handle_async(:chatgpt_poll, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:chatgpt_start, {:ok, {:ok, login}}, socket) do
    schedule_poll(login)
    {:noreply, assign(socket, login: login, busy: false)}
  end

  def handle_async(:chatgpt_start, _result, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(
       :error,
       gettext("Could not start ChatGPT sign-in. Check that it is enabled, or wait for an existing sign-in to expire.")
     )}
  end

  def handle_async(:chatgpt_poll, {:ok, {:ok, %{status: "pending"}}}, socket) do
    if socket.assigns.login, do: schedule_poll(socket.assigns.login)
    {:noreply, socket}
  end

  def handle_async(:chatgpt_poll, {:ok, {:ok, %{status: "connected"}}}, socket) do
    {:noreply,
     socket
     |> assign(login: nil, selected_provider: nil, provider_modal_open?: false)
     |> assign_providers()
     |> push_event("close-modal", %{id: "add-provider-modal"})
     |> put_flash(:info, gettext("ChatGPT connected."))}
  end

  def handle_async(:chatgpt_poll, {:ok, {:error, :provider_unavailable}}, socket) do
    if socket.assigns.login, do: schedule_poll(socket.assigns.login)
    {:noreply, socket}
  end

  def handle_async(:chatgpt_poll, _result, socket) do
    {:noreply,
     socket
     |> assign(:login, nil)
     |> assign_providers()
     |> put_flash(:error, gettext("ChatGPT sign-in did not complete. Please try again."))}
  end

  def handle_info({:poll_chatgpt, id}, %{assigns: %{login: %{login_id: id}}} = socket) do
    user = socket.assigns.current_user

    {:noreply,
     start_async(socket, :chatgpt_poll, fn -> audited(user, fn -> Connections.poll_chatgpt(user, id) end) end)}
  end

  def handle_info({:poll_chatgpt, _id}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <section id="llm-provider-settings" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("AI accounts")}</h1>
          <p data-part="description">
            {gettext("Connect your Claude or ChatGPT account for future agent sessions.")}
          </p>
        </div>
        <.modal
          id="add-provider-modal"
          data-part="provider-modal"
          title={gettext("Connect account")}
          description={gettext("Connect your Claude or ChatGPT account to Atlas.")}
          header_type="icon"
          on_dismiss="close_provider_modal"
          on_open_change="provider_modal_changed"
        >
          <:header_icon><.lock /></:header_icon>
          <:trigger :let={attrs}>
            <.button
              id="add-ai-provider"
              label={gettext("Connect account")}
              size="medium"
              phx-click="open_provider_modal"
              {attrs}
            >
              <:icon_left><.plus /></:icon_left>
            </.button>
          </:trigger>
          <div :if={@provider_modal_open?} data-part="provider-modal-content">
            <div data-part="provider-selector">
              <.select
                id="llm-provider-select"
                name="provider"
                value={@selected_provider}
                label={gettext("Choose service")}
                on_value_change="select_provider"
              >
                <:item value="claude" label="Claude" />
                <:item value="chatgpt" label="ChatGPT" />
              </.select>
              <p data-part="description">
                {gettext("Credentials are encrypted and belong only to your Atlas account.")}
              </p>
            </div>
            <div
              :if={@selected_provider == "claude"}
              id="claude-provider-setup"
              data-part="provider-setup"
            >
              <p>
                {gettext(
                  "On your computer, install Claude Code, run the command below, sign in with your Claude account, and paste the generated token here."
                )}
              </p>
              <code data-part="provider-code">claude setup-token</code>
              <p data-part="description">
                {gettext(
                  "This is a Claude Code subscription token, not an Anthropic API key. Saving it does not verify access. Subscription terms and eligibility apply."
                )}
              </p>
              <.form
                for={@claude_form}
                id="claude-provider-form"
                data-part="credential-form"
                action={~p"/settings/llm-providers/claude"}
                method="post"
              >
                <.text_input
                  field={@claude_form[:token]}
                  id="claude-token"
                  type="password"
                  label={gettext("Claude token")}
                  autocomplete="off"
                  show_suffix={false}
                  required
                />
              </.form>
            </div>
            <div
              :if={@selected_provider == "chatgpt"}
              id="chatgpt-provider-setup"
              data-part="provider-setup"
            >
              <p>
                {gettext(
                  "Sign in with ChatGPT to connect your subscription. You will authorize the connection on OpenAI's website; Atlas never asks for your password."
                )}
              </p>
              <.alert
                :if={!@chatgpt.login_available}
                id="chatgpt-unavailable"
                status="information"
                size="small"
                title={gettext("ChatGPT sign-in has not been enabled by your Atlas administrator.")}
              />
              <.button
                :if={is_nil(@login)}
                id="connect-chatgpt-provider"
                label={gettext("Sign in with ChatGPT")}
                size="medium"
                phx-click="start_chatgpt"
                disabled={!@chatgpt.login_available or @busy}
              />
              <div :if={@login} id="chatgpt-device-login" data-part="provider-setup">
                <p>
                  {gettext(
                    "Open the link and enter this one-time code. It expires in 15 minutes. Only authorize it if you started this sign-in yourself."
                  )}
                </p>
                <code id="chatgpt-user-code" data-part="provider-code">{@login.user_code}</code>
                <.button
                  id="chatgpt-verification-link"
                  label={gettext("Continue to ChatGPT")}
                  size="medium"
                  href={@login.verification_url}
                  target="_blank"
                  rel="noopener noreferrer"
                />
                <.button
                  id="cancel-chatgpt-login"
                  label={gettext("Cancel sign-in")}
                  variant="secondary"
                  size="medium"
                  phx-click="cancel_chatgpt"
                />
              </div>
            </div>
          </div>
          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  size="medium"
                  phx-click="close_provider_modal"
                />
              </:action>
              <:action :if={@selected_provider == "claude"}>
                <.button
                  id="save-claude-provider"
                  label={gettext("Save connection")}
                  form="claude-provider-form"
                  type="submit"
                  size="medium"
                />
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
      </div>
      <.card title={gettext("Connected accounts")} icon="lock">
        <.card_section data-part="providers-table-section">
          <div :if={@providers_empty?} id="providers-empty-state">
            <.table_empty_state
              icon="lock"
              title={gettext("No AI accounts connected")}
              subtitle={gettext("Connect your Claude or ChatGPT account to Atlas.")}
            />
          </div>
          <.table :if={!@providers_empty?} id="ai-providers-table" rows={@streams.providers}>
            <:col :let={{_id, provider}} label={gettext("Service")}>
              <.text_and_description_cell
                label={provider_name(provider.provider)}
                description={credential_type(provider.provider)}
              />
            </:col>
            <:col label={gettext("Status")}>
              <.badge_cell label={gettext("Credentials saved")} color="neutral" style="light-fill" />
            </:col>
            <:col :let={{_id, provider}} label={gettext("Updated")}>
              <.text_cell label={Calendar.strftime(provider.updated_at, "%b %-d, %Y")} />
            </:col>
            <:col :let={{_id, provider}} label={gettext("Actions")}>
              <.button_cell>
                <:button>
                  <.dropdown id={"provider-actions-#{provider.provider}"} icon_only>
                    <:icon><.dots_vertical /></:icon>
                    <.dropdown_item
                      id={"update-#{provider.provider}-provider"}
                      label={gettext("Update credentials")}
                      value="update"
                      phx-click="configure_provider"
                      phx-value-provider={provider.provider}
                    >
                      <:left_icon><.settings /></:left_icon>
                    </.dropdown_item>
                    <.dropdown_item
                      id={"disconnect-#{provider.provider}-provider"}
                      label={gettext("Disconnect")}
                      value="disconnect"
                      phx-click="request_disconnect"
                      phx-value-provider={provider.provider}
                    >
                      <:left_icon><.logout /></:left_icon>
                    </.dropdown_item>
                  </.dropdown>
                </:button>
              </.button_cell>
            </:col>
          </.table>
        </.card_section>
      </.card>
      <.modal
        id="disconnect-provider-modal"
        title={gettext("Disconnect account")}
        description={gettext("Remove the saved credentials from your Atlas account.")}
        header_type="icon"
        on_dismiss="cancel_disconnect"
      >
        <:header_icon><.logout /></:header_icon>
        <:trigger :let={attrs}>
          <div data-part="hidden-trigger">
            <button type="button" tabindex="-1" aria-hidden="true" {attrs}></button>
          </div>
        </:trigger>
        <p :if={@disconnect_provider} data-part="disconnect-provider-description">
          {gettext(
            "Disconnect %{provider}? Atlas will delete its saved credentials. Revoke access separately in your Claude or OpenAI account settings.",
            provider: provider_name(@disconnect_provider)
          )}
        </p>
        <:footer>
          <.modal_footer>
            <:action>
              <.button label={gettext("Cancel")} variant="secondary" phx-click="cancel_disconnect" />
            </:action>
            <:action>
              <.button
                id="confirm-disconnect-provider"
                label={gettext("Disconnect")}
                variant="destructive"
                phx-click="disconnect"
              />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>
    </section>
    """
  end

  defp assign_providers(socket) do
    providers = Connections.list(socket.assigns.current_user)
    configured = Enum.filter(providers, & &1.credential_configured)

    socket
    |> assign(:chatgpt, Enum.find(providers, &(&1.provider == "chatgpt")))
    |> assign(:providers_empty?, configured == [])
    |> stream(:providers, configured, reset: true)
  end

  defp reset_provider_modal(socket) do
    socket = cancel_async(socket, :chatgpt_poll)
    if socket.assigns.login, do: Connections.cancel_chatgpt(socket.assigns.current_user, socket.assigns.login.login_id)

    assign(socket,
      login: nil,
      cancel_start?: socket.assigns.busy,
      selected_provider: nil,
      provider_modal_open?: false,
      claude_form: empty_form()
    )
  end

  defp provider_name("claude"), do: "Claude"
  defp provider_name("chatgpt"), do: "ChatGPT"
  defp credential_type("claude"), do: gettext("Claude Code subscription")
  defp credential_type("chatgpt"), do: gettext("ChatGPT subscription")
  defp empty_form, do: to_form(%{"token" => ""}, as: "claude")
  defp schedule_poll(login), do: Process.send_after(self(), {:poll_chatgpt, login.login_id}, login.interval * 1000)
  defp audited(user, fun), do: Audit.with_context(%{actor: user, interface: "dashboard"}, fun)
end
