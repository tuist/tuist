defmodule TuistWeb.Components.ClaudeIntegration do
  @moduledoc """
  Connects Claude Managed Agents environments from Settings → Integrations
  without an Anthropic API key, through Workload Identity Federation
  (`Tuist.Sandboxes.Anthropic.Federation`):

  1. Trust Tuist: the account's issuer and subject to enter in the Claude
     Console's Connect workload wizard.
  2. Paste the federation ids (or the rule's exchange snippet); Tuist runs a
     test exchange.
  3. Tuist creates the self-hosted environment with a federated token.
  4. Paste the environment key, which only the Console can generate, and
     pick the sandbox shape.

  The environment key goes straight from the last form into the agent
  environment row and is never assigned to the socket.
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

  def handle_event("go", %{"step" => step}, socket) do
    {:noreply, assign(socket, step: String.to_integer(step), error: nil, rejected: false)}
  end

  def handle_event("ids-change", params, socket) do
    pasted =
      params
      |> Map.get("snippet", "")
      |> Federation.parse_ids()
      |> Map.new(fn {key, value} -> {"anthropic_#{key}", value} end)

    ids = params |> Map.take(@id_fields) |> Map.merge(pasted)
    {:noreply, assign(socket, ids: ids, id_errors: %{})}
  end

  def handle_event("verify", params, socket) do
    account = authorized_account!(socket)
    ids = Map.take(params, @id_fields)
    changeset = AgentEnvironment.federation_changeset(ids)

    with {:ok, struct} <- Ecto.Changeset.apply_action(changeset, :validate),
         {:ok, _token} <- Federation.verify(account.id, Federation.ids(struct)) do
      {:noreply, assign(socket, ids: ids, id_errors: %{}, error: nil, rejected: false, step: 3)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, ids: ids, id_errors: field_errors(changeset), error: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           ids: ids,
           id_errors: %{},
           error: exchange_error(reason),
           rejected: match?({:federation_rejected, _}, reason)
         )}
    end
  end

  def handle_event("create-environment", %{"name" => name}, socket) do
    account = authorized_account!(socket)
    name = if String.trim(name) == "", do: "tuist", else: String.trim(name)

    case Sandboxes.create_anthropic_environment(account, federation_ids(socket), name) do
      {:ok, environment_id} ->
        {:noreply, assign(socket, anthropic_environment_id: environment_id, environment_name: name, error: nil, step: 4)}

      {:error, reason} ->
        {:noreply, assign(socket, environment_name: name, error: exchange_error(reason))}
    end
  end

  def handle_event("connect", %{"environment_key" => key, "shape" => shape}, socket) do
    account = authorized_account!(socket)
    {platform, vcpus, memory_mb} = parse_shape(shape)

    attrs =
      Map.merge(
        %{
          kind: :managed_agents,
          anthropic_environment_id: socket.assigns.anthropic_environment_id,
          environment_key: String.trim(key),
          name: socket.assigns.environment_name,
          platform: platform,
          vcpus: vcpus,
          memory_mb: memory_mb
        },
        Map.new(socket.assigns.ids, fn {key, value} -> {String.to_existing_atom(key), value} end)
      )

    case Sandboxes.create_agent_environment(account, attrs) do
      {:ok, _agent_environment} ->
        {:noreply, socket |> reset() |> load() |> push_event("close-modal", %{id: "connect-claude-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Never assign the submitted key or its changeset to the LiveView.
        message =
          if changeset.errors[:environment_key],
            do: dgettext("dashboard_integrations", "Paste the environment key you generated in the Claude Console."),
            else: dgettext("dashboard_integrations", "Could not connect the environment. It may already be connected.")

        {:noreply, assign(socket, error: message)}
    end
  end

  defp reset(socket) do
    assign(socket,
      step: 1,
      ids: Map.new(@id_fields, &{&1, ""}),
      id_errors: %{},
      error: nil,
      rejected: false,
      anthropic_environment_id: nil,
      environment_name: "tuist",
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

  defp federation_ids(socket) do
    ids = socket.assigns.ids

    %{
      organization_id: ids["anthropic_organization_id"],
      workspace_id: ids["anthropic_workspace_id"],
      service_account_id: ids["anthropic_service_account_id"],
      federation_rule_id: ids["anthropic_federation_rule_id"]
    }
  end

  defp field_errors(changeset) do
    Map.new(changeset.errors, fn {field, {message, _opts}} -> {to_string(field), message} end)
  end

  defp exchange_error({:federation_rejected, %{status: 401}}) do
    dgettext(
      "dashboard_integrations",
      "Anthropic rejected the token. Check that the rule uses the issuer URL and subject prefix from step 1 and names this service account. The authentication history in the Claude Console shows the reason."
    )
  end

  defp exchange_error({:federation_rejected, %{message: message}}) do
    dgettext("dashboard_integrations", "Anthropic rejected the request: %{message}", message: message)
  end

  defp exchange_error(%{status: 403}) do
    dgettext(
      "dashboard_integrations",
      "Anthropic refused to create the environment. Set the federation rule's scope to workspace:developer."
    )
  end

  defp exchange_error(%{status: status, message: message}) do
    dgettext("dashboard_integrations", "Anthropic answered %{status}: %{message}", status: status, message: message)
  end

  defp exchange_error(_reason) do
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

  defp authentication(%AgentEnvironment{} = agent_environment) do
    cond do
      Federation.federated?(agent_environment) -> dgettext("dashboard_integrations", "Federated")
      is_binary(agent_environment.anthropic_api_key) -> dgettext("dashboard_integrations", "API key")
      true -> dgettext("dashboard_integrations", "No credentials")
    end
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
        history_url: Federation.authentication_history_url(),
        step_titles: %{
          1 => dgettext("dashboard_integrations", "Trust Tuist in the Claude Console"),
          2 => dgettext("dashboard_integrations", "Paste the federation IDs"),
          3 => dgettext("dashboard_integrations", "Create the environment"),
          4 => dgettext("dashboard_integrations", "Finish")
        }
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
              "Run Claude Managed Agents sessions on Tuist sandboxes, without an Anthropic API key."
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
            variant={if @environments == [], do: "primary", else: "secondary"}
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
            label={authentication(environment)}
            color={if Federation.federated?(environment), do: "success", else: "neutral"}
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
        <div data-part="claude-wizard" data-step={@step}>
          <span data-part="step-indicator">
            {dgettext("dashboard_integrations", "Step %{step} of 4", step: @step)} · {@step_titles[
              @step
            ]}
          </span>
          <.alert
            :if={@error}
            id="claude-wizard-error"
            status="error"
            type="secondary"
            size="small"
            title={@error}
          />
          <.link_button
            :if={@error && @rejected && @step == 2}
            href={@history_url}
            target="_blank"
            rel="noopener noreferrer"
            label={dgettext("dashboard_integrations", "Open the authentication history")}
            variant="primary"
            underline
          />

          <div :if={@step == 1} data-part="step">
            <p>
              {dgettext(
                "dashboard_integrations",
                "In the Claude Console, open Workload identity, click Connect workload and choose Custom OIDC. Use these values, keep the default discovery JWKS source, and add the service account to the workspace that should run the sessions."
              )}
            </p>
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
            <div data-part="actions">
              <.button
                type="button"
                variant="secondary"
                label={dgettext("dashboard_integrations", "Open the Claude Console")}
                href={@console_wif_url}
                target="_blank"
                rel="noopener noreferrer"
              />
              <.button
                type="button"
                variant="primary"
                label={dgettext("dashboard_integrations", "Next")}
                phx-click="go"
                phx-value-step="2"
                phx-target={@myself}
              />
            </div>
          </div>

          <form
            :if={@step == 2}
            id={"claude-ids-form-#{@form_version}"}
            data-part="step"
            phx-change="ids-change"
            phx-submit="verify"
            phx-target={@myself}
            autocomplete="off"
          >
            <p>
              {dgettext(
                "dashboard_integrations",
                "The federation rule's page in the Claude Console shows an exchange snippet with all four IDs. Paste it here, or enter the IDs below. None of them is a secret."
              )}
            </p>
            <.text_area
              id={"claude-snippet-#{@form_version}"}
              name="snippet"
              value=""
              label={dgettext("dashboard_integrations", "Exchange snippet")}
              rows={3}
              max_length={4000}
              show_character_count={false}
              placeholder="fdrl_…  svac_…  wrkspc_…"
            />
            <.text_input
              id="claude-organization-id"
              name="anthropic_organization_id"
              value={@ids["anthropic_organization_id"]}
              label={dgettext("dashboard_integrations", "Organization ID")}
              placeholder="00000000-0000-0000-0000-000000000000"
              error={@id_errors["anthropic_organization_id"]}
            />
            <.text_input
              id="claude-workspace-id"
              name="anthropic_workspace_id"
              value={@ids["anthropic_workspace_id"]}
              label={dgettext("dashboard_integrations", "Workspace ID")}
              placeholder="wrkspc_…"
              error={@id_errors["anthropic_workspace_id"]}
            />
            <.text_input
              id="claude-service-account-id"
              name="anthropic_service_account_id"
              value={@ids["anthropic_service_account_id"]}
              label={dgettext("dashboard_integrations", "Service account ID")}
              placeholder="svac_…"
              error={@id_errors["anthropic_service_account_id"]}
            />
            <.text_input
              id="claude-federation-rule-id"
              name="anthropic_federation_rule_id"
              value={@ids["anthropic_federation_rule_id"]}
              label={dgettext("dashboard_integrations", "Federation rule ID")}
              placeholder="fdrl_…"
              error={@id_errors["anthropic_federation_rule_id"]}
            />
            <div data-part="actions">
              <.button
                type="button"
                variant="secondary"
                label={dgettext("dashboard_integrations", "Back")}
                phx-click="go"
                phx-value-step="1"
                phx-target={@myself}
              />
              <.button
                type="submit"
                variant="primary"
                label={dgettext("dashboard_integrations", "Test connection")}
                phx-disable-with={dgettext("dashboard_integrations", "Testing…")}
              />
            </div>
          </form>

          <form
            :if={@step == 3}
            id={"claude-environment-form-#{@form_version}"}
            data-part="step"
            phx-submit="create-environment"
            phx-target={@myself}
            autocomplete="off"
          >
            <.alert
              status="success"
              type="secondary"
              size="small"
              title={dgettext("dashboard_integrations", "Anthropic accepted Tuist's token.")}
            />
            <p>
              {dgettext(
                "dashboard_integrations",
                "Tuist creates a self-hosted environment in your Claude workspace and runs every session started on it in a Tuist sandbox."
              )}
            </p>
            <.text_input
              id="claude-environment-name"
              name="name"
              value={@environment_name}
              label={dgettext("dashboard_integrations", "Environment name")}
            />
            <div data-part="actions">
              <.button
                type="button"
                variant="secondary"
                label={dgettext("dashboard_integrations", "Back")}
                phx-click="go"
                phx-value-step="2"
                phx-target={@myself}
              />
              <.button
                type="submit"
                variant="primary"
                label={dgettext("dashboard_integrations", "Create environment")}
                phx-disable-with={dgettext("dashboard_integrations", "Creating…")}
              />
            </div>
          </form>

          <form
            :if={@step == 4}
            id={"claude-finish-form-#{@form_version}"}
            data-part="step"
            phx-submit="connect"
            phx-target={@myself}
            autocomplete="off"
          >
            <.copy_row
              id="claude-environment-id"
              label={dgettext("dashboard_integrations", "Environment ID")}
              value={@anthropic_environment_id}
            />
            <p>
              {dgettext(
                "dashboard_integrations",
                "Anthropic only lets you generate the environment key in the Claude Console. Open the environment, click Generate environment key and paste it below."
              )}
            </p>
            <.link_button
              href={@console_environments_url}
              target="_blank"
              rel="noopener noreferrer"
              label={dgettext("dashboard_integrations", "Open environments in the Claude Console")}
              variant="primary"
              underline
            />
            <.text_input
              id={"claude-environment-key-#{@form_version}"}
              name="environment_key"
              type="password"
              input_type="password"
              label={dgettext("dashboard_integrations", "Environment key")}
              value=""
              required
              show_required
              hint={dgettext("dashboard_integrations", "Stored encrypted and never shown again.")}
            />
            <.select
              id="claude-shape"
              name="shape"
              value="linux-2-4096"
              label={dgettext("dashboard_integrations", "Sandbox shape")}
            >
              <:item :for={{value, label} <- shape_options()} value={value} label={label} />
            </.select>
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
