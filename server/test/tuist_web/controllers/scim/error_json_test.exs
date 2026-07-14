defmodule TuistWeb.SCIM.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias TuistWeb.SCIM.ErrorJSON

  test "renders SCIM error resources" do
    assert "500.scim+json" |> ErrorJSON.render(%{status: 500}) |> JSON.decode!() == %{
             "schemas" => ["urn:ietf:params:scim:api:messages:2.0:Error"],
             "status" => "500",
             "detail" => "Internal Server Error"
           }
  end

  test "renders malformed JSON as invalid syntax" do
    assert "400.scim+json"
           |> ErrorJSON.render(%{
             status: 400,
             reason: %Plug.Parsers.ParseError{exception: %JSON.DecodeError{}}
           })
           |> JSON.decode!() == %{
             "schemas" => ["urn:ietf:params:scim:api:messages:2.0:Error"],
             "status" => "400",
             "detail" => "Invalid JSON payload",
             "scimType" => "invalidSyntax"
           }
  end
end
