defmodule TuistWeb.Marketing.MarketingPreviewsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

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
        "Share your app instantly with a URL. No TestFlight delays, just click and run on any simulator or device."
      )

    {:noreply,
     socket
     |> assign(:head_title, dgettext("marketing", "Previews · Tuist"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       Tuist.Environment.app_url(
         path:
           TuistWeb.Helpers.OpenGraph.image_path(:marketing,
             title: dgettext("marketing", "Previews")
           )
       )
     )
     |> assign(:head_description, description)
     |> assign_feature_structured_data(dgettext("marketing", "Previews"), description, "/previews")}
  end
end
