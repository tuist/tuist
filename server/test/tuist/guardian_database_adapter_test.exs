defmodule Tuist.GuardianDatabaseAdapterTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Guardian.DB.Token

  test "storing the same token twice keeps the original record" do
    claims = %{
      "aud" => "tuist",
      "exp" => DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.to_unix(),
      "iss" => "tuist",
      "jti" => UUIDv7.generate(),
      "sub" => "1",
      "typ" => "refresh"
    }

    assert {:ok, {:resource, "refresh", ^claims, "first-hash"}} =
             Guardian.DB.after_encode_and_sign(:resource, "refresh", claims, "first-hash")

    assert {:ok, {:resource, "refresh", ^claims, "second-hash"}} =
             Guardian.DB.after_encode_and_sign(:resource, "refresh", claims, "second-hash")

    assert %Token{jwt: "first-hash"} = Token.find_by_claims(claims)
  end
end
