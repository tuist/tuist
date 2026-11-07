defmodule TuistWeb.Marketing.MarketingPreviewsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias TuistWeb.Marketing.SocialCards

  embed_templates "marketing_previews_live/*"

  def render(assigns), do: previews(assigns)

  def mount(_params, session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path
        {:cont, assign(socket, current_path: current_path)}
      end)
      |> TuistWeb.Authentication.mount_current_user(session)

    {:ok, socket}
  end

  def handle_params(_params, _url, socket) do
    description =
      dgettext(
        "marketing",
        "Share iOS and Android app builds from a link. Run them on compatible simulators, emulators, or devices, subject to platform and signing requirements."
      )

    {:noreply,
     socket
     |> assign(:head_title, dgettext("marketing", "Share iOS and Android app previews from a link · Tuist"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       SocialCards.image_url("previews")
     )
     |> assign(:head_description, description)
     |> assign_feature_structured_data(dgettext("marketing", "Previews"), description, "/previews")}
  end
end
