defmodule TuistWeb.Marketing.MarketingCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Marketing.Stats

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

    {:ok, socket}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:head_title, dgettext("marketing", "Cache · Tuist"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/og/cache.jpg")
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
