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
        empty_page(conn, 200)

      id ->
        case iframe_template(params, id) do
          {:ok, template} ->
            conn
            |> put_resp_content_type("text/html")
            |> put_layout(false)
            |> put_view(MarketingHTML)
            |> assign(:plain_disabled?, true)
            |> assign(:analytics_disabled?, true)
            |> render(template)

          :error ->
            empty_page(conn, 404)
        end
    end
  end

  defp iframe_template(params, id) do
    template_name =
      String.replace("blog_#{params["year"]}_#{params["month"]}_#{params["day"]}_#{params["slug"]}_#{id}", "-", "_")

    :functions
    |> MarketingHTML.__info__()
    |> Enum.find_value(:error, fn
      {name, 1} ->
        if Atom.to_string(name) == template_name, do: {:ok, name}

      _ ->
        nil
    end)
  end

  defp empty_page(conn, status) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
  end
end
