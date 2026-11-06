defmodule TuistWeb.Components.AmpWorkspaces do
  @moduledoc """
  Connects Amp workspaces to an account, so Orbs in them exchange Amp identity
  tokens for Tuist CI tokens without a trust policy.
  """
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Authorization
  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.UnauthorizedError

  @audience_prefix "tuist-amp-connect:"

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:form_version, fn -> 0 end)
      |> assign_new(:audience, &new_audience/0)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("open", _, socket) do
    {:noreply,
     socket
     |> load()
     |> assign(error: nil)
     |> push_event("open-modal", %{id: "connect-amp-workspace-modal"})}
  end

  def handle_event("cancel", _, socket), do: {:noreply, close_modal(socket)}

  def handle_event("connect", %{"token" => token}, socket) do
    socket = load(socket)

    # The audience names this page's single-use challenge, so a token minted
    # for login or for another connection attempt cannot be replayed here.
    with {:ok, workspace_id} <- OIDC.amp_workspace_id(String.trim(token), socket.assigns.audience),
         {:ok, _connection} <- Accounts.create_amp_workspace_connection(socket.assigns.account, workspace_id) do
      {:noreply, socket |> load() |> close_modal()}
    else
      error -> {:noreply, assign(socket, error: connect_error(error))}
    end
  end

  def handle_event("disconnect", %{"id" => id}, socket) do
    socket = load(socket)
    _ = Accounts.delete_amp_workspace_connection(socket.assigns.account, id)
    {:noreply, load(socket)}
  end

  defp connect_error({:error, :missing_amp_workspace_claim}),
    do:
      dgettext(
        "dashboard_integrations",
        "This token comes from a personal Amp thread. Run the command in a thread of a workspace project."
      )

  defp connect_error({:error, %Ecto.Changeset{}}),
    do: dgettext("dashboard_integrations", "This Amp workspace is already connected.")

  defp connect_error(_),
    do:
      dgettext(
        "dashboard_integrations",
        "The token is not valid for this connection. Run the command again and paste the new token within 10 minutes."
      )

  defp close_modal(socket) do
    socket
    |> push_event("close-modal", %{id: "connect-amp-workspace-modal"})
    |> assign(error: nil, form_version: socket.assigns.form_version + 1, audience: new_audience())
  end

  defp new_audience do
    @audience_prefix <> (18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
  end

  # Reload the account and reauthorize on every event, including events from
  # pages opened before the user lost access.
  defp load(socket) do
    account = Repo.get!(Account, socket.assigns.account.id)

    if Authorization.authorize(:account_update, socket.assigns.current_user, account) != :ok do
      raise UnauthorizedError
    end

    assign(socket, account: account, connections: Accounts.list_amp_workspace_connections(account))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} data-part="amp-workspaces-card-section" class="noora-card__section">
      <div data-part="header-row">
        <div data-part="header">
          <span data-part="title">Amp</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_integrations",
              "Let Amp Orbs in your workspaces sign in to Tuist without a stored token. Orbs get CI access, including cache uploads, to every project in this account."
            )}
          </span>
        </div>
        <div data-part="actions">
          <.button
            type="button"
            label={dgettext("dashboard_integrations", "Connect workspace")}
            variant={if @connections == [], do: "primary", else: "secondary"}
            phx-click="open"
            phx-target={@myself}
          />
        </div>
      </div>
      <div
        :for={connection <- @connections}
        id={"amp-workspace-#{connection.id}"}
        data-part="workspace"
      >
        <div data-part="details">
          <span data-part="name">
            {dgettext("dashboard_integrations", "Workspace %{id}", id: connection.workspace_id)}
          </span>
          <span data-part="meta">
            {dgettext("dashboard_integrations", "Connected %{time}",
              time: DateFormatter.from_now(connection.inserted_at)
            )}
          </span>
        </div>
        <.button
          type="button"
          label={dgettext("dashboard_integrations", "Disconnect")}
          variant="secondary"
          size="small"
          phx-click="disconnect"
          phx-value-id={connection.id}
          phx-target={@myself}
        />
      </div>
      <.modal
        id="connect-amp-workspace-modal"
        title={dgettext("dashboard_integrations", "Connect an Amp workspace")}
        header_size="large"
      >
        <:trigger :let={attrs}>
          <button type="button" hidden aria-hidden="true" tabindex="-1" {attrs} />
        </:trigger>
        <.line_divider />
        <form
          id={"amp-workspace-form-#{@form_version}"}
          phx-submit="connect"
          phx-target={@myself}
          data-part="amp-workspace-form"
          autocomplete="off"
        >
          <.alert :if={@error} status="error" type="secondary" size="small" title={@error} />
          <ol>
            <li>
              {dgettext(
                "dashboard_integrations",
                "In a thread of the workspace that runs in an Orb, run this command:"
              )}
              <div data-part="command">
                <code id="amp-workspace-command">amp orb id-token --audience {@audience}</code>
                <.button
                  id="copy-amp-workspace-command"
                  variant="secondary"
                  size="small"
                  icon_only
                  type="button"
                  phx-hook="Clipboard"
                  data-clipboard-value={"amp orb id-token --audience #{@audience}"}
                  aria-label={dgettext("dashboard_integrations", "Copy command")}
                >
                  <.copy />
                </.button>
              </div>
            </li>
            <li>
              {dgettext(
                "dashboard_integrations",
                "Paste the token it prints. It proves the Orb runs in the workspace and only works for this connection."
              )}
            </li>
          </ol>
          <.text_input
            id={"amp-workspace-token-#{@form_version}"}
            name="token"
            type="password"
            input_type="password"
            label={dgettext("dashboard_integrations", "Amp identity token")}
            placeholder="eyJ…"
            value=""
            required
            show_required
          />
          <div data-part="actions">
            <.button
              type="button"
              label={dgettext("dashboard_integrations", "Cancel")}
              variant="secondary"
              phx-click="cancel"
              phx-target={@myself}
            />
            <.button
              type="submit"
              label={dgettext("dashboard_integrations", "Connect")}
              variant="primary"
            />
          </div>
        </form>
      </.modal>
    </section>
    """
  end
end
