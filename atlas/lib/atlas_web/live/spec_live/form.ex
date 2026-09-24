defmodule AtlasWeb.SpecLive.Form do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Specs
  alias Atlas.Engineering.Specs.Spec

  @impl true
  def mount(params, _session, socket) do
    spec =
      if socket.assigns.live_action == :edit,
        do: Specs.get_spec_by_number!(params["number"]),
        else: %Spec{}

    domains = Domains.list_visible_domains(socket.assigns.current_user)
    projects = Projects.list_visible_projects(socket.assigns.current_user)

    spec = %{spec | domain_ids: Enum.map(spec.domains || [], & &1.id)}

    if (socket.assigns.live_action == :new and
          Specs.can_create?(socket.assigns.current_user)) or
         (socket.assigns.live_action == :edit and
            Specs.can_edit?(spec, socket.assigns.current_user)) do
      title =
        if socket.assigns.live_action == :new,
          do: dgettext("specs", "New spec"),
          else: dgettext("specs", "Edit spec")

      {:ok,
       socket
       |> assign(:page_title, title)
       |> assign(:spec, spec)
       |> assign(:domains, domains)
       |> assign(:projects, projects)
       |> assign(:selected_domain_ids, spec.domain_ids)
       |> assign_form(Specs.change_spec(spec))}
    else
      {:ok,
       socket
       |> put_flash(:error, dgettext("specs", "Only organization members can edit specs."))
       |> redirect(to: ~p"/engineering/specs")}
    end
  end

  @impl true
  def handle_event("validate", %{"spec" => params}, socket) do
    {:noreply,
     socket
     |> assign(:selected_domain_ids, selected_domain_ids(params))
     |> assign_form(
       socket.assigns.spec
       |> Specs.change_spec(params)
       |> Map.put(:action, :validate)
     )}
  end

  def handle_event("toggle_domain", %{"data" => domain_id}, socket) do
    selected_domain_ids =
      if domain_id in socket.assigns.selected_domain_ids,
        do: List.delete(socket.assigns.selected_domain_ids, domain_id),
        else: [domain_id | socket.assigns.selected_domain_ids]

    {:noreply, assign(socket, :selected_domain_ids, selected_domain_ids)}
  end

  def handle_event("save", %{"spec" => params}, socket) do
    result =
      if socket.assigns.live_action == :new,
        do: Specs.create_spec(params, socket.assigns.current_user),
        else: Specs.update_spec(socket.assigns.spec, params, socket.assigns.current_user)

    case result do
      {:ok, spec} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("specs", "Spec saved."))
         |> push_navigate(to: ~p"/engineering/specs/#{spec.number}")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("specs", "Only organization members can edit specs.")
         )}

      {:error, :locked} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("specs", "A spec write is in progress. Try again in a moment.")
         )}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :spec))

  @impl true
  def render(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <h1>
            {if @live_action == :new,
              do: dgettext("specs", "New spec"),
              else: dgettext("specs", "Edit spec")}
          </h1>
          <p>
            {dgettext(
              "specs",
              "Write the spec body in Markdown. Bind it to an engineering project so reviewers know where it lives."
            )}
          </p>
        </div>
      </div>
      <.card icon="file_text" title={dgettext("specs", "Spec")}>
        <.card_section>
          <.form for={@form} id="spec-form" phx-change="validate" phx-submit="save">
            <.text_input field={@form[:title]} label={dgettext("specs", "Title")} />
            <.text_input
              field={@form[:summary]}
              label={dgettext("specs", "Summary")}
              placeholder={dgettext("specs", "One line, no em dashes.")}
            />
            <.text_area
              field={@form[:body]}
              label={dgettext("specs", "Markdown body")}
              placeholder="# Spec title\n\nThe pitch..."
              rows={20}
              max_length={100_000}
            />
            <div data-part="select-field">
              <span>{dgettext("specs", "Engineering project")}</span>
              <.select
                id="spec-engineering-project"
                name={@form[:engineering_project_id].name}
                value={to_string(@form[:engineering_project_id].value)}
                label={dgettext("specs", "Choose project")}
              >
                <:item
                  :for={project <- @projects}
                  value={project.id}
                  label={project.name}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>{dgettext("specs", "Status")}</span>
              <.select
                id="spec-status"
                name={@form[:status].name}
                value={to_string(@form[:status].value)}
                label={dgettext("specs", "Choose status")}
              >
                <:item
                  :for={status <- @form[:status].value |> then(fn _ -> statuses() end)}
                  value={to_string(status)}
                  label={humanize_status(status)}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>{dgettext("specs", "Domains")}</span>
              <input
                :for={domain_id <- @selected_domain_ids}
                type="hidden"
                name="spec[domain_ids][]"
                value={domain_id}
              />
              <.dropdown
                id="spec-domains"
                label={domain_label(@domains, @selected_domain_ids)}
                close_on_select={false}
              >
                <.dropdown_item
                  :for={domain <- @domains}
                  value={domain.id}
                  label={domain.name}
                  checked={domain.id in @selected_domain_ids}
                  on_click="toggle_domain"
                />
              </.dropdown>
            </div>
            <div data-part="form-actions">
              <.button
                label={
                  if @live_action == :new,
                    do: dgettext("specs", "Create"),
                    else: dgettext("specs", "Save changes")
                }
                size="medium"
                variant="primary"
                type="submit"
              />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp statuses, do: Spec.statuses()

  defp humanize_status(status), do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp selected_domain_ids(params) do
    params
    |> Map.get("domain_ids", [])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp domain_label(_domains, []), do: dgettext("specs", "Select domains")

  defp domain_label(domains, selected_domain_ids) do
    domains
    |> Enum.filter(&(&1.id in selected_domain_ids))
    |> Enum.map_join(", ", & &1.name)
  end
end
