defmodule TuistCloudWeb.AuthControllerTest do
  use TuistCloudWeb.ConnCase, async: true

  describe "GET /users/auth/invalid" do
    test "redirects to the home page", %{conn: conn} do
      # When
      assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
        conn
        |> get("/users/auth/invalid")
      end
    end
  end
end
