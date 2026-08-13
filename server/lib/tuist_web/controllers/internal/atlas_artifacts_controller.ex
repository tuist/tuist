defmodule TuistWeb.Internal.AtlasArtifactsController do
  @moduledoc """
  Internal Atlas access to stored artifacts.

  Returns a short-lived presigned download URL for the artifact behind a record
  (see `Tuist.Atlas.Artifacts`) rather than the bytes themselves, so a large
  `.xcresult` bundle never travels through this server. The caller is
  authenticated by `TuistWeb.Plugs.InternalAtlasAuthPlug` (Atlas workload
  identity), so this endpoint is reachable only by the Atlas service account.
  """

  use TuistWeb, :controller

  alias Tuist.Atlas.Artifacts

  @doc """
  Presign a download for `:kind`/`:id`. `expires_in` (seconds, query param)
  shortens the default lifetime; it is clamped server-side.
  """
  def show(conn, %{"kind" => kind, "id" => id} = params) do
    case Artifacts.presign(kind, id, expires_in: expires_in(params)) do
      {:ok, artifact} ->
        json(conn, artifact)

      {:error, :unknown_kind} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "unknown_kind", supported_kinds: Artifacts.kinds()})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "record_not_found"})

      {:error, :object_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "artifact_not_stored"})

      {:error, :storage_unavailable} ->
        conn |> put_status(:bad_gateway) |> json(%{error: "storage_unavailable"})
    end
  end

  defp expires_in(%{"expires_in" => expires_in}) when is_integer(expires_in), do: expires_in

  defp expires_in(%{"expires_in" => expires_in}) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {seconds, ""} -> seconds
      _ -> nil
    end
  end

  defp expires_in(_params), do: nil
end
