defmodule TuistWeb.PreviewController do
  alias TuistWeb.Authorization
  alias Tuist.Storage
  alias Tuist.Previews
  use TuistWeb, :controller

  plug :assign_current_preview
  plug Authorization, [:current_user, :read, :preview] when action in [:preview]

  def download_qr_code_svg(
        conn,
        %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => preview_id
        } = _params
      ) do
    {:ok, qr_code_image} =
      url(~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}/qr-code.svg")
      |> QRCode.create(:low)
      |> QRCode.render()

    conn
    |> put_resp_content_type("image/svg+xml")
    |> send_resp(200, qr_code_image)
  end

  def download_archive(
        conn,
        %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => preview_id
        } = _params
      ) do
    object =
      Storage.get_object_as_string(
        Previews.get_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview_id
        })
      )

    conn
    |> send_resp(200, object)
  end

  def manifest(
        %{assigns: %{current_preview: preview}} = conn,
        %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => preview_id
        } = _params
      ) do
    plist_content = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
        <dict>
            <key>items</key>
            <array>
                <dict>
                    <key>assets</key>
                    <array>
                        <dict>
                            <key>kind</key>
                            <string>software-package</string>
                            <key>url</key>
                            <string>#{url(~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}/app.ipa")}</string>
                          </dict>
                    </array>
                    <key>metadata</key>
                    <dict>
                        <key>bundle-identifier</key>
                        <string>#{preview.bundle_identifier}</string>
                        <key>bundle-version</key>
                        <string>#{preview.version}</string>
                        <key>kind</key>
                        <string>software</string>
                        <key>title</key>
                        <string>App</string>
                    </dict>

                </dict>
            </array>
        </dict>
    </plist>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, plist_content)
  end

  def preview(
        %{assigns: %{current_preview: preview}} = conn,
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
        :preview,
        preview
      )
      |> assign(
        :preview_download_url,
        "itms-services://?action=download-manifest&url=#{url(~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}/manifest.plist")}"
      )
      |> assign(
        :deeplink_url,
        "tuist:open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{preview_id}&full_handle=#{account_handle}/#{project_handle}"
      )

    render(conn, :preview, layout: false)
  end

  defp assign_current_preview(%{params: %{"id" => preview_id}} = conn, _opts) do
    preview = Previews.get_preview_by_id(preview_id)

    if is_nil(preview) do
      raise TuistWeb.Errors.NotFoundError,
            "Preview not found."
    end

    conn
    |> assign(:current_preview, preview)
  end
end
