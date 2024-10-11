defmodule TuistWeb.PreviewHTML do
  use TuistWeb, :html

  def render("preview.html", assigns) do
    ~H"""
    <div class="page preview desktop_preview">
      <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Icon")} class="preview__logo" />
      <span class="loader"></span>
      <h4 class="preview__title"><%= gettext("Launching Tuist Preview") %></h4>
      <span class="text--small font--regular color--text-primary">
        <div>
          <%= raw(
            gettext(
              "Don't have the Tuist app installed? <a style=\"display: inline;\" href=\"%{app_download_url}\">Click here to download it.</a>",
              app_download_url: ~p"/download"
            )
          ) %>
        </div>
      </span>
    </div>
    <%= if @preview.type == :ipa do %>
      <div class="page preview mobile_preview">
        <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Icon")} class="preview__logo" />
        <h4 class="preview__title">
          <%= gettext("%{display_name} Preview, %{version}",
            display_name: @preview.display_name,
            version: @preview.version
          ) %>
        </h4>
        <.button>
          <a href={@preview_download_url} class="color--text-primary">
            <%= gettext("Install") %>
          </a>
        </.button>
      </div>
      <script>
        function iOS() {
          return [
            'iPad Simulator',
            'iPhone Simulator',
            'iPod Simulator',
            'iPad',
            'iPhone',
            'iPod'
          ].includes(navigator.platform)
        }

        function hideElementsByClass(className) {
          var elements = document.querySelectorAll('.' + className);
          elements.forEach(function(element) {
            element.style.display = 'none';
          });
        }

        if (iOS() && document.querySelectorAll('.desktop_preview') !== null) {
          hideElementsByClass('desktop_preview');
        } else {
          hideElementsByClass('mobile_preview');
          window.location.href = "<%= raw @deeplink_url %>";
        }
      </script>
    <% else %>
      <script>
        window.location.href = "<%= raw @deeplink_url %>";
      </script>
    <% end %>
    """
  end
end
