defmodule TuistWeb.Marketing.MarketingChangelogEntryLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Changelog
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.Design

  embed_templates "marketing_changelog_entry_live/*"
  # The redesigned template lives in new/; the suffix keeps its function name
  # (changelog_entry_new/1) distinct from the legacy changelog_entry/1.
  embed_templates "marketing_changelog_entry_live/new/*", suffix: "_new"

  def render(%{new_design: true} = assigns), do: changelog_entry_new(assigns)
  def render(assigns), do: changelog_entry(assigns)

  def mount(_params, session, socket) do
    {:ok, assign(socket, :new_design, Design.new?(session, :changelog_entry))}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    entry = Changelog.get_entry_by_id(id)

    if is_nil(entry) do
      raise NotFoundError
    end

    date = Timex.format!(entry.date, "{Mfull} {D}, {YYYY}")

    {:noreply,
     socket
     |> assign(:entry, entry)
     |> assign(:head_title, entry.title)
     |> assign(:head_description, entry.description)
     |> assign(
       :head_image,
       Tuist.Environment.app_url(
         path:
           OpenGraph.image_path(:changelog_entry,
             title: entry.title,
             description: entry.description,
             date: date,
             pull_request: entry.pull_request
           )
       )
     )
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, true)
     |> assign_structured_data(get_changelog_entry_structured_data(entry))}
  end
end
