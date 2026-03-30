defmodule TuistWeb.Marketing.MarketingChangelogEntryLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Changelog
  alias TuistWeb.Errors.NotFoundError

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    entry = Changelog.get_entry_by_id(id)

    if is_nil(entry) do
      raise NotFoundError
    end

    description =
      entry.body
      |> HtmlSanitizeEx.strip_tags()
      |> String.trim()
      |> String.slice(0, 160)

    {:noreply,
     socket
     |> assign(:entry, entry)
     |> assign(:head_title, entry.title)
     |> assign(:head_description, description)
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/og/generated/changelog/#{entry.id}.jpg")
     )
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, true)
     |> assign_structured_data(get_changelog_entry_structured_data(entry))}
  end
end
