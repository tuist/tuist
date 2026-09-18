defmodule AtlasWeb.ProjectLive.Show do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.ProjectKey
  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Webhook
  alias Atlas.Engineering.Projects.Webhooks
  alias AtlasWeb.Endpoint
  alias Phoenix.LiveView.JS

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(:page_title, project.name)
         |> assign(:project, project)
         |> assign_resource_forms(project)
         |> assign_webhook_resources(project, true)
         |> assign_project_form(Projects.change_project(project))
         |> assign(:delete_project_form, delete_project_form())
         |> assign(:errors_enabled?, Errors.enabled?())
         |> assign(:project_key, Errors.primary_project_key(project))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/engineering/projects")}
    end
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_project_form(socket, changeset)}
  end

  def handle_event("save", %{"project" => params}, socket) do
    update_project(socket, params)
  end

  def handle_event("link_repository", %{"repository" => params}, socket) do
    link_repository(socket, params)
  end

  def handle_event("close_link_repository", _params, socket) do
    {:noreply,
     socket
     |> assign_repository_form(Projects.change_repository_for_project(socket.assigns.project))
     |> push_event("close-modal", %{id: "link-repository-modal"})}
  end

  def handle_event("link_domain", %{"link_domain" => %{"domain_id" => domain_id}}, socket) do
    link_domain(socket, domain_id)
  end

  def handle_event("close_link_domain", _params, socket) do
    {:noreply,
     socket
     |> assign_link_domain_form(socket.assigns.available_domains)
     |> push_event("close-modal", %{id: "link-domain-modal"})}
  end

  def handle_event("close_delete_project", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_project_form, delete_project_form())
     |> push_event("close-modal", %{id: "delete-project-modal"})}
  end

  def handle_event("create_webhook", %{"webhook" => params}, socket) do
    do_create_webhook(socket, params)
  end

  def handle_event("select_webhook_source", %{"source" => source}, socket) do
    case parse_webhook_source(source) do
      {:ok, source} -> {:noreply, assign(socket, :selected_source, source)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_new_webhook", _params, socket) do
    {:noreply,
     socket
     |> assign(:webhook_form, webhook_form())
     |> assign(:selected_source, default_webhook_source())
     |> push_event("close-modal", %{id: "new-webhook-modal"})}
  end

  def handle_event("new_webhook_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:webhook_form, webhook_form())
     |> assign(:selected_source, default_webhook_source())}
  end

  def handle_event("new_webhook_modal_open_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("dismiss_created_webhook", _params, socket) do
    {:noreply, assign(socket, :created_webhook_url, nil)}
  end

  def handle_event("delete_webhook", %{"id" => id}, socket) do
    do_delete_webhook(socket, id)
  end

  def handle_event("delete_project", %{"name" => name}, socket) do
    if name == socket.assigns.project.name do
      {:ok, _project} = Projects.delete_project(socket.assigns.project)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Project deleted."))
       |> push_event("close-modal", %{id: "delete-project-modal"})
       |> push_navigate(to: ~p"/engineering/projects")}
    else
      {:noreply, assign(socket, :delete_project_form, delete_project_form())}
    end
  end

  def handle_event("remove_repository", %{"id" => repository_id}, socket) do
    remove_repository(socket, repository_id)
  end

  def handle_event("remove_domain", %{"id" => domain_id}, socket) do
    :ok = Projects.unlink_domain_from_project(socket.assigns.project, domain_id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Domain removed from project."))
     |> reload_project()}
  end

  def handle_event("rotate_error_key", _params, socket) do
    case Errors.rotate_project_key(socket.assigns.project) do
      {:ok, key} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Rotated. Update your Sentry-compatible client to the new Data Source Name.")
         )
         |> assign(:project_key, key)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not rotate the Data Source Name."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="project-show">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{@project.name}</h1>
          <p :if={@project.description}>{@project.description}</p>
        </div>
      </div>

      <.card title={gettext("Settings")} icon="apps">
        <.card_section>
          <.form
            id="edit-project-form"
            for={@project_form}
            phx-change="validate"
            phx-submit="save"
            data-part="form"
          >
            <.text_input
              id="project-name"
              field={@project_form[:name]}
              label={gettext("Name")}
              required={true}
              show_required={true}
            />
            <.text_area
              id="project-description"
              field={@project_form[:description]}
              label={gettext("Description")}
              max_length={500}
              rows={4}
            />
            <div data-part="select-field">
              <span>{gettext("Visibility")}</span>
              <.select
                id="project-visibility"
                name={@project_form[:visibility].name}
                value={to_string(@project_form[:visibility].value)}
                label={gettext("Choose visibility")}
              >
                <:item value="public" label={gettext("Public")} icon="world" />
                <:item value="private" label={gettext("Private")} icon="lock" />
              </.select>
            </div>
            <div data-part="form-actions">
              <.button
                label={gettext("Save project")}
                size="medium"
                variant="primary"
              />
            </div>
          </.form>
        </.card_section>
      </.card>

      <.card
        :if={@errors_enabled? and @project_key}
        title={gettext("Error tracking")}
        icon="alert_hexagon"
      >
        <:actions>
          <.button
            variant="secondary"
            size="medium"
            label={gettext("Rotate")}
            phx-click="rotate_error_key"
            data-confirm={
              gettext(
                "Rotating the Data Source Name invalidates the current one. Clients using it will need to be updated with the new value."
              )
            }
          />
        </:actions>

        <.card_section data-part="error-tracking-card">
          <p data-part="error-tracking-intro">
            {gettext(
              "Point any Sentry-compatible client at this Data Source Name and its events will show up on the Errors dashboard scoped to this project."
            )}
          </p>

          <div data-part="dsn-row">
            <div data-part="dsn-value">
              <code>{ProjectKey.dsn(@project_key, Endpoint.url())}</code>
              <.button
                id={"copy-dsn-#{@project_key.id}"}
                variant="secondary"
                size="small"
                icon_only
                type="button"
                phx-hook="Clipboard"
                data-clipboard-value={ProjectKey.dsn(@project_key, Endpoint.url())}
                aria-label={gettext("Copy Data Source Name")}
                data-part="copy-button"
              >
                <span data-part="copy-icon"><.icon name="copy" /></span>
                <span data-part="copy-check-icon"><.icon name="copy_check" /></span>
              </.button>
            </div>
            <div :if={@project_key.last_used_at} data-part="dsn-meta">
              {gettext("Last used %{when}",
                when: format_short_datetime(@project_key.last_used_at)
              )}
            </div>
            <div :if={!@project_key.last_used_at} data-part="dsn-meta">
              {gettext("Never used")}
            </div>
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Repositories")} icon="brand_github">
        <:actions>
          <.link_repository_modal form={@repository_form} />
        </:actions>

        <.card_section>
          <div data-part="resource-table">
            <.table
              id="project-repositories-table"
              rows={@project.github_repositories}
              row_key={fn repository -> "repository-#{repository.id}" end}
            >
              <:col :let={repository} label={gettext("Repository")}>
                <.text_and_description_cell
                  label={repository_full_name(repository)}
                  description={gettext("Linked repository")}
                  icon="brand_github"
                />
              </:col>
              <:col :let={repository} label="">
                <.button_cell>
                  <:button>
                    <.button
                      label={gettext("Remove repository")}
                      size="large"
                      variant="secondary"
                      icon_only={true}
                      phx-click="remove_repository"
                      phx-value-id={repository.id}
                      data-confirm={
                        gettext("Remove %{repository} from this project?",
                          repository: repository_full_name(repository)
                        )
                      }
                      title={gettext("Remove repository")}
                      aria-label={gettext("Remove repository")}
                    >
                      <.trash />
                    </.button>
                  </:button>
                </.button_cell>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="brand_github"
                  title={gettext("No repositories linked yet")}
                  subtitle={gettext("Linked repositories appear here.")}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Domains")} icon="treemap">
        <:actions>
          <.link_domain_modal
            form={@link_domain_form}
            available_domains={@available_domains}
          />
        </:actions>

        <.card_section>
          <div data-part="resource-table">
            <.table
              id="project-domains-table"
              rows={@project.domains}
              row_key={fn domain -> "domain-#{domain.id}" end}
            >
              <:col :let={domain} label={gettext("Domain")}>
                <div data-part="cell" data-type="text_and_description">
                  <div data-part="column">
                    <.link
                      navigate={~p"/engineering/domains/#{domain.id}"}
                      data-part="domain-title-link"
                    >
                      <span data-part="label">{domain.name}</span>
                    </.link>
                    <span data-part="description">
                      {domain.description || gettext("No description yet.")}
                    </span>
                  </div>
                </div>
              </:col>
              <:col :let={domain} label="">
                <.button_cell>
                  <:button>
                    <.button
                      label={gettext("Remove domain")}
                      size="large"
                      variant="secondary"
                      icon_only={true}
                      phx-click="remove_domain"
                      phx-value-id={domain.id}
                      data-confirm={
                        gettext("Remove %{domain} from this project?",
                          domain: domain.name
                        )
                      }
                      title={gettext("Remove domain")}
                      aria-label={gettext("Remove domain")}
                    >
                      <.trash />
                    </.button>
                  </:button>
                </.button_cell>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="treemap"
                  title={gettext("No domains defined")}
                  subtitle={gettext("Link a domain to slice this project's work.")}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>

      <%!--
      The webhook card mints URLs under `/webhooks/projects/:project_id/:source/:token`,
      but the ingest controller did not come across in this port. Hide the card
      (and hold back the matching MCP tools) until `Projects.ingest_webhook/4`
      returns something other than `:not_implemented`, so operators do not wire
      Grafana to a URL that returns 404. The helpers stay compiled so bringing
      the card back is a one-line revert.
      --%>
      <%= if false do %>
        <.webhooks_card
          webhooks={@webhooks}
          webhook_form={@webhook_form}
          webhook_sources={@webhook_sources}
          selected_source={@selected_source}
          created_webhook_url={@created_webhook_url}
        />
      <% end %>

      <.delete_project_section
        project={@project}
        delete_project_form={@delete_project_form}
      />
    </section>
    """
  end

  attr :form, :any, required: true

  defp link_repository_modal(assigns) do
    ~H"""
    <.modal
      id="link-repository-modal"
      title={gettext("Link repository")}
      description={gettext("Add a GitHub repository that belongs to this project.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_link_repository"
    >
      <:trigger :let={attrs}>
        <.button
          label={gettext("Link repository")}
          size="medium"
          variant="secondary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.brand_github />
      </:header_icon>

      <.form
        id="link-repository-form"
        for={@form}
        phx-submit="link_repository"
        data-part="form"
      >
        <.text_input
          field={@form[:owner]}
          label={gettext("Owner")}
          placeholder="tuist"
          required={true}
          show_required={true}
        />
        <.text_input
          field={@form[:name]}
          label={gettext("Name")}
          placeholder="tuist"
          required={true}
          show_required={true}
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
              phx-click="close_link_repository"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Link repository")}
              size="medium"
              variant="primary"
              type="submit"
              form="link-repository-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :form, :any, required: true
  attr :available_domains, :list, required: true

  defp link_domain_modal(assigns) do
    ~H"""
    <.modal
      id="link-domain-modal"
      title={gettext("Link domain")}
      description={gettext("Attach an existing reusable domain to this project.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_link_domain"
    >
      <:trigger :let={attrs}>
        <.button
          label={gettext("Link domain")}
          size="medium"
          variant="secondary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="treemap" />
      </:header_icon>

      <.form id="link-domain-form" for={@form} phx-submit="link_domain" data-part="form">
        <div :if={@available_domains == []} data-part="empty-link-options">
          <p>
            {gettext("Every existing domain is already linked to this project.")}
          </p>
        </div>

        <div :if={@available_domains != []} data-part="select-field">
          <span>{gettext("Domain")}</span>
          <.select
            id="link-project-domain"
            name={@form[:domain_id].name}
            value={Phoenix.HTML.Form.normalize_value("select", @form[:domain_id].value)}
            label={gettext("Choose domain")}
          >
            <:item :for={domain <- @available_domains} value={domain.id} label={domain.name} />
          </.select>
        </div>
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_link_domain"
            />
          </:action>
          <:action :if={@available_domains != []}>
            <.button
              label={gettext("Link domain")}
              size="medium"
              variant="primary"
              type="submit"
              form="link-domain-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :webhooks, :list, required: true
  attr :webhook_form, :any, required: true
  attr :webhook_sources, :list, required: true
  attr :selected_source, :atom, required: true
  attr :created_webhook_url, :string, default: nil

  defp webhooks_card(assigns) do
    ~H"""
    <.card title={gettext("Webhooks")} icon="webhook">
      <:actions>
        <.new_webhook_modal
          webhook_form={@webhook_form}
          webhook_sources={@webhook_sources}
          selected_source={@selected_source}
        />
      </:actions>

      <.card_section data-part="webhooks-card">
        <.alert
          :if={@created_webhook_url}
          status="success"
          size="large"
          title={gettext("Webhook URL")}
          data-part="created-webhook"
        >
          <p>{gettext("Copy this now. It is shown only once.")}</p>
          <code data-part="created-webhook-url">{@created_webhook_url}</code>
          <:action>
            <.button
              label={gettext("Dismiss")}
              size="small"
              variant="secondary"
              phx-click="dismiss_created_webhook"
            />
          </:action>
        </.alert>

        <div data-part="resource-table">
          <.table
            id="project-webhooks-table"
            rows={@webhooks}
            row_key={fn webhook -> "webhook-#{webhook.id}" end}
          >
            <:col :let={webhook} label={gettext("Name")}>
              <.text_and_description_cell
                label={webhook.name}
                description={
                  gettext("Created %{date}",
                    date: format_short_datetime(webhook.inserted_at)
                  )
                }
              />
            </:col>
            <:col :let={webhook} label={gettext("Source")}>
              <div data-part="cell" data-type="badge">
                <.badge
                  label={Webhook.source_label(webhook.source)}
                  color="information"
                  style="light-fill"
                  size="large"
                >
                  <:icon><.bell /></:icon>
                </.badge>
              </div>
            </:col>
            <:col :let={webhook} label={gettext("Last used")}>
              <.text_cell label={last_used_label(webhook.last_used_at)} />
            </:col>
            <:col :let={webhook} label="">
              <.button_cell>
                <:button>
                  <.button
                    label={gettext("Delete webhook")}
                    size="large"
                    variant="secondary"
                    icon_only={true}
                    phx-click="delete_webhook"
                    phx-value-id={webhook.id}
                    data-confirm={
                      gettext("Delete this webhook? The URL will stop working immediately.")
                    }
                    title={gettext("Delete webhook")}
                    aria-label={gettext("Delete webhook")}
                  >
                    <.trash />
                  </.button>
                </:button>
              </.button_cell>
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="webhook"
                title={gettext("No webhooks yet")}
                subtitle={gettext("Generate a webhook to ingest alerts for this project.")}
              />
            </:empty_state>
          </.table>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :webhook_form, :any, required: true
  attr :webhook_sources, :list, required: true
  attr :selected_source, :atom, required: true

  defp new_webhook_modal(assigns) do
    ~H"""
    <.modal
      id="new-webhook-modal"
      title={gettext("New webhook")}
      description={gettext("Generate a URL an external source can post alerts to.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_webhook"
      on_open_change="new_webhook_modal_open_change"
    >
      <:trigger :let={attrs}>
        <.button
          label={gettext("New webhook")}
          size="medium"
          variant="secondary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.bell />
      </:header_icon>
      <.form
        id="new-webhook-form"
        for={@webhook_form}
        phx-submit="create_webhook"
        data-part="form"
      >
        <.text_input
          field={@webhook_form[:name]}
          label={gettext("Name")}
          placeholder="Grafana production"
          required={true}
          show_required={true}
        />

        <div data-part="select-field">
          <span>{gettext("Source")}</span>
          <.select
            id="webhook-source"
            name={@webhook_form[:source].name}
            value={Atom.to_string(@selected_source)}
            label={Webhook.source_label(@selected_source)}
          >
            <:item
              :for={source <- @webhook_sources}
              value={Atom.to_string(source)}
              label={Webhook.source_label(source)}
              icon="bell"
            />
          </.select>
        </div>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_new_webhook"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Generate webhook")}
              size="medium"
              variant="primary"
              type="button"
              phx-click={JS.dispatch("submit", to: "#new-webhook-form")}
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :project, :map, required: true
  attr :delete_project_form, :any, required: true

  defp delete_project_section(assigns) do
    ~H"""
    <.card_section data-part="delete-project-card-section">
      <div data-part="header">
        <span data-part="title">{gettext("Delete project")}</span>
        <span data-part="subtitle">
          {gettext("This action cannot be undone.")}
        </span>
      </div>
      <div data-part="content">
        <.form
          data-part="form"
          for={@delete_project_form}
          id="delete-project-form"
          phx-submit="delete_project"
        >
          <.modal
            id="delete-project-modal"
            title={gettext("Are you sure you want to delete this?")}
            header_size="large"
            on_dismiss="close_delete_project"
          >
            <:trigger :let={attrs}>
              <.button
                label={gettext("Delete project")}
                variant="destructive"
                size="medium"
                {attrs}
              />
            </:trigger>
            <.line_divider />
            <.alert
              status="warning"
              type="secondary"
              size="small"
              title={
                gettext("Deleting the project will permanently remove its project links and sources")
              }
            />
            <.text_input
              label={gettext("Enter this project's name to confirm")}
              field={@delete_project_form[:name]}
              type="basic"
              placeholder={@project.name}
            />
            <.line_divider />
            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    type="reset"
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="medium"
                    phx-click="close_delete_project"
                  />
                </:action>
                <:action>
                  <.button
                    type="submit"
                    form="delete-project-form"
                    label={gettext("Delete")}
                    variant="destructive"
                    size="medium"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </.form>
      </div>
    </.card_section>
    """
  end

  defp do_create_webhook(socket, params) do
    case Webhooks.create(socket.assigns.project, params) do
      {:ok, {webhook, token}} ->
        url = webhook_ingest_url(socket.assigns.project.id, webhook.source, token)

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Webhook created. Copy the URL. It is shown only once.")
         )
         |> assign(:webhooks, Webhooks.list_for_project(socket.assigns.project))
         |> assign(:webhook_form, webhook_form())
         |> assign(:selected_source, default_webhook_source())
         |> assign(:created_webhook_url, url)
         |> push_event("close-modal", %{id: "new-webhook-modal"})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Couldn't create the webhook."))}
    end
  end

  defp do_delete_webhook(socket, id) do
    case Enum.find(socket.assigns.webhooks, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      webhook ->
        {:ok, _} = Webhooks.delete(webhook)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Webhook deleted."))
         |> assign(:webhooks, Webhooks.list_for_project(socket.assigns.project))}
    end
  end

  defp update_project(socket, params) do
    case Projects.update_project(socket.assigns.project, params) do
      {:ok, project} ->
        project = Projects.get_project!(project.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Project updated."))
         |> assign(:page_title, project.name)
         |> assign(:project, project)
         |> assign_resource_forms(project)
         |> assign_webhook_resources(project, true)
         |> assign_project_form(Projects.change_project(project))}

      {:error, changeset} ->
        {:noreply, assign_project_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp assign_project_form(socket, changeset), do: assign(socket, :project_form, to_form(changeset, as: :project))

  defp assign_resource_forms(socket, project) do
    available_domains = Projects.list_domains_available_for_project(project)

    socket
    |> assign(:available_domains, available_domains)
    |> assign_repository_form(Projects.change_repository_for_project(project))
    |> assign_link_domain_form(available_domains)
  end

  defp assign_repository_form(socket, changeset),
    do: assign(socket, :repository_form, to_form(changeset, as: :repository))

  defp assign_webhook_resources(socket, project, editable?) do
    socket
    |> assign(:webhook_sources, Webhook.sources())
    |> assign(:webhook_form, webhook_form())
    |> assign(:selected_source, default_webhook_source())
    |> assign(:created_webhook_url, nil)
    |> assign(:webhooks, if(editable?, do: Webhooks.list_for_project(project), else: []))
  end

  defp assign_link_domain_form(socket, available_domains) do
    assign(socket, :link_domain_form, link_domain_form(available_domains))
  end

  defp delete_project_form, do: to_form(%{"name" => ""})

  defp webhook_form do
    to_form(%{"name" => "", "source" => Atom.to_string(default_webhook_source())}, as: :webhook)
  end

  defp default_webhook_source, do: List.first(Webhook.sources())

  defp parse_webhook_source(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> :error
      source -> {:ok, source}
    end
  end

  defp webhook_ingest_url(project_id, source, token) do
    Endpoint.url() <> "/webhooks/projects/#{project_id}/#{source}/#{token}"
  end

  defp last_used_label(nil), do: gettext("never used")

  defp last_used_label(%DateTime{} = at), do: gettext("last used %{date}", date: format_short_datetime(at))

  defp format_short_datetime(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp link_domain_form([domain | _domains]), do: to_form(%{"domain_id" => domain.id}, as: :link_domain)

  defp link_domain_form([]), do: to_form(%{"domain_id" => ""}, as: :link_domain)

  defp link_repository(socket, params) do
    case Projects.create_repository_for_project(socket.assigns.project, params) do
      {:ok, _repository} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Repository linked."))
         |> reload_project()
         |> push_event("close-modal", %{id: "link-repository-modal"})}

      {:error, changeset} ->
        {:noreply, assign_repository_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp link_domain(socket, domain_id) do
    case Projects.link_domain_to_project(socket.assigns.project, domain_id) do
      {:ok, _domain} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Domain linked."))
         |> reload_project()
         |> push_event("close-modal", %{id: "link-domain-modal"})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Domain not found."))}
    end
  end

  defp remove_repository(socket, repository_id) do
    case Projects.delete_repository_from_project(socket.assigns.project, repository_id) do
      {:ok, _repository} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Repository removed from project."))
         |> reload_project()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Repository not found."))}
    end
  end

  defp reload_project(socket) do
    project = Projects.get_project!(socket.assigns.project.id)

    socket
    |> assign(:project, project)
    |> assign_resource_forms(project)
    |> assign(:webhooks, Webhooks.list_for_project(project))
  end

  defp repository_full_name(repository), do: "#{repository.owner}/#{repository.name}"
end
