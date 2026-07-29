defmodule TuistWeb.SCIM.ErrorRenderingTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint TuistWeb.Endpoint

  test "returns a SCIM error resource for unmatched SCIM routes" do
    conn = get(build_conn(), "/scim/v2/Unknown")

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/scim+json"

    assert json_response(conn, 404) == %{
             "schemas" => ["urn:ietf:params:scim:api:messages:2.0:Error"],
             "status" => "404",
             "detail" => "SCIM endpoint not found"
           }
  end

  test "returns a SCIM error resource for malformed JSON" do
    conn =
      build_conn()
      |> put_req_header("accept", "application/scim+json")
      |> put_req_header("content-type", "application/scim+json")

    {400, headers, body} =
      assert_error_sent 400, fn ->
        post(conn, "/scim/v2/Users", "{")
      end

    assert {"content-type", content_type} = List.keyfind(headers, "content-type", 0)
    assert content_type =~ "application/scim+json"

    assert JSON.decode!(body) == %{
             "schemas" => ["urn:ietf:params:scim:api:messages:2.0:Error"],
             "status" => "400",
             "detail" => "Invalid JSON payload",
             "scimType" => "invalidSyntax"
           }
  end
end
