defmodule AtlasWeb.SearchPalette do
  @moduledoc """
  Renders the global Cmd/Ctrl+K search palette markup.

  Open/close state is driven entirely from JavaScript via the `SearchPalette`
  hook (toggled with the `data-open` attribute on the root). The form pushes
  search events to the host LiveView, where `AtlasWeb.LayoutLive` attaches a
  shared `handle_event` hook to resolve results.
  """

  use Phoenix.Component
  use Gettext, backend: AtlasWeb.Gettext
  use Noora

  use Phoenix.VerifiedRoutes,
    endpoint: AtlasWeb.Endpoint,
    router: AtlasWeb.Router,
    statics: AtlasWeb.static_paths()

  import AtlasWeb.RevenueComponents, only: [domain_favicon_url: 2]

  attr :id, :string, default: "search-palette"
  attr :query, :string, required: true
  attr :accounts, :list, required: true
  attr :form, :map, required: true

  def search_palette(assigns) do
    ~H"""
    <div id={@id} class="search-palette" phx-hook="SearchPalette" data-open="false">
      <div data-part="backdrop" data-action="close"></div>
      <div data-part="positioner">
        <div data-part="content">
          <.form
            for={@form}
            id={"#{@id}-form"}
            phx-change="search_palette_search"
            phx-submit="search_palette_search"
          >
            <div data-part="search">
              <.text_input
                id={"#{@id}-input"}
                field={@form[:query]}
                type="search"
                placeholder={gettext("Search accounts...")}
                phx-debounce="120"
              >
                <:suffix>
                  <.shortcut_key size="small">ESC</.shortcut_key>
                </:suffix>
              </.text_input>
            </div>
          </.form>

          <div data-part="results">
            <%= cond do %>
              <% String.trim(@query) == "" -> %>
                <div data-part="empty">
                  <p data-part="title">{gettext("Type to search")}</p>
                  <p data-part="description">
                    {gettext("Find accounts by name, domain, or handle.")}
                  </p>
                </div>
              <% @accounts == [] -> %>
                <div data-part="empty">
                  <p data-part="title">{gettext("No results")}</p>
                  <p data-part="description">
                    {gettext("Nothing matched \"%{query}\".", query: @query)}
                  </p>
                </div>
              <% true -> %>
                <ul data-part="group">
                  <li data-part="group-header">
                    <.building />
                    <span>{gettext("Accounts")}</span>
                  </li>
                  <li :for={account <- @accounts} data-part="item">
                    <.link
                      navigate={~p"/commercial/sales/accounts/#{account.id}"}
                      data-result-link
                      data-part="link"
                    >
                      <%= if account.primary_domain do %>
                        <img
                          data-part="favicon"
                          src={domain_favicon_url(account.primary_domain, 128)}
                          alt=""
                          referrerpolicy="no-referrer"
                          loading="lazy"
                        />
                      <% else %>
                        <.avatar
                          id={"#{@id}-result-#{account.id}-avatar"}
                          size="small"
                          name={account.name}
                        />
                      <% end %>
                      <div data-part="text">
                        <span data-part="title">{account.name}</span>
                        <span :if={account.primary_domain} data-part="description">
                          {account.primary_domain}
                        </span>
                      </div>
                    </.link>
                  </li>
                </ul>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
