defmodule TuistWeb.DownloadController do
  use TuistWeb, :controller

  def download(conn, _params) do
    latest_app_release = Tuist.GitHub.Releases.get_latest_app_release()

    if is_nil(latest_app_release) do
      raise TuistWeb.Errors.NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    else
      app_download_url =
        latest_app_release.assets
        |> Enum.find(&String.ends_with?(&1.browser_download_url, "dmg"))
        |> Map.get(:browser_download_url)

      conn |> redirect(external: app_download_url) |> halt()
    end
  end
end
