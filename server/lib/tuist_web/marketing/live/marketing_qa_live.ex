defmodule TuistWeb.Marketing.MarketingQALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  @mautic_qa_segment 3

  def mount(params, session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)
      |> TuistWeb.Authentication.mount_current_user(session)
      |> then(
        &if(is_nil(socket.assigns[:current_user]),
          do: &1,
          else:
            assign(&1,
              in_list_message:
                if(Tuist.Mautic.email_in_segment?(&1.assigns[:current_user].email, @mautic_qa_segment),
                  do: gettext("You are already in the waiting list")
                )
            )
        )
      )
      |> assign(:form, to_form(%{"email" => ""}))

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:head_title, gettext("Tuist QA"))
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, false)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/qa/og.png")
     )
     |> assign(:head_description, gettext("Automate testing your apps for Apple platforms using agents."))}
  end

  def handle_event("add-to-waiting-list", params, socket) do
    current_user = socket.assigns[:current_user]

    email =
      if is_nil(current_user) do
        params["email"]
      else
        current_user.email
      end

    {:ok, _} = Tuist.Mautic.add_email_to_segment(email, @mautic_qa_segment)
    socket = assign(socket, :in_list_message, gettext("Added to the waiting list"))
    {:noreply, socket}
  end
end
