defmodule TuistWeb.Marketing.MarketingGlobeLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.CSP, only: [get_csp_nonce: 0]
  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Stats
  alias TuistWeb.Marketing.SocialCards

  def mount(_params, session, socket) do
    if connected?(socket), do: Stats.subscribe_globe()

    {:ok,
     socket
     |> TuistWeb.Authentication.mount_current_user(session)
     |> assign_snapshot(Stats.get_globe())
     # A display page for a screen: no support chat bubble over the globe.
     |> assign(:support_chat_disabled?, true)
     # The globe's first-paint placeholder is an inline script, so it needs
     # the request's CSP nonce (only the dead render matters — CSP is
     # enforced against the initial response's header).
     |> assign(:csp_nonce, get_csp_nonce())}
  end

  def handle_params(params, url, socket) do
    description = dgettext("marketing", "Watch Tuist's global cache turn compiled code into faster builds.")

    {:noreply,
     socket
     |> assign(:current_path, URI.parse(url).path)
     |> assign(:demo, params["demo"] == "true")
     |> assign(:head_title, dgettext("marketing", "A world of faster builds · Tuist"))
     |> assign(:head_description, description)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_image, SocialCards.image_url("cache"))
     # The figures are set in Geist Pixel (its Grid shape), which only this
     # page uses, so it comes from Google Fonts rather than the site's font
     # set. The shape axis is requested as a range and pinned in globe.css.
     |> assign(:head_stylesheets, [
       "https://fonts.googleapis.com/css2?family=Geist+Pixel:ELSH@0..100&display=swap"
     ])
     |> assign_feature_structured_data(dgettext("marketing", "Cache globe"), description, "/globe")}
  end

  def handle_info({:cache_globe_updated, snapshot}, socket) do
    {:noreply, assign_snapshot(socket, snapshot)}
  end

  # The DitherGlobe canvas reads its markers from a data attribute on mount,
  # so the initial render carries the regions with their current activity;
  # the CacheGlobe hook keeps them updated afterwards. Locations are
  # [latitude, longitude] in the snapshot.
  defp assign_snapshot(socket, snapshot) do
    markers =
      Enum.map(snapshot.regions, fn region ->
        %{lat: Enum.at(region.location, 0), lon: Enum.at(region.location, 1), active: region.recent_downloads > 0}
      end)

    socket
    |> assign(:snapshot, snapshot)
    |> assign(:server_now, DateTime.to_iso8601(DateTime.utc_now()))
    |> assign(:markers, JSON.encode!(markers))
  end
end
