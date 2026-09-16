defmodule TuistWeb.Marketing.MarketingGlobeLive do
  @moduledoc false
  use TuistWeb, :live_view

  alias Tuist.Marketing.Stats

  def mount(_params, _session, socket) do
    if connected?(socket), do: Stats.subscribe_globe()

    {:ok,
     socket
     |> assign(:snapshot, Stats.get_globe())
     |> assign(:support_chat_disabled?, true)
     |> assign(:head_title, dgettext("marketing", "A world of faster builds · Tuist"))
     |> assign(
       :head_description,
       dgettext("marketing", "Watch Tuist's global cache turn compiled code into faster builds.")
     )
     |> assign(:head_twitter_card, "summary_large_image")}
  end

  def handle_params(params, url, socket) do
    {:noreply,
     socket
     |> assign(:current_path, URI.parse(url).path)
     |> assign(:demo, params["demo"] == "true")}
  end

  def handle_info({:cache_globe_updated, snapshot}, socket) do
    {:noreply, assign(socket, :snapshot, snapshot)}
  end
end
