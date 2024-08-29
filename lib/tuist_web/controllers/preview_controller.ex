defmodule TuistWeb.PreviewController do
  use TuistWeb, :controller

  def preview(
        conn,
        %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => preview_id
        } = _params
      ) do
    conn =
      conn
      |> assign(
        :page_title,
        gettext("Redirecting...")
      )
      |> assign(
        :deeplink_url,
        "tuist:open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{preview_id}&full_handle=#{account_handle}/#{project_handle}"
      )

    render(conn, :preview, layout: false)
  end
end
