defmodule TuistWeb.ErrorHTML do
  use TuistWeb, :html

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/tuist_web/controllers/error_html/404.html.heex
  #   * lib/tuist_web/controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  def render("401.html", assigns) do
    render_error_page(
      assigns
      |> Map.put(:head_title, gettext("Unauthorized"))
      |> Map.put(:title, gettext("You are not authorized to view this page."))
      |> Map.put(
        :message,
        gettext(
          "Please, make sure you are accessing the right resource and that you have the permissions to access it."
        )
      )
      |> Map.put(:error_name, gettext("401 error"))
    )
  end

  def render("404.html", assigns) do
    reason = assigns.reason

    reason_message =
      if is_nil(reason) do
        gettext("Sorry, the page you are looking for doesn't exist or has been moved.")
      else
        reason.message
      end

    render_error_page(
      assigns
      |> Map.put(:head_title, gettext("Not found"))
      |> Map.put(:title, gettext("We can't find that page."))
      |> Map.put(
        :message,
        reason_message
      )
      |> Map.put(:error_name, gettext("404 error"))
    )
  end

  def render("429.html", assigns) do
    reason = assigns.reason

    reason_message =
      if is_nil(reason) do
        gettext("Sorry, you made too many requests. Please try again later.")
      else
        reason.message
      end

    render_error_page(
      assigns
      |> Map.put(:head_title, gettext("Too many requests"))
      |> Map.put(:title, gettext("Too many requests."))
      |> Map.put(
        :message,
        reason_message
      )
      |> Map.put(:error_name, gettext("429 error"))
    )
  end

  def render("500.html", assigns) do
    render_error_page(
      assigns
      |> Map.put(:head_title, gettext("Server error"))
      |> Map.put(:title, gettext("Oops! Something went wrong."))
      |> Map.put(
        :message,
        gettext(
          "Sorry, something went wrong on our side. Contact us at contact@tuist.io and we'll look into it."
        )
      )
      |> Map.put(:error_name, gettext("500 error"))
    )
  end

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  def render_error_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title>{"#{@head_title || gettext("Error")} · Tuist"}</.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/app/css/app.css"} />
        <link phx-track-static rel="stylesheet" href={~p"/app/css/app/pages/error.css"} />
      </head>
      <body>
        <div class="page error-page">
          <p class="text--medium font--semibold color--text-brand-secondary">{@error_name}</p>
          <h2 class="color--text-primary error-page__title">{@title}</h2>
          <p class="text--extraLarge font--regular color--text-tertiary">{@message}</p>
          <.button variant="secondary" class="error-page__home-button">
            <a href={~p"/"}>{gettext("Take me home")}</a>
          </.button>
        </div>
      </body>
    </html>
    """
  end
end
