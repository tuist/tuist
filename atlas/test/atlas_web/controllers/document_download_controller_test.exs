defmodule AtlasWeb.DocumentDownloadControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Documents

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "contract.txt")
    File.write!(path, "Confidential contract body.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{"original_filename" => "contract.txt", "content_type" => "text/plain", "source" => "upload"},
        enqueue?: false
      )

    %{document: document}
  end

  test "redirects bare download links to a descriptive filename path", %{conn: conn, document: document} do
    {conn, _user} = log_in_user(conn, %{email: "exec-download@example.com", role: :executive})

    conn = get(conn, ~p"/documents/#{document.id}/download")

    assert redirected_to(conn) == ~p"/documents/#{document.id}/download/contract.txt"
  end

  test "streams the document for executives from a descriptive filename path", %{conn: conn, document: document} do
    {conn, _user} = log_in_user(conn, %{email: "exec-download-stream@example.com", role: :executive})

    conn = get(conn, ~p"/documents/#{document.id}/download/contract.txt")

    assert response(conn, 200) == "Confidential contract body."
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="contract.txt")]
  end

  test "serves the document when a descriptive filename segment is present", %{conn: conn, document: document} do
    {conn, _user} = log_in_user(conn, %{email: "exec-download-named@example.com", role: :executive})

    conn = get(conn, ~p"/documents/#{document.id}/download/contract.txt")

    assert response(conn, 200) == "Confidential contract body."
  end

  test "uses the document title in the inline filename", %{conn: conn, tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "download")
    File.write!(path, "Invoice body.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "title" => "SafetyCulture Pty Ltd",
          "original_filename" => "download",
          "content_type" => "application/pdf",
          "source" => "upload"
        },
        enqueue?: false
      )

    {conn, _user} = log_in_user(conn, %{email: "exec-download-title@example.com", role: :executive})

    conn = get(conn, ~p"/documents/#{document.id}/download/safetyculture-pty-ltd.pdf")

    assert response(conn, 200) == "Invoice body."
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="safetyculture-pty-ltd.pdf")]
  end

  test "forbids non-executive users", %{conn: conn, document: document} do
    {conn, _user} = log_in_user(conn, %{email: "employee-download@example.com", role: :employee})

    conn = get(conn, ~p"/documents/#{document.id}/download")

    assert response(conn, 403)
  end

  test "returns not found for unknown documents", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "exec-missing@example.com", role: :executive})

    conn = get(conn, ~p"/documents/#{Ecto.UUID.generate()}/download")

    assert response(conn, 404)
  end
end
