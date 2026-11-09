defmodule TuistWeb.Components.ClaudeIntegration do
  @moduledoc """
  Connects Claude Managed Agents environments from Settings → Integrations
  in one form. The customer creates a self-hosted environment and its key
  in the Claude Console (only the Console generates environment keys) and
  pastes both with the credential Tuist starts sessions with, picked by the
  selector at the top:

  - An Anthropic API key, the default because it is the quickest to try,
    stored as the row's `anthropic_api_key`.
  - A federated identity (`Tuist.Sandboxes.Anthropic.Federation`): the form
    shows the account's issuer and subject to trust in the Console and takes
    the four federation ids, so Tuist stores no API key.

  Tuist fetches the environment with the credential before writing the row,
  so a wrong credential, environment id or workspace fails in the form. The
  secrets go from the submitted form straight into the row and are never
  assigned to the socket.
  """
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Accounts.Account
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Federation
  alias Tuist.Sandboxes.Sandbox
  alias TuistWeb.Errors.UnauthorizedError

  @console_wif_url "https://platform.claude.com/settings/workload-identity-federation"
  @console_environments_url "https://platform.claude.com/environments"
  @id_fields ~w(anthropic_organization_id anthropic_workspace_id anthropic_service_account_id anthropic_federation_rule_id)

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> reset() |> load()}
  end

  @impl true
  def handle_event("open", _params, socket) do
    {:noreply, socket |> load() |> reset() |> push_event("open-modal", %{id: "connect-claude-modal"})}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> reset() |> push_event("close-modal", %{id: "connect-claude-modal"})}
  end

  def handle_event("auth", %{"mode" => mode}, socket) do
    auth = if mode == "federation", do: :federation, else: :api_key
    {:noreply, assign(socket, auth: auth, error: nil, rejected: false, field_errors: %{})}
  end

  # Keeps the federation ids across switches of the selector. The secrets
  # in `params` are dropped.
  def handle_event("change", params, socket) do
    {:noreply, assign(socket, ids: Map.merge(socket.assigns.ids, Map.take(params, @id_fields)))}
  end

  def handle_event("connect", params, socket) do
    account = authorized_account!(socket)
    auth = socket.assigns.auth
    environment_id = trimmed(params, "environment_id")
    {platform, vcpus, memory_mb} = parse_shape(Map.get(params, "shape", ""))
    socket = if auth == :federation, do: assign(socket, ids: Map.take(params, @id_fields)), else: socket

    with {:ok, credential, credential_attrs} <- credential(auth, params),
         {:ok, environment} <- Sandboxes.fetch_anthropic_environment(account, credential, environment_id),
         attrs =
           Map.merge(credential_attrs, %{
             kind: :managed_agents,
             anthropic_environment_id: environment_id,
             environment_key: trimmed(params, "environment_key"),
             name: String.slice(environment["name"] || environment_id, 0, 100),
             platform: platform,
             vcpus: vcpus,
             memory_mb: memory_mb
           }),
         {:ok, _agent_environment} <- Sandboxes.create_agent_environment(account, attrs) do
      {:noreply, socket |> reset() |> load() |> push_event("close-modal", %{id: "connect-claude-modal"})}
    else
      {:field_errors, errors} ->
        {:noreply, assign(socket, field_errors: errors, error: nil, rejected: false)}

      # Never assign the submitted secrets or their changeset to the LiveView.
      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          if changeset.errors[:anthropic_environment_id],
            do: dgettext("dashboard_integrations", "Could not connect the environment. It may already be connected."),
            else: dgettext("dashboard_integrations", "Could not connect the environment.")

        {:noreply, assign(socket, field_errors: %{}, error: message, rejected: false)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           field_errors: %{},
           error: connect_error(auth, reason),
           rejected: match?({:federation_rejected, _}, reason)
         )}
    end
  end

  # Checks every field Tuist needs before calling Anthropic and returns the
  # credential to fetch the environment with and the row's credential
  # attributes.
  defp credential(auth, params) do
    missing =
      for field <- ["environment_id", "environment_key"], trimmed(params, field) == "", into: %{} do
        {field, dgettext("dashboard_integrations", "can't be blank")}
      end

    case {credential_fields(auth, params), missing} do
      {{:ok, credential, attrs}, missing} when missing == %{} -> {:ok, credential, attrs}
      {{:ok, _credential, _attrs}, missing} -> {:field_errors, missing}
      {{:field_errors, errors}, missing} -> {:field_errors, Map.merge(errors, missing)}
    end
  end

  defp credential_fields(:api_key, params) do
    case trimmed(params, "api_key") do
      "" -> {:field_errors, %{"api_key" => dgettext("dashboard_integrations", "can't be blank")}}
      api_key -> {:ok, {:api_key, api_key}, %{anthropic_api_key: api_key}}
    end
  end

  defp credential_fields(:federation, params) do
    ids = Map.new(@id_fields, &{&1, trimmed(params, &1)})

    case ids |> AgentEnvironment.federation_changeset() |> Ecto.Changeset.apply_action(:validate) do
      {:ok, struct} ->
        {:ok, Federation.ids(struct), Map.new(ids, fn {key, value} -> {String.to_existing_atom(key), value} end)}

      {:error, changeset} ->
        {:field_errors, Map.new(changeset.errors, fn {field, {message, _opts}} -> {to_string(field), message} end)}
    end
  end

  defp trimmed(params, key), do: params |> Map.get(key, "") |> to_string() |> String.trim()

  defp reset(socket) do
    assign(socket,
      auth: :api_key,
      ids: Map.new(@id_fields, &{&1, ""}),
      field_errors: %{},
      error: nil,
      rejected: false,
      form_version: Map.get(socket.assigns, :form_version, 0) + 1
    )
  end

  defp load(socket) do
    account = authorized_account!(socket)

    environments =
      account
      |> Sandboxes.list_agent_environments()
      |> Enum.filter(&(&1.kind == :managed_agents))

    assign(socket,
      account: account,
      environments: environments,
      available: FeatureFlags.sandboxes_enabled?(account),
      issuer: Federation.issuer(account.id),
      subject_prefix: "account:#{account.id}:*"
    )
  end

  defp authorized_account!(socket) do
    account = Repo.get!(Account, socket.assigns.account.id)

    if Authorization.authorize(:account_update, socket.assigns.current_user, account) != :ok do
      raise UnauthorizedError
    end

    account
  end

  defp connect_error(_auth, {:federation_rejected, %{status: 401}}) do
    dgettext(
      "dashboard_integrations",
      "Anthropic rejected the token. Check that the rule uses the issuer URL and subject prefix above and names this service account. The authentication history in the Claude Console shows the reason."
    )
  end

  defp connect_error(_auth, {:federation_rejected, %{message: message}}) do
    dgettext("dashboard_integrations", "Anthropic rejected the request: %{message}", message: message)
  end

  defp connect_error(_auth, :not_self_hosted) do
    dgettext(
      "dashboard_integrations",
      "This environment is not self-hosted. Create a self-hosted environment in the Claude Console."
    )
  end

  defp connect_error(:api_key, %{status: 401}) do
    dgettext("dashboard_integrations", "Anthropic rejected the API key. Check that you copied all of it.")
  end

  defp connect_error(:api_key, %{status: 403}) do
    dgettext(
      "dashboard_integrations",
      "This API key cannot read the environment. Use a key with the developer role in the environment's workspace."
    )
  end

  defp connect_error(:federation, %{status: 403}) do
    dgettext(
      "dashboard_integrations",
      "Anthropic refused the federated token. Set the federation rule's scope to workspace:developer."
    )
  end

  defp connect_error(_auth, %{status: 404}) do
    dgettext(
      "dashboard_integrations",
      "Anthropic has no environment with this ID in the credential's workspace. Check the ID, and that the credential belongs to the environment's workspace."
    )
  end

  defp connect_error(_auth, %{status: status, message: message}) do
    dgettext("dashboard_integrations", "Anthropic answered %{status}: %{message}", status: status, message: message)
  end

  defp connect_error(_auth, _reason) do
    dgettext("dashboard_integrations", "Could not reach Anthropic. Try again.")
  end

  defp shape_options do
    for platform <- [:linux, :darwin], {vcpus, memory_mb} <- Sandbox.shapes(platform) do
      os = if platform == :darwin, do: "macOS", else: "Linux"
      {"#{platform}-#{vcpus}-#{memory_mb}", "#{os} · #{vcpus} vCPU · #{div(memory_mb, 1024)} GB"}
    end
  end

  defp parse_shape(shape) do
    with [platform, vcpus, memory_mb] when platform in ["linux", "darwin"] <- String.split(shape, "-"),
         {vcpus, ""} <- Integer.parse(vcpus),
         {memory_mb, ""} <- Integer.parse(memory_mb) do
      {String.to_existing_atom(platform), vcpus, memory_mb}
    else
      _ -> {:linux, 2, 4096}
    end
  end

  # Federated environments need no badge; the others are flagged so admins
  # move them to federation.
  defp authentication_badge(%AgentEnvironment{} = agent_environment) do
    cond do
      Federation.federated?(agent_environment) -> nil
      is_binary(agent_environment.anthropic_api_key) -> {dgettext("dashboard_integrations", "API key"), "warning"}
      true -> {dgettext("dashboard_integrations", "No credentials"), "destructive"}
    end
  end

  attr :text, :string, required: true, doc: "A translated sentence with a `%{link}` placeholder"
  attr :href, :string, required: true
  attr :label, :string, required: true

  # Renders a sentence with a Claude Console link in place of `%{link}`,
  # keeping the sentence one translatable string.
  defp linked_sentence(assigns) do
    assigns = assign(assigns, :parts, String.split(assigns.text, "%{link}", parts: 2))

    ~H"""
    <p>
      <%= case @parts do %>
        <% [before, rest] -> %>
          {before}<.link_button
            href={@href}
            target="_blank"
            rel="noopener noreferrer"
            label={@label}
            variant="primary"
            underline
          />{rest}
        <% [text] -> %>
          {text}
      <% end %>
    </p>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp copy_row(assigns) do
    ~H"""
    <div data-part="copy-row">
      <span data-part="copy-label">{@label}</span>
      <div data-part="read-only-value">
        <code id={"#{@id}-value"}>{@value}</code>
        <.button
          id={"#{@id}-copy"}
          variant="secondary"
          size="small"
          icon_only
          type="button"
          phx-hook="Clipboard"
          data-clipboard-value={@value}
          aria-label={dgettext("dashboard_integrations", "Copy %{label}", label: @label)}
        >
          <.copy />
        </.button>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        console_wif_url: @console_wif_url,
        console_environments_url: @console_environments_url,
        history_url: Federation.authentication_history_url()
      )

    ~H"""
    <section
      hidden={not @available}
      id={@id}
      data-part="claude-card-section"
      class="noora-card__section"
    >
      <div data-part="header-row">
        <div data-part="header">
          <span data-part="title">Claude</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_integrations",
              "Run Claude Managed Agents sessions on Tuist sandboxes."
            )}
          </span>
        </div>
        <div data-part="actions">
          <.button
            :if={@available}
            id="connect-claude-button"
            type="button"
            label={
              if @environments == [],
                do: dgettext("dashboard_integrations", "Connect"),
                else: dgettext("dashboard_integrations", "Connect environment")
            }
            variant="primary"
            phx-click="open"
            phx-target={@myself}
          />
        </div>
      </div>
      <ul :if={@environments != []} data-part="claude-environments">
        <li :for={environment <- @environments} data-part="claude-environment">
          <span data-part="name">{environment.name || environment.anthropic_environment_id}</span>
          <code>{environment.anthropic_environment_id}</code>
          <span data-part="meta">
            {if environment.platform == :darwin, do: "macOS", else: "Linux"} · {environment.vcpus} vCPU · {div(
              environment.memory_mb,
              1024
            )} GB
          </span>
          <.badge
            :for={{label, color} <- List.wrap(authentication_badge(environment))}
            label={label}
            color={color}
            style="light-fill"
          />
        </li>
      </ul>
      <.modal
        :if={@available}
        id="connect-claude-modal"
        title={dgettext("dashboard_integrations", "Connect Claude Managed Agents")}
        header_size="large"
      >
        <:trigger :let={attrs}>
          <button type="button" hidden aria-hidden="true" tabindex="-1" {attrs} />
        </:trigger>
        <.line_divider />
        <div data-part="claude-connect">
          <.button_group id="claude-auth-selector" size="medium">
            <.button_group_item
              label={dgettext("dashboard_integrations", "API key")}
              phx-click="auth"
              phx-value-mode="api_key"
              phx-target={@myself}
              data-selected={@auth == :api_key}
            />
            <.button_group_item
              label={dgettext("dashboard_integrations", "Federated identity")}
              phx-click="auth"
              phx-value-mode="federation"
              phx-target={@myself}
              data-selected={@auth == :federation}
            />
          </.button_group>

          <form
            id={"claude-connect-form-#{@form_version}"}
            phx-change="change"
            phx-submit="connect"
            phx-target={@myself}
            autocomplete="off"
          >
            <.alert
              :if={@error}
              id="claude-connect-error"
              status="error"
              type="secondary"
              size="small"
              title={@error}
            />
            <.link_button
              :if={@error && @rejected}
              href={@history_url}
              target="_blank"
              rel="noopener noreferrer"
              label={dgettext("dashboard_integrations", "Open the authentication history")}
              variant="primary"
              underline
            />

            <div :if={@auth == :api_key} data-part="group">
              <.text_input
                id={"claude-api-key-#{@form_version}"}
                name="api_key"
                type="password"
                input_type="password"
                label={dgettext("dashboard_integrations", "Anthropic API key")}
                placeholder="sk-ant-api03-…"
                value=""
                show_required
                error={@field_errors["api_key"]}
                label_tooltip={
                  dgettext(
                    "dashboard_integrations",
                    "Needs the developer role in the environment's workspace. Stored encrypted. Use a federated identity for environments you rely on."
                  )
                }
              />
            </div>

            <div :if={@auth == :federation} data-part="group">
              <.linked_sentence
                text={
                  dgettext(
                    "dashboard_integrations",
                    "In %{link}, connect a Custom OIDC workload with these values and add its service account to the environment's workspace.",
                    link: "%{link}"
                  )
                }
                href={@console_wif_url}
                label={dgettext("dashboard_integrations", "Workload identity")}
              />
              <div data-part="grid">
                <.copy_row
                  id="claude-issuer"
                  label={dgettext("dashboard_integrations", "Issuer URL")}
                  value={@issuer}
                />
                <.copy_row
                  id="claude-subject"
                  label={dgettext("dashboard_integrations", "Subject prefix")}
                  value={@subject_prefix}
                />
                <.copy_row
                  id="claude-audience"
                  label={dgettext("dashboard_integrations", "Audience")}
                  value={Federation.audience()}
                />
                <.copy_row
                  id="claude-scope"
                  label={dgettext("dashboard_integrations", "Scope")}
                  value="workspace:developer"
                />
              </div>
              <div data-part="grid">
                <.text_input
                  id="claude-organization-id"
                  name="anthropic_organization_id"
                  value={@ids["anthropic_organization_id"]}
                  label={dgettext("dashboard_integrations", "Organization ID")}
                  label_tooltip={
                    dgettext(
                      "dashboard_integrations",
                      "Settings → Organization in the Claude Console."
                    )
                  }
                  placeholder="00000000-0000-…"
                  error={@field_errors["anthropic_organization_id"]}
                />
                <.text_input
                  id="claude-workspace-id"
                  name="anthropic_workspace_id"
                  value={@ids["anthropic_workspace_id"]}
                  label={dgettext("dashboard_integrations", "Workspace ID")}
                  label_tooltip={
                    dgettext(
                      "dashboard_integrations",
                      "Settings → Workspaces in the Claude Console. Use the workspace that runs the environment."
                    )
                  }
                  placeholder="wrkspc_…"
                  error={@field_errors["anthropic_workspace_id"]}
                />
                <.text_input
                  id="claude-service-account-id"
                  name="anthropic_service_account_id"
                  value={@ids["anthropic_service_account_id"]}
                  label={dgettext("dashboard_integrations", "Service account ID")}
                  label_tooltip={
                    dgettext(
                      "dashboard_integrations",
                      "Shown when Connect workload finishes, and on the federation rule's page in Workload identity."
                    )
                  }
                  placeholder="svac_…"
                  error={@field_errors["anthropic_service_account_id"]}
                />
                <.text_input
                  id="claude-federation-rule-id"
                  name="anthropic_federation_rule_id"
                  value={@ids["anthropic_federation_rule_id"]}
                  label={dgettext("dashboard_integrations", "Federation rule ID")}
                  label_tooltip={
                    dgettext(
                      "dashboard_integrations",
                      "Shown when Connect workload finishes, and on the federation rule's page in Workload identity."
                    )
                  }
                  placeholder="fdrl_…"
                  error={@field_errors["anthropic_federation_rule_id"]}
                />
              </div>
            </div>

            <div data-part="group">
              <span data-part="group-title">
                {dgettext("dashboard_integrations", "Self-hosted environment")}
              </span>
              <.linked_sentence
                text={
                  dgettext(
                    "dashboard_integrations",
                    "Create one in the %{link}, open it and click Generate environment key.",
                    link: "%{link}"
                  )
                }
                href={@console_environments_url}
                label={dgettext("dashboard_integrations", "Claude Console")}
              />
              <div data-part="grid">
                <.text_input
                  id={"claude-environment-id-#{@form_version}"}
                  name="environment_id"
                  value=""
                  label={dgettext("dashboard_integrations", "Environment ID")}
                  placeholder="env_…"
                  show_required
                  error={@field_errors["environment_id"]}
                />
                <.text_input
                  id={"claude-environment-key-#{@form_version}"}
                  name="environment_key"
                  type="password"
                  input_type="password"
                  label={dgettext("dashboard_integrations", "Environment key")}
                  value=""
                  show_required
                  error={@field_errors["environment_key"]}
                />
              </div>
              <div data-part="grid">
                <div data-part="field">
                  <.label label={dgettext("dashboard_integrations", "Sandbox shape")} />
                  <.select
                    id="claude-shape"
                    name="shape"
                    value="linux-2-4096"
                    label={dgettext("dashboard_integrations", "Sandbox shape")}
                  >
                    <:item :for={{value, label} <- shape_options()} value={value} label={label} />
                  </.select>
                </div>
              </div>
            </div>

            <div data-part="actions">
              <.button
                type="button"
                variant="secondary"
                label={dgettext("dashboard_integrations", "Cancel")}
                phx-click="cancel"
                phx-target={@myself}
              />
              <.button
                type="submit"
                variant="primary"
                label={dgettext("dashboard_integrations", "Connect")}
                phx-disable-with={dgettext("dashboard_integrations", "Connecting…")}
              />
            </div>
          </form>
        </div>
      </.modal>
    </section>
    """
  end
end
