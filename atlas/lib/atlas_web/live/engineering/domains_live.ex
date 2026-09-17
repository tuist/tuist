defmodule AtlasWeb.Engineering.DomainsLive do
  @moduledoc """
  Lists domains and renders per-domain detail. Ported from Hive's
  `HiveWeb.DomainLive.Index` + `.Show` with the Evolution / Postmortem /
  Specs side panels stripped.
  """

  use AtlasWeb, :live_view

  alias Atlas.Engineering.Domains

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Domains"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    domains = Domains.list_visible_domains(socket.assigns[:current_user])
    assign(socket, domains: domains)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case Domains.fetch_visible_domain(id, socket.assigns[:current_user]) do
      {:ok, domain} ->
        socket
        |> assign(:domain, domain)
        |> assign(:page_title, domain.name)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Domain not found."))
        |> push_navigate(to: ~p"/engineering/domains")
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-semibold">{gettext("Domains")}</h1>

      <div class="mt-6 space-y-3">
        <%= for domain <- @domains do %>
          <div class="border rounded p-4 hover:bg-neutral-50">
            <.link navigate={~p"/engineering/domains/#{domain.id}"} class="font-medium">
              {domain.name}
            </.link>
            <p :if={domain.description} class="text-sm text-neutral-500 mt-1">
              {domain.description}
            </p>
          </div>
        <% end %>

        <p :if={@domains == []} class="text-sm text-neutral-500">
          {gettext("No domains yet.")}
        </p>
      </div>
    </div>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="p-8 space-y-6">
      <div>
        <.link navigate={~p"/engineering/domains"} class="text-sm text-neutral-500">
          &larr; {gettext("Domains")}
        </.link>
        <h1 class="text-2xl font-semibold mt-2">{@domain.name}</h1>
        <p :if={@domain.description} class="text-neutral-500">{@domain.description}</p>
      </div>

      <section>
        <h2 class="text-lg font-medium">{gettext("Linked projects")}</h2>
        <ul class="mt-2 space-y-1">
          <%= for project <- @domain.projects do %>
            <li>
              <.link navigate={~p"/engineering/projects/#{project.id}"}>{project.name}</.link>
            </li>
          <% end %>
          <li :if={@domain.projects == []} class="text-sm text-neutral-500">
            {gettext("No projects linked.")}
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
