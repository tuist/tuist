defmodule TuistWeb.Marketing.MarketingFlakyTestsLive do
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
      |> assign(:flaky_tests_last_24h, stats.flaky_tests_last_24h)

    {:ok, socket}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:head_title, dgettext("marketing", "Flaky Tests · Tuist"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       Tuist.Environment.app_url(
         path: TuistWeb.Helpers.OpenGraph.marketing_og_image_path("/marketing/images/og/generated/flaky-tests.jpg")
       )
     )
     |> assign(
       :head_description,
       dgettext(
         "marketing",
         "Automatically detect flaky tests that fail without code changes and reduce time spent investigating false failures."
       )
     )}
  end

  def handle_info({:marketing_stats_updated, stats}, socket) do
    {:noreply, assign(socket, :flaky_tests_last_24h, stats.flaky_tests_last_24h)}
  end
end
