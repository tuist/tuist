defmodule AtlasWeb.ContractTemplateDownloadControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Contracts

  test "streams the .docx for a valid signed token", %{conn: conn} do
    {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
    token = Contracts.sign_download_token(template)

    conn = get(conn, ~p"/contracts/templates/2026-02/msa.docx?token=#{token}")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "wordprocessingml"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="msa.docx")
           ]

    body = response(conn, 200)
    assert byte_size(body) == template.byte_size
  end

  test "streams the .docx from a token issued 90 minutes ago", %{conn: conn} do
    signed_at = System.system_time(:second) - 90 * 60
    token = sign_token(signed_at)

    conn = get(conn, ~p"/contracts/templates/2026-02/msa.docx?token=#{token}")

    assert conn.status == 200
  end

  test "rejects a missing token with 404", %{conn: conn} do
    conn = get(conn, ~p"/contracts/templates/2026-02/msa.docx")

    assert response(conn, 404) == "Not Found"
  end

  test "explains how to recover from an expired token", %{conn: conn} do
    signed_at = System.system_time(:second) - Contracts.download_max_age() - 1
    token = sign_token(signed_at)

    conn = get(conn, ~p"/contracts/templates/2026-02/msa.docx?token=#{token}")

    assert response(conn, 410) ==
             "This download link has expired. Ask the connected agent to call get_contract_template again."
  end

  test "rejects a tampered token with 404", %{conn: conn} do
    {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
    token = Contracts.sign_download_token(template)
    tampered = String.replace(token, ~r/^./, "x")

    conn = get(conn, ~p"/contracts/templates/2026-02/msa.docx?token=#{tampered}")

    assert response(conn, 404) == "Not Found"
  end

  test "rejects when the path filename does not match the token payload", %{conn: conn} do
    {:ok, msa} = Contracts.fetch_template("2026-02", "msa.docx")
    msa_token = Contracts.sign_download_token(msa)

    conn = get(conn, ~p"/contracts/templates/2026-02/annex-2-dpa.docx?token=#{msa_token}")

    assert response(conn, 404) == "Not Found"
  end

  test "rejects when the path template_set does not match the token payload", %{conn: conn} do
    {:ok, msa} = Contracts.fetch_template("2026-02", "msa.docx")
    msa_token = Contracts.sign_download_token(msa)

    conn = get(conn, ~p"/contracts/templates/9999-99/msa.docx?token=#{msa_token}")

    assert response(conn, 404) == "Not Found"
  end

  defp sign_token(signed_at) do
    Phoenix.Token.sign(
      AtlasWeb.Endpoint,
      "contract-template-download",
      %{"template_set" => "2026-02", "filename" => "msa.docx"},
      signed_at: signed_at
    )
  end
end
