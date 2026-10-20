defmodule AtlasWeb.PostmortemLive.Public do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  alias Atlas.Engineering.Postmortems
  alias AtlasWeb.Markdown

  @impl true
  def mount(%{"share_token" => token}, _session, socket) do
    case Postmortems.get_postmortem_by_share_token(token) do
      %{} = postmortem ->
        {:ok,
         socket
         |> assign(:page_title, Postmortems.title(postmortem))
         |> assign(:postmortem, postmortem)}

      nil ->
        {:ok,
         socket
         |> assign(:page_title, dgettext("postmortems", "Postmortem not available"))
         |> assign(:postmortem, nil)}
    end
  end

  @impl true
  def render(%{postmortem: nil} = assigns) do
    ~H"""
    <section id="postmortem-public-not-found">
      <h1>{dgettext("postmortems", "Postmortem not available")}</h1>
      <p>
        {dgettext(
          "postmortems",
          "This postmortem is either private or does not exist."
        )}
      </p>
    </section>
    """
  end

  def render(assigns) do
    ~H"""
    <section id="postmortem-public">
      <article data-part="article">
        <header data-part="header">
          <div data-part="brand">
            <img src={~p"/images/tuist-logo.svg"} alt="Atlas" />
            <span>Atlas</span>
          </div>
          <h1>{Postmortems.title(@postmortem)}</h1>
          <div data-part="meta">
            <span>{Calendar.strftime(@postmortem.inserted_at, "%B %d, %Y")}</span>
            <span :if={@postmortem.domains != []} data-part="domains">
              <span :for={domain <- @postmortem.domains} data-part="domain">{domain.name}</span>
            </span>
          </div>
        </header>
        <Markdown.content
          id={"postmortem-#{@postmortem.number}-public-body"}
          body={@postmortem.body}
          heading_offset={0}
          strip_leading_h1={true}
          data-part="body"
        />
        <section :if={@postmortem.action_items != []} data-part="action-items">
          <h2>{dgettext("postmortems", "Action items")}</h2>
          <ul>
            <li :for={action_item <- @postmortem.action_items} data-part="action-item">
              <span data-part="status" data-completed={to_string(!is_nil(action_item.completed_at))}>
                {if action_item.completed_at,
                  do: dgettext("postmortems", "Done"),
                  else: dgettext("postmortems", "Open")}
              </span>
              <span data-part="title">{action_item.title}</span>
            </li>
          </ul>
        </section>
      </article>
    </section>
    """
  end
end
