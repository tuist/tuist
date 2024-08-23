defmodule TuistWeb.PreviewHTML do
  use TuistWeb, :html

  def render("preview.html", assigns) do
    ~H"""
    <div class="page preview">
      <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Icon")} class="preview__logo" />
      <span class="loader"></span>
      <h4 class="preview__title"><%= gettext("Launching Tuist Preview") %></h4>
      <%= if not is_nil(@app_download_url) do %>
        <span class="text--small font--regular color--text-primary">
          <%= raw(
            gettext(
              "Don't have the Tuist app installed? <a style=\"display: inline;\" href=\"%{app_download_url}\">Click here to download it.</a>",
              app_download_url: @app_download_url
            )
          ) %>
        </span>
      <% end %>
    </div>

    <script>
      window.location.href = "<%= raw @deeplink_url %>";
    </script>
    """
  end
end
