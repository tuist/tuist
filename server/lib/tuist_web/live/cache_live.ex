defmodule TuistWeb.CacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Phoenix.HTML.Form
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Billing.Entitlements
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Registrations
  alias Tuist.Kura.SelfHostedClients

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    cache_enabled = cache_enabled?(selected_account)
    # Self-hosting cache nodes is an Enterprise-only capability, gated by the
    # plan entitlement rather than the (transient) :kura rollout flag.
    self_hosted_enabled = cache_enabled and Entitlements.allows?(selected_account, :self_hosted_cache)
    if connected?(socket) and cache_enabled, do: Kura.subscribe_to_account(selected_account.id)

    socket =
      socket
      |> assign(:cache_enabled, cache_enabled)
      |> assign(:self_hosted_enabled, self_hosted_enabled)
      |> assign(:head_title, "#{dgettext("dashboard_account", "Cache")} · #{selected_account.name} · Tuist")
      |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))
      |> assign(:new_self_hosted_client_secret, nil)
      |> load_servers_state()
      |> load_self_hosted_state()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "select_cache_upload_policy",
        %{"policy" => policy},
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    policy =
      case policy do
        "members_and_tokens" -> :members_and_tokens
        "tokens_only" -> :tokens_only
        _ -> selected_account.cache_write_policy
      end

    {:ok, updated_account} = Accounts.update_account(selected_account, %{cache_write_policy: policy})

    {:noreply, assign(socket, :selected_account, updated_account)}
  end

  def handle_event(
        "create_self_hosted_client",
        params,
        %{assigns: %{self_hosted_enabled: true, selected_account: account}} = socket
      ) do
    name = params |> get_in(["self_hosted_client", "name"]) |> to_string() |> String.trim()

    if name == "" do
      form =
        to_form(%{"name" => ""},
          as: :self_hosted_client,
          errors: [
            name: {dgettext("dashboard_account", "Enter a name to identify this credential."), []}
          ]
        )

      {:noreply, assign(socket, :new_self_hosted_client_form, form)}
    else
      case SelfHostedClients.create_self_hosted_client(account, %{name: name}) do
        {:ok, {client, secret}} ->
          # Keep the modal open and swap its body to the one-time secret
          # disclosure (mirrors the webhook signing-secret flow).
          {:noreply,
           socket
           |> assign(:new_self_hosted_client_secret, %{
             client_id: client.client_id,
             secret: secret,
             name: client.name
           })
           |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))
           |> load_self_hosted_state()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :new_self_hosted_client_form, to_form(changeset))}
      end
    end
  end

  def handle_event("create_self_hosted_client", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss_self_hosted_client_secret", _params, socket) do
    {:noreply,
     socket
     |> reset_self_hosted_client_modal()
     |> push_event("close-modal", %{id: "add-self-hosted-client-modal"})}
  end

  def handle_event("self_hosted_client_modal_open_change", %{"open" => false}, socket) do
    {:noreply, reset_self_hosted_client_modal(socket)}
  end

  def handle_event("self_hosted_client_modal_open_change", _params, socket), do: {:noreply, socket}

  def handle_event("revoke_self_hosted_client", %{"id" => id}, socket) do
    socket = push_event(socket, "close-modal", %{id: "revoke-credential-modal-#{id}"})

    case Enum.find(socket.assigns.self_hosted_clients, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      client ->
        {:ok, _} = SelfHostedClients.revoke_self_hosted_client(client)
        {:noreply, load_self_hosted_state(socket)}
    end
  end

  def handle_event("close-revoke-credential-modal-" <> id, _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "revoke-credential-modal-#{id}"})}
  end

  def handle_event("close-add-self-hosted-client-modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-modal", %{id: "add-self-hosted-client-modal"})
     |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))}
  end

  @impl true
  def handle_info({:kura_server, _event, _server}, %{assigns: %{cache_enabled: true}} = socket) do
    {:noreply, load_servers_state(socket)}
  end

  def handle_info({:kura_server, _event, _server}, socket), do: {:noreply, socket}

  defp load_servers_state(%{assigns: %{cache_enabled: false}} = socket) do
    socket
    |> assign(:servers, [])
    |> assign(:managed_cache_visible?, false)
    |> assign(:serving_state, :absent)
  end

  defp load_servers_state(socket, _opts \\ []) do
    account = socket.assigns.selected_account

    # Customer-facing list only. Private runner-cache nodes are
    # control-plane-managed (provisioned/torn down by the identity rule), so
    # surfacing them here would report a cache the account cannot use.
    servers =
      account.id
      |> Kura.list_servers_for_account()
      |> Enum.reject(&Regions.private?(Regions.get(&1.region)))

    socket
    |> assign(:servers, servers)
    # A deployment serving no public region runs nobody's cache, so there is
    # no managed cache to report the state of.
    |> assign(:managed_cache_visible?, servers != [] or Enum.any?(Regions.available(), &(not Regions.private?(&1))))
    |> assign(:serving_state, serving_state(servers))
  end

  # What the account is told, which is whether its cache is working — not where
  # it runs or how many there are. Naming a region here would invite a request
  # to change it, and placement is not a request the account can make.
  defp serving_state(servers) do
    cond do
      Enum.any?(servers, &(&1.status == :active)) -> :active
      Enum.any?(servers, &(&1.status in [:provisioning, :replicating, :failed])) -> :preparing
      true -> :absent
    end
  end

  defp reset_self_hosted_client_modal(socket) do
    socket
    |> assign(:new_self_hosted_client_secret, nil)
    |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))
  end

  defp load_self_hosted_state(%{assigns: %{cache_enabled: false}} = socket) do
    socket
    |> assign(:self_hosted_clients, [])
    |> assign(:registered_endpoints, [])
  end

  defp load_self_hosted_state(%{assigns: %{selected_account: account}} = socket) do
    socket
    |> assign(:self_hosted_clients, SelfHostedClients.list_self_hosted_clients(account))
    |> assign(:registered_endpoints, Registrations.list_endpoints(account))
  end

  defp cache_enabled?(account) do
    FeatureFlags.kura_enabled?(account)
  end

  attr(:cache_write_policy, :atom, required: true)

  def cache_write_policy_section(assigns) do
    ~H"""
    <div class="cache-section" data-part="cache-write-policy-card">
      <div data-part="header">
        <div data-part="title-group">
          <span data-part="title">{dgettext("dashboard_account", "Upload access")}</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_account",
              "Choose whether members can upload or CI is the trusted cache writer."
            )}
          </span>
          <.link_button
            href="/en/docs/guides/server/authentication#continuous-integration"
            target="_blank"
            label={dgettext("dashboard_account", "Learn how to authenticate CI")}
            variant="primary"
            size="medium"
            data-part="docs-link"
          >
            <:icon_right><.external_link /></:icon_right>
          </.link_button>
        </div>
      </div>
      <div
        data-part="policy-options"
        role="radiogroup"
        aria-label={dgettext("dashboard_account", "Upload access")}
      >
        <button
          id="cache-upload-policy-members-and-tokens"
          type="button"
          data-part="policy-option"
          data-selected={if @cache_write_policy == :members_and_tokens, do: "true", else: "false"}
          role="radio"
          aria-checked={if @cache_write_policy == :members_and_tokens, do: "true", else: "false"}
          phx-click="select_cache_upload_policy"
          phx-value-policy="members_and_tokens"
        >
          <span data-part="option-header">
            <span data-part="control" aria-hidden="true"></span>
            <span data-part="body">
              <span data-part="label">
                {dgettext("dashboard_account", "Members, CI and account tokens")}
              </span>
              <span data-part="description">
                {dgettext(
                  "dashboard_account",
                  "Members using login sessions, CI OIDC tokens, and account tokens with cache write scopes can upload."
                )}
              </span>
            </span>
          </span>
        </button>
        <button
          id="cache-upload-policy-tokens-only"
          type="button"
          data-part="policy-option"
          data-selected={if @cache_write_policy == :tokens_only, do: "true", else: "false"}
          role="radio"
          aria-checked={if @cache_write_policy == :tokens_only, do: "true", else: "false"}
          phx-click="select_cache_upload_policy"
          phx-value-policy="tokens_only"
        >
          <span data-part="option-header">
            <span data-part="control" aria-hidden="true"></span>
            <span data-part="body">
              <span data-part="label">
                {dgettext("dashboard_account", "CI and account tokens only")}
              </span>
              <span data-part="description">
                {dgettext(
                  "dashboard_account",
                  "Members can download, but uploads require CI OIDC tokens or account tokens with cache write scopes."
                )}
              </span>
            </span>
          </span>
        </button>
      </div>
    </div>
    """
  end

  attr(:serving_state, :atom, required: true)

  def cache_servers_section(assigns) do
    ~H"""
    <div class="cache-section" data-part="servers-card">
      <div data-part="header">
        <div data-part="title-group">
          <span data-part="title">{dgettext("dashboard_account", "Managed cache")}</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_account",
              "Tuist runs your cache for you and keeps it close to where your builds run, following them if they move."
            )}
          </span>
        </div>
      </div>
      <div data-part="serving-status">
        <%= case @serving_state do %>
          <% :active -> %>
            <.badge
              label={dgettext("dashboard_account", "Active")}
              color="success"
              style="light-fill"
            />
            <span data-part="serving-description">
              {dgettext(
                "dashboard_account",
                "Your cache is serving builds. Nothing to configure."
              )}
            </span>
          <% :preparing -> %>
            <.badge
              label={dgettext("dashboard_account", "Setting up")}
              color="attention"
              style="light-fill"
            />
            <span data-part="serving-description">
              {dgettext(
                "dashboard_account",
                "Your cache is being set up. Builds keep working while it warms up."
              )}
            </span>
          <% :absent -> %>
            <.badge
              label={dgettext("dashboard_account", "Not running yet")}
              color="neutral"
              style="light-fill"
            />
            <span data-part="serving-description">
              {dgettext(
                "dashboard_account",
                "Your cache starts the first time a build uses it."
              )}
            </span>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:self_hosted_clients, :list, required: true)
  attr(:new_self_hosted_client_form, Form, required: true)
  attr(:new_self_hosted_client_secret, :map, default: nil)
  attr(:registered_endpoints, :list, required: true)

  def self_hosted_section(assigns) do
    ~H"""
    <div data-part="self-hosted-header">
      <div data-part="title-group">
        <span data-part="title">
          {dgettext("dashboard_account", "Self-hosted servers")}
        </span>
        <span data-part="subtitle">
          {dgettext(
            "dashboard_account",
            "Run your own cache nodes. Generate a credential they authenticate with, and they register themselves so the CLI can reach them directly."
          )}
        </span>
      </div>
    </div>
    <div class="cache-section" data-part="credentials-section">
      <div data-part="subsection-header">
        <div data-part="title-group">
          <span data-part="title">{dgettext("dashboard_account", "Credentials")}</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_account",
              "Tenant-scoped credentials your nodes present to Tuist. A credential only authorizes this account's traffic."
            )}
          </span>
        </div>
        <div data-part="actions">
          <.form
            for={@new_self_hosted_client_form}
            id="add-self-hosted-client-form"
            phx-submit="create_self_hosted_client"
          >
            <%!-- Noora's modal shell is `phx-update="ignore"`, so we keep the --%>
            <%!-- title neutral and swap the body between the form and the --%>
            <%!-- one-time secret disclosure (mirrors the webhook flow). --%>
            <.modal
              id="add-self-hosted-client-modal"
              title={dgettext("dashboard_account", "Node credential")}
              on_dismiss="dismiss_self_hosted_client_secret"
              on_open_change="self_hosted_client_modal_open_change"
            >
              <:trigger :let={attrs}>
                <.button
                  id="add-self-hosted-client-button"
                  label={dgettext("dashboard_account", "Generate credential")}
                  variant="secondary"
                  size="medium"
                  type="button"
                  {attrs}
                />
              </:trigger>

              <div data-part="modal-content-wrapper">
                <.line_divider />

                <%= if @new_self_hosted_client_secret do %>
                  <div data-part="modal-body">
                    <div data-part="modal-message">
                      <span data-part="title">
                        {dgettext("dashboard_account", "Client credentials")}
                      </span>
                      <span data-part="subtitle">
                        {dgettext(
                          "dashboard_account",
                          "Copy the secret now. It will not be shown again after you close this dialog."
                        )}
                      </span>
                    </div>
                    <div data-part="credential-field">
                      <span data-part="label">
                        {dgettext("dashboard_account", "Client ID")}
                      </span>
                      <div data-part="read-only-value">
                        <code>{@new_self_hosted_client_secret.client_id}</code>
                        <.button
                          id="copy-self-hosted-client-id-button"
                          variant="secondary"
                          size="small"
                          icon_only
                          type="button"
                          phx-hook="Clipboard"
                          data-clipboard-value={@new_self_hosted_client_secret.client_id}
                          aria-label={dgettext("dashboard_account", "Copy client ID")}
                        >
                          <.copy />
                        </.button>
                      </div>
                    </div>
                    <div data-part="credential-field">
                      <span data-part="label">
                        {dgettext("dashboard_account", "Client secret")}
                      </span>
                      <div data-part="read-only-value">
                        <code id="new-self-hosted-client-secret">
                          {@new_self_hosted_client_secret.secret}
                        </code>
                        <.button
                          id="copy-self-hosted-client-secret-button"
                          variant="secondary"
                          size="small"
                          icon_only
                          type="button"
                          phx-hook="Clipboard"
                          data-clipboard-value={@new_self_hosted_client_secret.secret}
                          aria-label={dgettext("dashboard_account", "Copy client secret")}
                        >
                          <.copy />
                        </.button>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <div data-part="modal-body">
                    <.text_input
                      field={@new_self_hosted_client_form[:name]}
                      type="basic"
                      label={dgettext("dashboard_account", "Name")}
                      placeholder={dgettext("dashboard_account", "Production mesh")}
                    />
                  </div>
                <% end %>

                <.line_divider />
              </div>

              <:footer>
                <.modal_footer>
                  <:action :if={@new_self_hosted_client_secret}>
                    <.button
                      type="button"
                      label={dgettext("dashboard_account", "Done")}
                      variant="primary"
                      phx-click="dismiss_self_hosted_client_secret"
                    />
                  </:action>
                  <:action :if={is_nil(@new_self_hosted_client_secret)}>
                    <.button
                      type="button"
                      label={dgettext("dashboard_account", "Cancel")}
                      variant="secondary"
                      phx-click="dismiss_self_hosted_client_secret"
                    />
                  </:action>
                  <:action :if={is_nil(@new_self_hosted_client_secret)}>
                    <.button
                      type="submit"
                      label={dgettext("dashboard_account", "Generate")}
                      variant="primary"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </.form>
        </div>
      </div>
      <.table id="self-hosted-clients-table" rows={@self_hosted_clients}>
        <:col :let={client} label={dgettext("dashboard_account", "Name")}>
          <.text_cell label={client.name} />
        </:col>
        <:col :let={client} label={dgettext("dashboard_account", "Client ID")}>
          <.text_cell label={client.client_id} />
        </:col>
        <:col :let={client} label={dgettext("dashboard_account", "Secret")}>
          <.text_cell label={masked_secret(client.secret_last_four)} />
        </:col>
        <:col :let={client} label="">
          <.button_cell>
            <:button>
              <.modal
                id={"revoke-credential-modal-#{client.id}"}
                title={dgettext("dashboard_account", "Revoke credential")}
                header_type="icon"
                header_size="small"
                on_dismiss={"close-revoke-credential-modal-#{client.id}"}
              >
                <:trigger :let={attrs}>
                  <.button
                    type="button"
                    variant="secondary"
                    size="small"
                    icon_only
                    aria-label={dgettext("dashboard_account", "Revoke credential")}
                    {attrs}
                  >
                    <.trash />
                  </.button>
                </:trigger>
                <:header_icon>
                  <.trash />
                </:header_icon>
                <.line_divider />
                <p data-part="revoke-credential-message">
                  {dgettext(
                    "dashboard_account",
                    "Revoke %{name}? Self-hosted nodes using it will stop authenticating.",
                    name: client.name
                  )}
                </p>
                <:footer>
                  <.modal_footer>
                    <:action>
                      <.button
                        label={dgettext("dashboard_account", "Cancel")}
                        variant="secondary"
                        type="button"
                        phx-click={"close-revoke-credential-modal-#{client.id}"}
                      />
                    </:action>
                    <:action>
                      <.button
                        label={dgettext("dashboard_account", "Revoke")}
                        variant="destructive"
                        type="button"
                        phx-click="revoke_self_hosted_client"
                        phx-value-id={client.id}
                      />
                    </:action>
                  </.modal_footer>
                </:footer>
              </.modal>
            </:button>
          </.button_cell>
        </:col>
        <:empty_state>
          <.table_empty_state
            title={dgettext("dashboard_account", "No credentials yet")}
            subtitle={
              dgettext("dashboard_account", "Generate one to authorize your self-hosted nodes.")
            }
          />
        </:empty_state>
      </.table>
    </div>

    <div class="cache-section" data-part="registered-nodes-section">
      <div data-part="subsection-header">
        <div data-part="title-group">
          <span data-part="title">{dgettext("dashboard_account", "Registered nodes")}</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_account",
              "Self-hosted nodes reporting in via registration heartbeats. The CLI routes cache traffic to each node's endpoint, and a node drops off this list when it stops heartbeating."
            )}
          </span>
        </div>
      </div>
      <.table id="registered-nodes-table" rows={@registered_endpoints}>
        <:col :let={node} label={dgettext("dashboard_account", "Node")}>
          <.text_cell label={node.node_id} />
        </:col>
        <:col :let={node} label={dgettext("dashboard_account", "Endpoint")}>
          <.text_cell label={node.advertised_http_url} />
        </:col>
        <:col :let={node} label={dgettext("dashboard_account", "Region")}>
          <.text_cell label={node.region || "—"} />
        </:col>
        <:col :let={node} label={dgettext("dashboard_account", "Status")}>
          <.badge_cell
            label={registered_status_label(node)}
            color={registered_status_color(node)}
            style="light-fill"
          />
        </:col>
        <:col :let={node} label={dgettext("dashboard_account", "Last heartbeat")}>
          <.text_cell label={Tuist.Utilities.DateFormatter.from_now(node.last_heartbeat_at)} />
        </:col>
        <:empty_state>
          <.table_empty_state
            title={dgettext("dashboard_account", "No registered nodes")}
            subtitle={
              dgettext(
                "dashboard_account",
                "Self-hosted nodes appear here once they start sending registration heartbeats."
              )
            }
          />
        </:empty_state>
      </.table>
    </div>
    """
  end

  defp registered_status_label(%{ready: true}), do: dgettext("dashboard_account", "Ready")
  defp registered_status_label(_), do: dgettext("dashboard_account", "Not ready")

  defp registered_status_color(%{ready: true}), do: "success"
  defp registered_status_color(_), do: "warning"

  # Suffix-only preview so a customer can match a credential against a secret
  # stored elsewhere; credentials issued before the hint existed show fully masked.
  defp masked_secret(tail) when is_binary(tail) and tail != "", do: String.duplicate("•", 12) <> tail
  defp masked_secret(_), do: String.duplicate("•", 16)
end
