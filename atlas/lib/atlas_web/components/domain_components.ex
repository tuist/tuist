defmodule AtlasWeb.DomainComponents do
  @moduledoc """
  Presentational components for the domains section.
  """

  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Errors.ProjectKey
  alias AtlasWeb.Endpoint

  attr :domains, :list, required: true
  attr :editable?, :boolean, default: false
  attr :form, :any, required: true

  def domains(assigns) do
    ~H"""
    <section id="domains">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{gettext("Domains")}</h1>
          <p>{gettext("The domains this Atlas instance plans and routes work for.")}</p>
        </div>
      </div>

      <.card icon="treemap" title={gettext("Domains")} data-part="domains-card">
        <:actions :if={@editable?}>
          <.new_domain_modal form={@form} />
        </:actions>
        <.card_section data-part="domains-section">
          <div data-part="domains-table">
            <.table
              id="domains-table"
              rows={@domains}
              row_key={fn domain -> "domain-#{domain.id || domain.name}" end}
              row_navigate={
                if @editable?, do: fn domain -> ~p"/engineering/domains/#{domain.id}" end, else: nil
              }
            >
              <:col :let={domain} label={gettext("Domain")}>
                <.text_and_description_cell
                  label={domain.name}
                  description={domain_description(domain)}
                />
              </:col>
              <:col :let={domain} label={gettext("Projects")}>
                <div data-part="cell" data-type="badge">
                  <div data-part="project-cell">
                    <.badge
                      :if={domain_projects(domain) == []}
                      label={gettext("No project")}
                      color="neutral"
                      style="light-fill"
                      size="large"
                    />
                    <.badge
                      :for={project <- domain_projects(domain)}
                      label={project.name}
                      color="neutral"
                      style="light-fill"
                      size="large"
                    >
                      <:icon><.icon name="apps" /></:icon>
                    </.badge>
                  </div>
                </div>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="treemap"
                  title={gettext("No domains yet")}
                  subtitle={domain_empty_subtitle(@editable?)}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :domain, :map, required: true
  attr :editable?, :boolean, default: false
  attr :admin?, :boolean, default: false
  attr :errors_enabled?, :boolean, default: false
  attr :domain_keys, :map, default: %{}
  attr :form, :any, required: true
  attr :delete_domain_form, :any, default: nil

  def domain_detail(assigns) do
    ~H"""
    <section id="domains">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{@domain.name}</h1>
          <p>{domain_description(@domain)}</p>
        </div>
      </div>

      <div data-part="domain-detail-layout">
        <.card icon="treemap" title={gettext("Domain")}>
          <.card_section>
            <.form
              :if={@editable?}
              for={@form}
              id="edit-domain-form"
              phx-change="validate"
              phx-submit="save"
              data-part="form"
            >
              <.text_input
                field={@form[:name]}
                label={gettext("Name")}
                placeholder="Hive"
                required={true}
                show_required={true}
              />
              <.text_area
                field={@form[:description]}
                label={gettext("Description")}
                placeholder={gettext("What this domain covers inside the organization.")}
                max_length={500}
                rows={4}
              />

              <div data-part="form-actions">
                <.button
                  label={gettext("Save domain")}
                  size="medium"
                  variant="primary"
                />
              </div>
            </.form>
            <.domain_readonly :if={!@editable?} domain={@domain} />
          </.card_section>
        </.card>

        <.domain_error_tracking_card
          :if={@admin? and @errors_enabled?}
          domain={@domain}
          domain_keys={@domain_keys}
        />

        <.delete_domain_section
          :if={@editable?}
          domain={@domain}
          delete_domain_form={@delete_domain_form}
        />
      </div>
    </section>
    """
  end

  attr :domain, :map, required: true
  attr :domain_keys, :map, required: true

  defp domain_error_tracking_card(assigns) do
    ~H"""
    <.card
      title={gettext("Error tracking")}
      icon="alert_hexagon"
    >
      <.card_section data-part="domain-error-tracking-card">
        <p data-part="domain-error-tracking-intro">
          {gettext(
            "Point any Sentry-compatible client at these Data Source Names and its events will be attributed to this domain automatically. One credential per linked project, so rotating one only cuts off that subsystem."
          )}
        </p>

        <div :if={domain_projects(@domain) == []} data-part="domain-error-tracking-empty">
          <p>
            {gettext(
              "Link this domain to a project first. Each linked project gets its own Data Source Name."
            )}
          </p>
        </div>

        <ul :if={domain_projects(@domain) != []} data-part="domain-dsn-list">
          <li
            :for={project <- domain_projects(@domain)}
            data-part="domain-dsn-row"
            id={"domain-dsn-#{project.id}"}
          >
            <div data-part="dsn-project-label">
              <.icon name="apps" />
              <span>{project.name}</span>
            </div>

            <.domain_dsn_value
              :if={Map.get(@domain_keys, project.id)}
              project={project}
              key={Map.get(@domain_keys, project.id)}
            />

            <div :if={is_nil(Map.get(@domain_keys, project.id))} data-part="dsn-meta">
              {gettext("Data Source Name unavailable.")}
            </div>
          </li>
        </ul>
      </.card_section>
    </.card>
    """
  end

  attr :project, :map, required: true
  attr :key, :map, required: true

  defp domain_dsn_value(assigns) do
    ~H"""
    <div data-part="dsn-row">
      <div data-part="dsn-value">
        <code>{ProjectKey.dsn(@key, Endpoint.url())}</code>
        <.button
          id={"copy-domain-dsn-#{@key.id}"}
          variant="secondary"
          size="small"
          icon_only
          type="button"
          phx-hook="Clipboard"
          data-clipboard-value={ProjectKey.dsn(@key, Endpoint.url())}
          aria-label={gettext("Copy Data Source Name")}
          data-part="copy-button"
        >
          <span data-part="copy-icon"><.icon name="copy" /></span>
          <span data-part="copy-check-icon"><.icon name="copy_check" /></span>
        </.button>
        <.button
          variant="secondary"
          size="small"
          label={gettext("Rotate")}
          phx-click="rotate_domain_error_key"
          phx-value-project-id={@project.id}
          data-confirm={
            gettext(
              "Rotating invalidates the current Data Source Name for %{project}. Clients using it will need to be updated with the new value.",
              project: @project.name
            )
          }
        />
      </div>
      <div :if={@key.last_used_at} data-part="dsn-meta">
        {gettext("Last used %{when}",
          when: format_short_datetime(@key.last_used_at)
        )}
      </div>
      <div :if={!@key.last_used_at} data-part="dsn-meta">
        {gettext("Never used")}
      </div>
    </div>
    """
  end

  defp format_short_datetime(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  attr :domain, :map, required: true
  attr :delete_domain_form, :any, required: true

  defp delete_domain_section(assigns) do
    ~H"""
    <.card_section data-part="delete-domain-card-section">
      <div data-part="header">
        <span data-part="title">{gettext("Delete domain")}</span>
        <span data-part="subtitle">
          {gettext("This action cannot be undone.")}
        </span>
      </div>
      <div data-part="content">
        <.form
          data-part="form"
          for={@delete_domain_form}
          id="delete-domain-form"
          phx-submit="delete_domain"
        >
          <.modal
            id="delete-domain-modal"
            title={gettext("Are you sure you want to delete this?")}
            header_size="large"
            on_dismiss="close_delete_domain"
          >
            <:trigger :let={attrs}>
              <.button
                label={gettext("Delete domain")}
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
              title={gettext("Deleting the domain will permanently remove all of its data")}
            />
            <.text_input
              label={gettext("Enter this domain's name to confirm")}
              field={@delete_domain_form[:name]}
              type="basic"
              placeholder={@domain.name}
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
                    phx-click="close_delete_domain"
                  />
                </:action>
                <:action>
                  <.button
                    type="submit"
                    form="delete-domain-form"
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

  attr :domain, :map, required: true

  defp domain_readonly(assigns) do
    ~H"""
    <dl data-part="domain-readonly">
      <div data-part="row">
        <dt>{gettext("Projects")}</dt>
        <dd>
          <div data-part="project-cell">
            <.badge
              :if={domain_projects(@domain) == []}
              label={gettext("No project")}
              color="neutral"
              style="light-fill"
              size="large"
            />
            <.badge
              :for={project <- domain_projects(@domain)}
              label={project.name}
              color="neutral"
              style="light-fill"
              size="large"
            >
              <:icon><.icon name="apps" /></:icon>
            </.badge>
          </div>
        </dd>
      </div>
    </dl>
    """
  end

  defp domain_empty_subtitle(true), do: gettext("Create the first domain to give Atlas a domain boundary.")

  defp domain_empty_subtitle(false), do: gettext("Organization members will populate this list.")

  defp domain_projects(%{projects: %Ecto.Association.NotLoaded{}}), do: []
  defp domain_projects(%{projects: projects}) when is_list(projects), do: projects
  defp domain_projects(_domain), do: []

  attr :form, :any, required: true

  defp new_domain_modal(assigns) do
    ~H"""
    <.modal
      id="new-domain-modal"
      title={gettext("New domain")}
      description={gettext("Create a reusable domain the team can link to projects.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_domain"
    >
      <:trigger :let={attrs}>
        <.button label={gettext("Add domain")} size="medium" variant="primary" {attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.package />
      </:header_icon>
      <.form id="new-domain-form" for={@form} phx-submit="save" data-part="form">
        <.text_input
          field={@form[:name]}
          label={gettext("Name")}
          placeholder="Hive"
          required={true}
          show_required={true}
        />
        <.text_area
          field={@form[:description]}
          label={gettext("Description")}
          placeholder={gettext("What this domain covers inside the organization.")}
          max_length={500}
          rows={4}
        />
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="medium"
              phx-click="close_new_domain"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Create domain")}
              size="medium"
              variant="primary"
              form="new-domain-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp domain_description(%{description: description}) when description in [nil, ""] do
    gettext("No description")
  end

  defp domain_description(%{description: description}), do: description
end
