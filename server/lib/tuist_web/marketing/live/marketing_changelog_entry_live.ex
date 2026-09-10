defmodule TuistWeb.Marketing.MarketingChangelogEntryLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Changelog
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.Design

  on_mount {TuistWeb.Authentication, :mount_current_user}

  embed_templates "marketing_changelog_entry_live/*"
  # The redesigned template lives in new/; the suffix keeps its function name
  # (changelog_entry_new/1) distinct from the legacy changelog_entry/1.
  embed_templates "marketing_changelog_entry_live/new/*", suffix: "_new"

  def render(%{new_design: true} = assigns), do: changelog_entry_new(assigns)
  def render(assigns), do: changelog_entry(assigns)

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :new_design, Design.new?(socket.assigns[:current_user], :changelog_entry))}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    entry = Changelog.get_entry_by_id(id)

    if is_nil(entry) do
      raise NotFoundError
    end

    date = Timex.format!(entry.date, "{Mfull} {D}, {YYYY}")

    {head_image, head_image_dimensions} = changelog_entry_head_image(entry, date)

    {:noreply,
     socket
     |> assign(:entry, entry)
     |> assign(:head_title, entry.title)
     |> assign(:head_description, entry.description)
     |> assign(:head_image, head_image)
     |> assign(:head_image_dimensions, head_image_dimensions)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, true)
     |> assign_article_head_meta(published_at: entry.date)
     |> put_structured_data([
       get_changelog_entry_structured_data(entry),
       get_breadcrumbs_structured_data([
         {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
         {dgettext("marketing", "Changelog"), Tuist.Environment.app_url(path: ~p"/changelog")},
         {entry.title, Tuist.Environment.app_url(path: "/changelog/#{entry.id}")}
       ])
     ])}
  end

  defp changelog_entry_head_image(entry, date) do
    case entry |> Changelog.get_entry_image_source() |> absolute_image_url() do
      nil ->
        {generated_changelog_image_url(entry, date), {1920, 1080}}

      image_url ->
        {image_url, nil}
    end
  end

  defp absolute_image_url(nil), do: nil

  defp absolute_image_url(source) do
    case URI.parse(source) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        source

      %URI{path: path} when is_binary(path) ->
        if String.starts_with?(path, "/") do
          source
          |> TuistWeb.Marketing.MarketingHTML.static_asset_path()
          |> then(&Tuist.Environment.app_url(path: &1))
        end

      _ ->
        nil
    end
  end

  defp generated_changelog_image_url(entry, date) do
    Tuist.Environment.app_url(
      path:
        OpenGraph.image_path(:changelog_entry,
          title: entry.title,
          description: entry.description,
          date: date,
          pull_request: entry.pull_request
        )
    )
  end
end
