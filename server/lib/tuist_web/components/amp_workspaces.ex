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
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.UnauthorizedError

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:form_version, fn -> 0 end)

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

  # Like Amp's own trust recipes (Google Cloud, AWS, Tailscale), the account
  # admin names the workspace; Amp's signature on each orb token proves the rest.
  def handle_event("connect", params, socket) do
    socket = load(socket)
    attrs = Map.new(["workspace_id", "project_id"], &{&1, params |> Map.get(&1, "") |> String.trim()})

    case Accounts.create_amp_workspace_connection(socket.assigns.account, attrs) do
      {:ok, _connection} -> {:noreply, socket |> load() |> close_modal()}
      {:error, changeset} -> {:noreply, assign(socket, error: connect_error(changeset))}
    end
  end

  def handle_event("disconnect", %{"id" => id}, socket) do
    socket = load(socket)
    _ = Accounts.delete_amp_workspace_connection(socket.assigns.account, id)
    {:noreply, load(socket)}
  end

  defp connect_error(%Ecto.Changeset{errors: errors}) do
    case errors do
      [workspace_id: {_, [constraint: :unique] ++ _}] ->
        dgettext("dashboard_integrations", "This Amp workspace is already connected.")

      [workspace_id: _] ->
        dgettext("dashboard_integrations", "Enter the workspace ID, a UUID such as 8e5f0d8f-a1a5-429d-843d-6096a60fa0a1.")

      _ ->
        dgettext("dashboard_integrations", "Enter the project ID as a UUID, or leave it empty for the whole workspace.")
    end
  end

  defp close_modal(socket) do
    socket
    |> push_event("close-modal", %{id: "connect-amp-workspace-modal"})
    |> assign(error: nil, form_version: socket.assigns.form_version + 1)
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
    <div id={@id} data-part="amp-part">
      <div data-part="header-row">
        <div data-part="header">
          <span data-part="title">{dgettext("dashboard_integrations", "Workspace sign-in")}</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_integrations",
              "Let Orbs in your Amp workspaces sign in to Tuist without a stored token. They get CI access, including cache uploads, to every project in this account."
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
            <%= if connection.project_id do %>
              {dgettext("dashboard_integrations", "Project %{id}", id: connection.project_id)}
            <% else %>
              {dgettext("dashboard_integrations", "All projects")}
            <% end %>
            · {dgettext("dashboard_integrations", "Connected %{time}",
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
                "In a thread of the workspace that runs in an Orb, print its workspace and project IDs:"
              )}
              <div data-part="command">
                <code id="amp-workspace-command">echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID</code>
                <.button
                  id="copy-amp-workspace-command"
                  variant="secondary"
                  size="small"
                  icon_only
                  type="button"
                  phx-hook="Clipboard"
                  data-clipboard-value="echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID"
                  aria-label={dgettext("dashboard_integrations", "Copy command")}
                >
                  <.copy />
                </.button>
              </div>
            </li>
            <li>
              {dgettext(
                "dashboard_integrations",
                "Paste the workspace ID below. Add the project ID to limit access to that Amp project's Orbs. Those Orbs get CI access, including cache uploads, to every project in this account."
              )}
            </li>
          </ol>
          <.text_input
            id={"amp-workspace-id-#{@form_version}"}
            name="workspace_id"
            type="basic"
            label={dgettext("dashboard_integrations", "Workspace ID")}
            placeholder="8e5f0d8f-a1a5-429d-843d-6096a60fa0a1"
            value=""
            required
            show_required
          />
          <.text_input
            id={"amp-project-id-#{@form_version}"}
            name="project_id"
            type="basic"
            label={dgettext("dashboard_integrations", "Project ID")}
            hint={
              dgettext(
                "dashboard_integrations",
                "Optional. Leave empty for every project in the workspace."
              )
            }
            placeholder="1e345004-78e8-4e1d-bb72-27bb1a22d450"
            value=""
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
    </div>
    """
  end
end
