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
        # Extract the blog post path from the request
        path = conn.request_path

        # Convert path to template name
        # e.g., "/blog/2025/11/6/zero-to-many/iframe.html?id=lone_wolf"
        # becomes "blog_2025_11_6_zero_to_many_lone_wolf"
        template =
          path
          |> String.trim_leading("/")
          |> String.replace("/iframe.html", "")
          |> String.replace(~r/[-\/]/, "_")
          |> Kernel.<>("_#{id}")
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
