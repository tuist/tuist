defmodule AtlasWeb.POCLive.Index do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Accounts.POCs

  @impl true
  def mount(_params, _session, socket) do
    pocs = POCs.list_pocs()

    {:ok,
     socket
     |> assign(:page_title, "POCs")
     |> assign(:pocs, pocs)
     |> assign(:can_manage?, POCs.can_manage?(socket.assigns.current_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="pocs">
      <div data-part="header">
        <div data-part="title-group">
          <h1>POCs</h1>
          <p>Proof-of-concept engagements with prospective customers.</p>
        </div>
        <div data-part="header-actions">
          <.button
            :if={@can_manage?}
            label="New POC"
            href={~p"/commercial/sales/pocs/new"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.circle_plus /></:icon_left>
          </.button>
        </div>
      </div>
      <.card icon="target" title="POCs">
        <.card_section>
          <div :if={@pocs == []} data-part="empty-state">
            <div data-part="empty-icon"><.icon name="target" /></div>
            <h2>No POCs yet</h2>
            <p>Create a POC to capture scope, context, and the public brief link.</p>
          </div>
          <.table
            :if={@pocs != []}
            id="pocs-table"
            rows={@pocs}
            row_navigate={fn poc -> ~p"/commercial/sales/pocs/#{poc.id}" end}
          >
            <:col :let={poc} label="POC">
              <.text_and_description_cell
                label={poc.title}
                description={account_label(poc)}
                icon="target"
              />
            </:col>
            <:col :let={poc} label="Hosting">
              <span>{humanize(poc.hosting)}</span>
            </:col>
            <:col :let={poc} label="Status">
              <span>{humanize(poc.status)}</span>
            </:col>
            <:col :let={poc} label="Public">
              <span>{if poc.public_token, do: "Published", else: "Draft"}</span>
            </:col>
            <:col :let={poc} label="Updated">
              <.time_cell time={poc.updated_at} />
            </:col>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp account_label(%{account: %{name: name}}) when is_binary(name), do: name
  defp account_label(_poc), do: nil

  defp humanize(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.capitalize()
  end

  defp humanize(value), do: to_string(value)
end
