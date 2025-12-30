defmodule TuistWeb.ErrorJSONTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  test "renders 404" do
    assert TuistWeb.ErrorJSON.render("404.json", %{}) == %{message: "Not Found"}
  end

  test "renders 500" do
    assert TuistWeb.ErrorJSON.render("500.json", %{}) ==
             %{message: "Internal Server Error"}
  end
end
