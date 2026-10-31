defmodule TuistWeb.Helpers.PreviewInstallURLs do
  @moduledoc """
  URLs that install a preview on a device, each carrying a signed install token.
  """
  use TuistWeb, :verified_routes

  alias Tuist.AppBuilds

  def manifest_url(account_handle, project_handle, preview) do
    url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/manifest.plist?#{token_params(preview)}")
  end

  def apk_url(account_handle, project_handle, preview) do
    url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/app.apk?#{token_params(preview)}")
  end

  def itms_services_url(account_handle, project_handle, preview) do
    "itms-services:" <> itms_services_path(account_handle, project_handle, preview)
  end

  def itms_services_path(account_handle, project_handle, preview) do
    "//?action=download-manifest&url=" <>
      URI.encode_www_form(manifest_url(account_handle, project_handle, preview))
  end

  defp token_params(preview), do: [token: AppBuilds.preview_install_token(preview)]
end
