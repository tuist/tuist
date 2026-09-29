defmodule TuistWeb.Marketing.MarketingCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.CSP, only: [get_csp_nonce: 0]
  import TuistWeb.Marketing.StructuredMarkup

  alias TuistWeb.Marketing.SocialCards

  embed_templates "marketing_cache_live/*"

  def render(assigns), do: cache(assigns)

  def mount(_params, session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path
        {:cont, assign(socket, current_path: current_path)}
      end)
      |> TuistWeb.Authentication.mount_current_user(session)
      # The globe's first-paint placeholder is an inline script, so it needs
      # the request's CSP nonce (only the dead render matters — CSP is
      # enforced against the initial response's header).
      |> assign(:csp_nonce, get_csp_nonce())

    {:ok, socket}
  end

  # Column count of the redesigned hero's background chart.
  @hero_column_count 20

  def handle_params(_params, _url, socket) do
    description =
      dgettext(
        "marketing",
        "Speeds up builds by reusing compiled binaries, cutting down build times in both local development and CI."
      )

    {:noreply,
     socket
     |> assign(:hero_column_count, @hero_column_count)
     |> assign(:head_title, dgettext("marketing", "Cache · Tuist"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       SocialCards.image_url("cache")
     )
     |> assign(:head_description, description)
     |> assign_feature_structured_data(dgettext("marketing", "Cache"), description, "/cache")}
  end
end
