defmodule TuistWeb.OpenGraphController do
  use TuistWeb, :controller

  alias Tuist.Projects.OpenGraph
  alias Tuist.Storage
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug

  def show(
        %{assigns: %{selected_account: account}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "hash" => hash} = params
      ) do
    with {:ok, payload} <- OpenGraph.payload_from_request(account_handle, project_handle, hash, params),
         {:ok, stream_source} <- OpenGraph.fetch_or_generate(payload, account) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_chunked(:ok)
      |> stream_response(stream_source, account)
    else
      {:error, :invalid_hash} ->
        send_resp(conn, 404, "")

      {:error, :invalid_payload} ->
        send_resp(conn, 400, "")

      {:error, _reason} ->
        send_resp(conn, 422, "")
    end
  end

  defp stream_response(conn, {:cached, object_key}, account) do
    object_key
    |> Storage.stream_object(account)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  defp stream_response(conn, {:generated, image_binary}, _account) do
    case chunk(conn, image_binary) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end
end
