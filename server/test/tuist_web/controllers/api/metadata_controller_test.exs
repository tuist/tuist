defmodule TuistWeb.API.MetadataControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  test "unauthenticated discovery defaults to the legacy allowance", %{conn: conn} do
    stub(Tuist.Environment, :expanded_build_metadata_enabled?, fn -> false end)
    conn = get(conn, "/api/metadata/limits")
    assert json_response(conn, 200) == %{"max_values" => 20}
    assert get_resp_header(conn, "x-tuist-custom-metadata-max-values") == ["20"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "advertisement is explicitly enabled after the receiver rollout", %{conn: conn} do
    stub(Tuist.Environment, :expanded_build_metadata_enabled?, fn -> true end)
    conn = get(conn, "/api/metadata/limits")
    assert json_response(conn, 200) == %{"max_values" => 64}
    assert get_resp_header(conn, "x-tuist-custom-metadata-max-values") == ["64"]
  end
end
