defmodule AtlasWeb.PeopleLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, gettext("People"))}

  def render(assigns) do
    ~H"""
    <section id="people" data-part="people">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("People")}</h1>
          <p data-part="description">
            {gettext("Your team, here in Atlas. Availability updates while the app is active.")}
          </p>
        </div>
      </div>
      <.card title={gettext("Team")} icon="users">
        <.card_section>
          <.table id="people-directory" rows={@streams.presence_people}>
            <:col :let={{_id, person}} label={gettext("Name")}>
              <.text_and_description_cell label={person.name} description={person.email}>
                <:image>
                  <.avatar id={"person-avatar-#{person.id}"} name={person.name} />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col :let={{_id, person}} label={gettext("Status")}>
              <.badge_cell
                label={if person.online, do: gettext("Online"), else: gettext("Offline")}
                color={if person.online, do: "success", else: "neutral"}
                style="light-fill"
                data-online={to_string(person.online)}
              />
            </:col>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end
end
