defmodule TuistWeb.Marketing.MarketingPreviewsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias TuistWeb.Marketing.Design

  embed_templates "marketing_previews_live/*"
  # The redesigned template lives in new/; the suffix keeps its function name
  # (previews_new/1) distinct from the legacy previews/1.
  embed_templates "marketing_previews_live/new/*", suffix: "_new"

  def render(%{new_design: true} = assigns), do: previews_new(assigns)
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

    socket = assign(socket, :new_design, Design.new?(socket.assigns[:current_user], :previews))

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
