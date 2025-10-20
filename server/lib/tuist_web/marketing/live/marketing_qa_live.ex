defmodule TuistWeb.Marketing.MarketingQALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  def mount(_params, session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path
        {:cont, assign(socket, current_path: current_path)}
      end)
      |> TuistWeb.Authentication.mount_current_user(session)
      |> assign_initial_state()

    {:ok, socket}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:head_title, dgettext("marketing", "Tuist QA"))
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, false)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/qa/og.png")
     )
     |> assign(:head_description, dgettext("marketing", "Automate testing your apps for Apple platforms using agents."))}
  end

  def handle_event("add-to-waiting-list", %{"email" => email}, socket) do
    :ok = Tuist.Loops.add_to_qa_waiting_list(email)

    socket = assign(socket, :email_submitted?, true)

    {:noreply, socket}
  end

  defp assign_initial_state(socket) do
    socket
    |> assign(:form, to_form(%{"email" => ""}))
    |> assign(:email_submitted?, false)
  end
end
