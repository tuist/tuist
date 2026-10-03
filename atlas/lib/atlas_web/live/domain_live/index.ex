defmodule AtlasWeb.DomainLive.Index do
  @moduledoc false

  use AtlasWeb, :live_view

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Domains.Domain
  alias AtlasWeb.DomainComponents

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    {:ok,
     socket
     |> assign(:page_title, gettext("Domains"))
     |> assign(:domains, Domains.list_visible_domains(user))
     |> assign_form(Domains.change_domain())}
  end

  @impl true
  def handle_event("close_new_domain", _params, socket) do
    {:noreply,
     socket
     |> reset_new_domain()
     |> push_event("close-modal", %{id: "new-domain-modal"})
     |> push_event("reset-form", %{id: "new-domain-form"})}
  end

  def handle_event("validate", %{"domain" => params}, socket) do
    changeset =
      %Domain{}
      |> Domains.change_domain(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"domain" => params}, socket) do
    create_domain(socket, params)
  end

  defp create_domain(socket, params) do
    case Domains.create_domain(params) do
      {:ok, _domain} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Domain created."))
         |> assign(:domains, Domains.list_visible_domains(socket.assigns[:current_user]))
         |> reset_new_domain()
         |> push_event("close-modal", %{id: "new-domain-modal"})
         |> push_event("reset-form", %{id: "new-domain-form"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :insert))
         |> push_event("open-modal", %{id: "new-domain-modal"})}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :domain))
  end

  defp reset_new_domain(socket) do
    assign_form(socket, Domains.change_domain())
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
    <DomainComponents.domains
      domains={@domains}
      editable?={true}
      form={@form}
    />
    """
  end
end
