defmodule TuistWeb.ErrorHTML do
  use TuistWeb, :html
  use Noora

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/tuist_web/controllers/error_html/404.html.heex
  #   * lib/tuist_web/controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  def render("400.html", %{reason: %TuistWeb.Errors.BadRequestError{message: error_message}} = assigns) do
    assigns
    |> Map.put(:head_title, gettext("Bad request"))
    |> Map.put(:title, error_message)
    |> Map.put(
      :message,
      error_message
    )
    |> Map.put(:error_name, gettext("400"))
    |> render_error_page()
  end

  def render("401.html", assigns) do
    assigns
    |> Map.put(:head_title, gettext("Unauthorized"))
    |> Map.put(:title, gettext("You are not authorized to view this page"))
    |> Map.put(
      :message,
      gettext("Please, make sure you are accessing the right resource and that you have the permissions to access it.")
    )
    |> Map.put(:error_name, gettext("401"))
    |> render_error_page()
  end

  def render("404.html", assigns) do
    reason = assigns.reason

    reason_message =
      if is_nil(reason) do
        gettext("Sorry, the page you are looking for doesn't exist or has been moved.")
      else
        reason.message
      end

    assigns
    |> Map.put(:head_title, gettext("Not found"))
    |> Map.put(:title, gettext("Oops, we couldn't find that page"))
    |> Map.put(
      :message,
      reason_message
    )
    |> Map.put(:error_name, gettext("404"))
    |> render_error_page()
  end

  def render("429.html", assigns) do
    reason = assigns.reason

    reason_message =
      if is_nil(reason) do
        gettext("Sorry, you made too many requests. Please try again later.")
      else
        reason.message
      end

    assigns
    |> Map.put(:head_title, gettext("Too many requests"))
    |> Map.put(:title, gettext("Too many requests."))
    |> Map.put(
      :message,
      reason_message
    )
    |> Map.put(:error_name, gettext("429"))
    |> render_error_page()
  end

  def render("500.html", assigns) do
    assigns
    |> Map.put(:head_title, gettext("Server error"))
    |> Map.put(:title, gettext("Oops! Something went wrong"))
    |> Map.put(
      :message,
      gettext("Sorry, something went wrong on our side. Contact us at contact@tuist.dev and we'll look into it.")
    )
    |> Map.put(:error_name, gettext("500"))
    |> render_error_page()
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
      <script defer phx-track-static type="module" src={~p"/app/assets/bundle.js"}>
      </script>
      <script nonce={get_csp_nonce()}>
        function cssvar(name) {
          return getComputedStyle(document.documentElement).getPropertyValue(name);
        }
      </script>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csp-nonce" content={get_csp_nonce()} />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title>{"#{@head_title || gettext("Error")} · Tuist"}</.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/app/assets/bundle.css"} />
      </head>
      <body>
        <div id="error-page">
          <div data-part="header">
            <h1 data-part="title">
              {@error_name}
            </h1>
            <h2 data-part="subtitle">
              {@title}
            </h2>
          </div>
          <img src="/images/error_image_light.png" data-theme="light" />
          <img src="/images/error_image_dark.png" data-theme="dark" />
          <div data-part="background">
            <div data-part="top-right-gradient"></div>
            <div data-part="bottom-left-gradient"></div>
          </div>
          <.button
            variant="primary"
            size="large"
            label={gettext("Go to dashboard")}
            navigate={~p"/dashboard"}
          />
        </div>
      </body>
    </html>
    """
  end
end
