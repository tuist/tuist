defmodule TuistWeb.Marketing.MarketingBlogIframeController do
  @moduledoc """
  Controller for serving blog post iframe visualizations as static HTML.
  These are D3.js animations that don't need LiveView overhead.
  """
  use TuistWeb, :controller

  alias TuistWeb.Marketing.MarketingHTML

  def show(conn, params) do
    case Map.get(params, "id") do
      nil ->
        # No id parameter - return empty page
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, "")

      id ->
        # Build template name from route params so the locale prefix in the
        # request path doesn't leak into the template lookup.
        # e.g., year=2025, month=11, day=6, slug=zero-to-many, id=lone_wolf
        # becomes :blog_2025_11_6_zero_to_many_lone_wolf
        template =
          "blog_#{params["year"]}_#{params["month"]}_#{params["day"]}_#{params["slug"]}_#{id}"
          |> String.replace("-", "_")
          |> String.to_atom()

        # Render the template directly without LiveView
        conn
        |> put_resp_content_type("text/html")
        |> put_layout(false)
        |> put_view(MarketingHTML)
        |> assign(:plain_disabled?, true)
        |> assign(:analytics_disabled?, true)
        |> render(template)
    end
  end
end
