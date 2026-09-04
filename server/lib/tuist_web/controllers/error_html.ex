defmodule TuistWeb.ErrorHTML do
  use TuistWeb, :html
  use Noora

  alias TuistWeb.Marketing.Design
  alias TuistWeb.Marketing.Layouts
  alias TuistWeb.Marketing.MarketingHTML

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
    |> Map.put(:head_title, dgettext("dashboard", "Bad request"))
    |> Map.put(:title, error_message)
    |> Map.put(
      :message,
      error_message
    )
    |> Map.put(:error_name, dgettext("dashboard", "400"))
    |> render_error_page()
  end

  def render("401.html", %{reason: %TuistWeb.Errors.UnauthorizedError{message: error_message}} = assigns) do
    assigns
    |> Map.put(:head_title, dgettext("dashboard", "Authentication failed"))
    |> Map.put(:title, error_message)
    |> Map.put(
      :message,
      error_message
    )
    |> Map.put(:error_name, dgettext("dashboard", "401"))
    |> render_error_page()
  end

  def render("401.html", assigns) do
    assigns
    |> Map.put(:head_title, dgettext("dashboard", "Unauthorized"))
    |> Map.put(:title, dgettext("dashboard", "You are not authorized to view this page"))
    |> Map.put(
      :message,
      dgettext(
        "dashboard",
        "Please, make sure you are accessing the right resource and that you have the permissions to access it."
      )
    )
    |> Map.put(:error_name, dgettext("dashboard", "401"))
    |> render_error_page()
  end

  # Every 404 renders the redesigned marketing page once its page flag is on
  # (tuist.dev shares one host between the marketing site and the dashboard:
  # an unknown single-segment URL like /r is the dashboard's account route
  # missing, and it should read as the public not-found page). Other statuses
  # keep the dashboard error page.
  def render("404.html", %{conn: %Plug.Conn{} = conn} = assigns) do
    if Design.new?(conn, :not_found) do
      render_marketing_not_found(assigns)
    else
      render_dashboard_not_found(assigns)
    end
  end

  def render("404.html", assigns), do: render_dashboard_not_found(assigns)

  def render("429.html", assigns) do
    reason = assigns.reason

    reason_message =
      if is_nil(reason) do
        dgettext("dashboard", "Sorry, you made too many requests. Please try again later.")
      else
        reason.message
      end

    assigns
    |> Map.put(:head_title, dgettext("dashboard", "Too many requests"))
    |> Map.put(:title, dgettext("dashboard", "Too many requests."))
    |> Map.put(
      :message,
      reason_message
    )
    |> Map.put(:error_name, dgettext("dashboard", "429"))
    |> render_error_page()
  end

  def render("500.html", assigns) do
    assigns
    |> Map.put(:head_title, dgettext("dashboard", "Server error"))
    |> Map.put(:title, dgettext("dashboard", "Oops! Something went wrong"))
    |> Map.put(
      :message,
      dgettext(
        "dashboard",
        "Sorry, something went wrong on our side. Contact us at contact@tuist.dev and we'll look into it."
      )
    )
    |> Map.put(:error_name, dgettext("dashboard", "500"))
    |> render_error_page()
  end

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  defp render_dashboard_not_found(assigns) do
    reason = Map.get(assigns, :reason)

    reason_message =
      if is_nil(reason) do
        dgettext("dashboard", "Sorry, the page you are looking for doesn't exist or has been moved.")
      else
        reason.message
      end

    assigns
    |> Map.put(:head_title, dgettext("dashboard", "Not found"))
    |> Map.put(:title, dgettext("dashboard", "Oops, we couldn't find that page"))
    |> Map.put(
      :message,
      reason_message
    )
    |> Map.put(:error_name, dgettext("dashboard", "404"))
    |> render_error_page()
  end

  defp render_marketing_not_found(assigns) do
    conn = assigns.conn

    assigns =
      assigns
      |> Map.put(:new_design, true)
      |> Map.put(:current_path, conn.request_path)
      |> Map.put(:head_title, dgettext("marketing", "Page not found") <> " · Tuist")
      |> Map.put(
        :head_description,
        dgettext("marketing", "The page you are looking for doesn't exist or has been moved.")
      )
      |> Map.put(:head_image, Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg"))
      |> Map.put(:head_twitter_card, "summary_large_image")

    assigns
    |> Map.put(:inner_content, MarketingHTML.not_found_new(assigns))
    |> Layouts.root()
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
        <.live_title>{"#{@head_title || dgettext("dashboard", "Error")} · Tuist"}</.live_title>
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
          <img src={~p"/images/error_image_light.png"} data-theme="light" decoding="async" />
          <img src={~p"/images/error_image_dark.png"} data-theme="dark" decoding="async" />
          <div data-part="background">
            <div data-part="top-right-gradient"></div>
            <div data-part="bottom-left-gradient"></div>
          </div>
          <.button
            variant="primary"
            size="large"
            label={dgettext("dashboard", "Go to dashboard")}
            navigate={~p"/dashboard"}
          />
        </div>
      </body>
    </html>
    """
  end
end
