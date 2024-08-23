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
    latest_app_release = Tuist.GitHub.Releases.get_latest_app_release()

    app_download_url =
      if is_nil(latest_app_release) do
        nil
      else
        latest_app_release.assets
        |> Enum.find(&String.ends_with?(&1.browser_download_url, "dmg"))
        |> Map.get(:browser_download_url)
      end

    conn =
      conn
      |> assign(
        :app_download_url,
        app_download_url
      )
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
