defmodule TuistWeb.Marketing.MarketingQALive do
  @moduledoc false
  use TuistWeb, :live_view

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog

  def mount(params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     # |> assign(
     #   :head_image,
     #   Tuist.Environment.app_url(path: "/marketing/images/og/blog.jpg")
     # )
     |> assign(:head_title, gettext("Tuist QA"))
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, false)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_description, gettext("Automate testing your apps for Apple platforms using agents."))}
  end
end
