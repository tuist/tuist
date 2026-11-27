defmodule TuistWeb.Noora.NooraLive do
  @moduledoc """
  Serves the Noora documentation at `/noora` and `/noora/:page`.
  """
  use TuistWeb, :live_view

  import TuistWeb.Noora.Components

  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Noora.Pages

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> TuistWeb.Authentication.mount_current_user(session)
     |> assign(:support_chat_disabled?, true)
     # English-only and unlisted until the documentation is complete.
     |> assign(:head_noindex, true)}
  end

  def handle_params(params, url, socket) do
    page =
      case params do
        %{"page" => slug} -> Pages.find(slug) || raise NotFoundError, "Noora page not found"
        _ -> Pages.introduction()
      end

    path = URI.parse(url).path
    user = socket.assigns.current_user

    cond do
      not Pages.team_only?(page) or Pages.team_member?(user) ->
        {:noreply,
         socket
         |> assign(:page, page)
         |> assign(:framed_example, framed_example(page, params))
         |> assign(:current_path, path)
         |> assign(:head_title, head_title(page))
         |> assign(:head_description, page.description())}

      # Team pages ask visitors to sign in, and come back here after.
      is_nil(user) ->
        {:noreply, redirect(socket, to: sign_in_path(path))}

      # Signed in, but not on the team: the page doesn't exist for them.
      true ->
        raise NotFoundError, "Noora page not found"
    end
  end

  # A device example's frame (docs_example) loads the page with its id, to
  # render that example alone.
  defp framed_example(page, %{"example" => id}) when is_binary(id) do
    Enum.find(page.examples(), &(&1.id == id)) || raise NotFoundError, "Noora example not found"
  end

  defp framed_example(_page, _params), do: nil

  defp sign_in_path(return_to), do: ~p"/docs/login?#{%{return_to: return_to}}"

  # Examples render real components, some of which emit events (a dismissed
  # alert, a changed toggle). The documentation has no state to update.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def render(%{framed_example: %{}} = assigns) do
    ~H"""
    <main class="noora-docs-device-preview">
      {apply(@page, @framed_example.function, [%{__changed__: nil}])}
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <.docs_shell page={@page} current_user={@current_user} current_path={@current_path}>
      <article id={"noora-page-#{@page.slug()}"} data-part="article">
        <.docs_page_header page={@page} />
        {if function_exported?(@page, :content, 1), do: @page.content(%{__changed__: nil})}
        <.docs_example :for={example <- @page.examples()} page={@page} example={example} />
        <.docs_guidelines page={@page} />
        <.docs_api_reference page={@page} />
        <.docs_page_footer page={@page} current_user={@current_user} />
      </article>
    </.docs_shell>
    """
  end

  defp head_title(Pages.Introduction), do: "Noora · Tuist"
  defp head_title(page), do: "#{page.title()} · Noora · Tuist"
end
