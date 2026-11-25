defmodule AtlasWeb.DocumentSignedDownloadControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Documents
  alias Atlas.Documents.Storage
  alias AtlasWeb.DocumentLinks

  setup do
    {:ok, document} =
      Documents.create_from_binary(
        "PK redline #{System.unique_integer([:positive])}",
        %{
          "original_filename" => "annex.docx",
          "content_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "source" => "email"
        },
        enqueue?: false
      )

    %{document: document}
  end

  test "serves the file without a session to a signed link for a user with document access", %{document: document} do
    user = insert_scoped_user!([:"documents:read"])
    {:ok, %{body: body}} = Storage.get_object(document.storage_key)

    conn = get(build_conn(), DocumentLinks.signed_download_url(document, user))

    assert response(conn, 200) == body
    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="annex.docx")]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "refuses links whose user lost document access", %{document: document} do
    user = insert_scoped_user!([:"tasks:read"])

    conn = get(build_conn(), DocumentLinks.signed_download_url(document, user))

    assert response(conn, 403)
  end

  test "refuses a token issued for another document, a missing token and an expired one", %{document: document} do
    user = insert_scoped_user!([:"documents:read"])

    {:ok, other} =
      Documents.create_from_binary("other #{System.unique_integer([:positive])}", %{"original_filename" => "other.txt"},
        enqueue?: false
      )

    [_, query] = other |> DocumentLinks.signed_download_url(user) |> String.split("?")

    assert build_conn() |> get("/documents/#{document.id}/file/annex.docx?#{query}") |> response(404)
    assert build_conn() |> get("/documents/#{document.id}/file/annex.docx") |> response(404)

    expired =
      Phoenix.Token.sign(
        AtlasWeb.Endpoint,
        "document-signed-download",
        %{"document_id" => document.id, "user_id" => user.id},
        signed_at: System.system_time(:second) - DocumentLinks.signed_max_age() - 1
      )

    assert build_conn()
           |> get("/documents/#{document.id}/file/annex.docx?#{URI.encode_query(%{token: expired})}")
           |> response(410)
  end

  defp insert_scoped_user!(scopes) do
    {_conn, user} = log_in_user(build_conn(), %{scopes: scopes})
    user
  end
end
