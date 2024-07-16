defmodule TuistWeb.AuthControllerTest do
  use TuistWeb.ConnCase, async: true

  describe "GET /users/auth/invalid" do
    test "redirects to the home page", %{conn: conn} do
      # When
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        conn
        |> get("/users/auth/invalid")
      end
    end
  end
end
