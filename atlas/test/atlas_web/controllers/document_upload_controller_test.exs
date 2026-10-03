defmodule AtlasWeb.DocumentUploadControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Documents.Storage.Local, as: LocalStorage

  # This controller exists only for the `Local` storage backend used in dev
  # and test; in production S3-compatible presigned URLs bypass Atlas entirely.
  describe "PUT /api/documents/uploads/local/:token" do
    test "accepts a body signed by presigned_put_url and enforces the bound Content-Type", %{conn: conn} do
      key = "documents/pending/#{Ecto.UUID.generate()}.pdf"
      {:ok, url} = LocalStorage.presigned_put_url(key, expires_in: 3600, content_type: "application/pdf")

      # Reuse the same signed token the client would have received.
      token = url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last()

      good =
        conn
        |> put_req_header("content-type", "application/pdf")
        |> put(~p"/api/documents/uploads/local/#{token}", "the bytes")

      assert good.status == 200

      bad =
        build_conn()
        |> put_req_header("content-type", "text/plain")
        |> put(~p"/api/documents/uploads/local/#{token}", "the bytes")

      assert bad.status == 400
    end

    test "rejects a tampered or unknown token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/pdf")
        |> put(~p"/api/documents/uploads/local/#{"not-a-real-token"}", "the bytes")

      assert conn.status == 403
    end
  end
end
