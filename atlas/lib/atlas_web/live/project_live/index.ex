defmodule AtlasWeb.ProjectLive.Index do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Project

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    {:ok,
     socket
     |> assign(:page_title, gettext("Projects"))
     |> assign(:projects, list_projects(user))
     |> assign_project_form(Projects.change_project())}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_project_form(socket, changeset)}
  end

  def handle_event("create", %{"project" => params}, socket) do
    create_project(socket, params)
  end

  def handle_event("cancel_new_project", _params, socket) do
    {:noreply,
     socket
     |> assign_project_form(Projects.change_project())
     |> push_event("close-modal", %{id: "new-project-modal"})
     |> push_event("reset-form", %{id: "new-project-form"})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="projects">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{gettext("Projects")}</h1>
          <p>
            {gettext(
              "The products, codebases, and services this Atlas instance tracks. Each project owns its linked GitHub repositories and can link to the domains the team slices by."
            )}
          </p>
        </div>
        <div data-part="header-actions">
          <.new_project_modal form={@project_form} />
        </div>
      </div>

      <.card title={gettext("All projects")} icon="apps">
        <.card_section>
          <div data-part="projects-table">
            <.table
              id="projects-table"
              rows={@projects}
              row_key={fn project -> "project-#{project.id || project.name}" end}
            >
              <:col :let={project} label={gettext("Project")}>
                <div data-part="cell" data-type="text_and_description">
                  <div data-part="column">
                    <.link
                      navigate={~p"/engineering/projects/#{project.id}"}
                      data-part="project-title-link"
                    >
                      <span data-part="label">{project.name}</span>
                    </.link>
                    <span data-part="description">
                      {project.description || gettext("No description yet.")}
                    </span>
                  </div>
                </div>
              </:col>
              <:col :let={project} label={gettext("Visibility")}>
                <div data-part="cell" data-type="badge">
                  <.badge
                    label={visibility_label(project.visibility)}
                    color={visibility_color(project.visibility)}
                    style="light-fill"
                    size="large"
                  >
                    <:icon>
                      <.lock :if={project.visibility == :private} />
                      <.world :if={project.visibility != :private} />
                    </:icon>
                  </.badge>
                </div>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="apps"
                  title={gettext("No projects yet")}
                  subtitle={gettext("Create one to start tracking releases and changelog updates.")}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp visibility_label(:public), do: gettext("Public")
  defp visibility_label(:private), do: gettext("Private")
  defp visibility_label(_), do: "—"

  defp visibility_color(:public), do: "success"
  defp visibility_color(:private), do: "attention"
  defp visibility_color(_), do: "neutral"

  defp create_project(socket, params) do
    case Projects.create_project(params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Project created."))
         |> assign(:projects, list_projects(socket.assigns[:current_user]))
         |> assign_project_form(Projects.change_project())
         |> push_event("close-modal", %{id: "new-project-modal"})
         |> push_event("reset-form", %{id: "new-project-form"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_project_form(Map.put(changeset, :action, :insert))
         |> push_event("open-modal", %{id: "new-project-modal"})}
    end
  end

  defp assign_project_form(socket, changeset) do
    assign(socket, :project_form, to_form(interpolate_errors(changeset), as: :project))
  end

  defp interpolate_errors(%Ecto.Changeset{} = changeset) do
    Map.update!(changeset, :errors, fn errors -> Enum.map(errors, &interpolate_error/1) end)
  end

  defp interpolate_error({field, {message, opts}}) do
    interpolated =
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)

    {field, {interpolated, opts}}
  end

  defp list_projects(user), do: user |> Projects.list_visible_projects() |> order_projects()

  defp order_projects(projects), do: Enum.sort_by(projects, &project_order/1)

  defp project_order(%{name: "Atlas"}), do: {0, "Atlas"}
  defp project_order(%{name: "Hive"}), do: {1, "Hive"}
  defp project_order(%{name: "Tuist"}), do: {2, "Tuist"}
  defp project_order(%{name: "Kura"}), do: {3, "Kura"}
  defp project_order(%{name: "Noora"}), do: {4, "Noora"}
  defp project_order(%{name: "Once"}), do: {5, "Once"}
  defp project_order(project), do: {6, String.downcase(project.name)}

  attr :form, :any, required: true

  defp new_project_modal(assigns) do
    ~H"""
    <.modal
      id="new-project-modal"
      title={gettext("New project")}
      description={
        gettext("Create a product, codebase, or service that can own domains and sources.")
      }
      header_type="icon"
      header_size="large"
      on_dismiss="cancel_new_project"
    >
      <:trigger :let={attrs}>
        <.button label={gettext("Add project")} size="medium" variant="primary" {attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="apps" />
      </:header_icon>

      <.form
        id="new-project-form"
        for={@form}
        phx-change="validate"
        phx-submit="create"
        data-part="form"
      >
        <.text_input
          id="new-project-name"
          field={@form[:name]}
          label={gettext("Name")}
          placeholder="Noora"
          required={true}
          show_required={true}
        />
        <.text_area
          id="new-project-description"
          field={@form[:description]}
          label={gettext("Description")}
          placeholder={gettext("What this project covers.")}
          max_length={500}
          rows={4}
        />
        <div data-part="select-field">
          <span>{gettext("Visibility")}</span>
          <.select
            id="new-project-visibility"
            name={@form[:visibility].name}
            value={Phoenix.HTML.Form.normalize_value("select", @form[:visibility].value)}
            label={gettext("Choose visibility")}
          >
            <:item value="public" label={gettext("Public")} icon="world" />
            <:item value="private" label={gettext("Private")} icon="lock" />
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
              phx-click="cancel_new_project"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Create project")}
              size="medium"
              variant="primary"
              type="submit"
              form="new-project-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end
end
