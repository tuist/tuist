defmodule AtlasWeb.DomainLive.Show do
  @moduledoc false

  use AtlasWeb, :live_view

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Errors
  alias AtlasWeb.DomainComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        {:ok,
         socket
         |> assign(:page_title, domain.name)
         |> assign(:domain, domain)
         |> assign(:delete_domain_form, delete_domain_form())
         |> assign(:errors_enabled?, Errors.enabled?())
         |> assign_domain_keys(domain)
         |> assign_form(Domains.change_domain(domain))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Domain not found."))
         |> redirect(to: ~p"/engineering/domains")}
    end
  end

  # Load one DSN per linked project so the "Error tracking" card can
  # render Copy + Rotate per pair. `primary_domain_key/2` provisions
  # lazily so the first render mints the credential — no separate
  # "generate" step required.
  defp assign_domain_keys(socket, domain) do
    if socket.assigns[:errors_enabled?] do
      keys =
        Map.new(domain.projects, fn project ->
          {project.id, Errors.primary_domain_key(project, domain)}
        end)

      assign(socket, :domain_keys, keys)
    else
      assign(socket, :domain_keys, %{})
    end
  end

  @impl true
  def handle_event("validate", %{"domain" => params}, socket) do
    changeset =
      socket.assigns.domain
      |> Domains.change_domain(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"domain" => params}, socket) do
    update_domain(socket, params)
  end

  def handle_event("close_delete_domain", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_domain_form, delete_domain_form())
     |> push_event("close-modal", %{id: "delete-domain-modal"})}
  end

  def handle_event("rotate_domain_error_key", %{"project-id" => project_id}, socket) do
    case Enum.find(socket.assigns.domain.projects, &(&1.id == project_id)) do
      nil -> {:noreply, socket}
      project -> rotate_domain_key(socket, project)
    end
  end

  def handle_event("delete_domain", %{"name" => name}, socket) do
    if name == socket.assigns.domain.name do
      {:ok, _domain} = Domains.delete_domain(socket.assigns.domain)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Domain deleted."))
       |> push_event("close-modal", %{id: "delete-domain-modal"})
       |> push_navigate(to: ~p"/engineering/domains")}
    else
      {:noreply, assign(socket, :delete_domain_form, delete_domain_form())}
    end
  end

  defp rotate_domain_key(socket, project) do
    case Errors.rotate_domain_key(project, socket.assigns.domain) do
      {:ok, key} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Rotated. Update your Sentry-compatible client to the new Data Source Name.")
         )
         |> assign(:domain_keys, Map.put(socket.assigns.domain_keys, project.id, key))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not rotate the Data Source Name."))}
    end
  end

  defp update_domain(socket, params) do
    case Domains.update_domain(socket.assigns.domain, params) do
      {:ok, domain} ->
        domain = Domains.get_domain!(domain.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Domain updated."))
         |> assign(:page_title, domain.name)
         |> assign(:domain, domain)
         |> assign_form(Domains.change_domain(domain))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :domain))
  end

  defp delete_domain_form do
    to_form(%{"name" => ""})
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

  @impl true
  def render(assigns) do
    ~H"""
    <DomainComponents.domain_detail
      domain={@domain}
      editable?={true}
      admin?={true}
      errors_enabled?={@errors_enabled?}
      domain_keys={@domain_keys}
      form={@form}
      delete_domain_form={@delete_domain_form}
    />
    """
  end
end
