defmodule TuistWeb.Marketing.MarketingCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Marketing.Stats
  alias TuistWeb.Marketing.Design

  embed_templates "marketing_cache_live/*"
  # The redesigned template lives in new/; the suffix keeps its function name
  # (cache_new/1) distinct from the legacy cache/1.
  embed_templates "marketing_cache_live/new/*", suffix: "_new"

  def render(%{new_design: true} = assigns), do: cache_new(assigns)
  def render(assigns), do: cache(assigns)

  def mount(_params, session, socket) do
    if connected?(socket), do: Stats.subscribe()
    stats = Stats.get_stats()

    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path
        {:cont, assign(socket, current_path: current_path)}
      end)
      |> TuistWeb.Authentication.mount_current_user(session)
      |> assign(:last_24h_artifacts_count, stats.cache_artifacts_last_24h)

    socket = assign(socket, :new_design, Design.new?(socket.assigns[:current_user], :cache))

    {:ok, socket}
  end

  # Column count of the redesigned hero's background chart.
  @hero_column_count 20

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:hero_column_count, @hero_column_count)
     |> assign(:head_title, dgettext("marketing", "Cache · Tuist"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       Tuist.Environment.app_url(
         path:
           TuistWeb.Helpers.OpenGraph.image_path(:marketing,
             title: dgettext("marketing", "Cache")
           )
       )
     )
     |> assign(
       :head_description,
       dgettext(
         "marketing",
         "Speeds up builds by reusing compiled binaries, cutting down build times in both local development and CI."
       )
     )}
  end

  def handle_info({:marketing_stats_updated, stats}, socket) do
    {:noreply, assign(socket, :last_24h_artifacts_count, stats.cache_artifacts_last_24h)}
  end
end
