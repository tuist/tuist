defmodule AtlasWeb.CodingSettingsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.CodingRepositories

  def mount(_params, _session, socket) do
    settings = CodingRepositories.settings(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       page_title: "Coding",
       installations: [],
       repositories: [],
       error: nil,
       loading: false,
       saving: false,
       form: settings_form(settings)
     )
     |> load_catalog(settings["installation_id"])}
  end

  def handle_event("change", %{"coding" => params}, socket) do
    params = Map.take(params, ~w(installation_id default_repository))
    changed? = params["installation_id"] != socket.assigns.form[:installation_id].value
    params = if changed?, do: Map.put(params, "default_repository", "_none"), else: params
    socket = assign(socket, form: to_form(params, as: :coding))
    {:noreply, if(changed?, do: load_catalog(socket, nullable(params["installation_id"])), else: socket)}
  end

  def handle_event("refresh", _params, socket),
    do: {:noreply, load_catalog(socket, nullable(socket.assigns.form[:installation_id].value))}

  def handle_event("save", %{"coding" => params}, %{assigns: %{saving: false, loading: false}} = socket) do
    user = socket.assigns.current_user
    settings = Map.new(~w(installation_id default_repository), &{&1, nullable(params[&1])})

    {:noreply,
     socket
     |> assign(saving: true)
     |> start_async(:save, fn ->
       Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> CodingRepositories.update(user, settings) end)
     end)}
  end

  def handle_event("save", _params, socket), do: {:noreply, socket}

  def handle_async(:catalog, {:ok, {:ok, catalog}}, socket),
    do:
      {:noreply,
       assign(socket,
         installations: catalog.installations,
         repositories: catalog.repositories,
         error: nil,
         loading: false
       )}

  def handle_async(:catalog, result, socket),
    do: {:noreply, assign(socket, repositories: [], error: failure(result), loading: false)}

  def handle_async(:save, {:ok, {:ok, settings}}, socket),
    do:
      {:noreply,
       socket
       |> assign(saving: false, form: settings_form(settings))
       |> put_flash(:info, "Coding preferences saved. Existing conversations and runs are unchanged.")}

  def handle_async(:save, result, socket),
    do: {:noreply, socket |> assign(saving: false) |> put_flash(:error, failure(result))}

  defp load_catalog(socket, installation) do
    if connected?(socket) do
      user = socket.assigns.current_user

      socket
      |> assign(loading: true, repositories: [], error: nil)
      |> start_async(:catalog, fn ->
        Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
          CodingRepositories.catalog(user, installation)
        end)
      end)
    else
      socket
    end
  end

  defp settings_form(settings),
    do: to_form(Map.new(settings, fn {key, value} -> {key, value || "_none"} end), as: :coding)

  defp nullable(value) when value in [nil, "", "_none"], do: nil
  defp nullable(value), do: value
  defp failure({:ok, {:error, reason}}), do: CodingRepositories.error_message(reason)
  defp failure(_), do: CodingRepositories.error_message(:unavailable)

  def render(assigns) do
    ~H"""
    <section id="coding-settings" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">Coding</h1>
          <p data-part="description">
            Choose a GitHub installation and a default repository for new private conversations.
          </p>
        </div>
        <.button
          id="coding-refresh"
          label="Refresh"
          variant="secondary"
          phx-click="refresh"
          disabled={@loading || @saving}
        />
      </div>
      <.card title="Repositories" icon="brand_github">
        <.card_section>
          <.form
            id="coding-settings-form"
            for={@form}
            phx-change="change"
            phx-submit="save"
            data-part="coding-settings-form"
          >
            <label for="coding-installation">GitHub App installation</label>
            <.select
              id="coding-installation"
              field={@form[:installation_id]}
              label="Choose installation"
              disabled={@saving || @loading}
            >
              <:item value="_none" label="No installation" />
              <:item
                :for={installation <- @installations}
                value={installation.id}
                label={installation.name}
              />
              <:item
                :if={
                  @form[:installation_id].value not in [nil, "", "_none"] &&
                    !Enum.any?(@installations, &(&1.id == @form[:installation_id].value))
                }
                value={@form[:installation_id].value}
                label="Saved installation · unavailable"
              />
            </.select>
            <label for="coding-default-repository">Default repository</label>
            <.select
              id="coding-default-repository"
              field={@form[:default_repository]}
              label="Choose repository"
              disabled={@saving || @loading || @form[:installation_id].value in [nil, "", "_none"]}
            >
              <:item value="_none" label="No default repository" />
              <:item
                :for={repository <- @repositories}
                value={repository.full_name}
                label={repository.full_name}
              />
              <:item
                :if={
                  @form[:default_repository].value not in [nil, "", "_none"] &&
                    !Enum.any?(@repositories, &(&1.full_name == @form[:default_repository].value))
                }
                value={@form[:default_repository].value}
                label={"#{@form[:default_repository].value} · not available"}
              />
            </.select>
            <p :if={@loading} id="coding-loading" role="status">Loading repositories…</p>
            <p :if={@error} id="coding-error" role="alert">{@error}</p>
            <.button
              id="coding-save"
              type="submit"
              label={if @saving, do: "Saving…", else: "Save preferences"}
              disabled={@loading || @saving}
            />
          </.form>
        </.card_section>
        <.card_section>
          <p data-part="description">
            Only repositories accessible to both you and the GitHub App appear here.
            You can override the repository in each private conversation. This does not clone code or enable a machine.
          </p>
          <.link navigate={~p"/settings/connections"}>Manage your GitHub connection</.link>
        </.card_section>
      </.card>
    </section>
    """
  end
end
