defmodule TuistWeb.SnapshotImagesController do
  @moduledoc """
  Serves a snapshot image to the dashboard: the build's own image (`head`),
  the baseline's (`baseline`), the rendered diff (`diff`) or the library's
  small copy of the build's image (`thumbnail`).

  The bytes are streamed through the server rather than redirected to a
  presigned URL so the review page works wherever the dashboard does. Image
  content never changes under a URL (blobs are content-addressed and diffs
  are written once per comparison), so browsers may cache it.
  """
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Projects
  alias Tuist.Snapshots
  alias TuistWeb.Authentication

  @variants %{"head" => :head, "baseline" => :baseline, "diff" => :diff, "thumbnail" => :thumbnail}

  def show(conn, %{
        "account_handle" => account_handle,
        "project_handle" => project_handle,
        "build_id" => build_id,
        "image_id" => image_id,
        "variant" => variant
      }) do
    user = Authentication.current_user(conn)

    with {:ok, variant} <- Map.fetch(@variants, variant),
         {:ok, project} <- Projects.get_project_by_slug("#{account_handle}/#{project_handle}", preload: [:account]),
         true <- FeatureFlags.snapshots_enabled?(project.account),
         :ok <- Authorization.authorize(:test_read, user, project),
         {:ok, build} <- Snapshots.get_build(project, build_id),
         {:ok, image} <- Snapshots.get_image(build, image_id),
         {:ok, binary} <- Snapshots.image_binary(project, image, variant) do
      conn
      |> put_resp_content_type(content_type(binary), nil)
      |> put_resp_header("cache-control", "private, max-age=86400, immutable")
      |> send_resp(200, binary)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> assign(:reason, nil)
        |> put_view(TuistWeb.ErrorHTML)
        |> render("404.html")
        |> halt()
    end
  end

  # Thumbnails are WebP; every other variant, and a thumbnail's fallback to
  # the full image, is PNG.
  defp content_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  defp content_type(_binary), do: "image/png"
end
