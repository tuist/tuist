defmodule TuistWeb.RouterTest do
  use TuistWeb.ConnCase, async: true
  use Mimic

  test "responses in non-production environments instruct robots not to index or follow the page",
       %{conn: conn} do
    for env <- ["can", "stag", "test"] do
      Tuist.Environment |> stub(:env, fn -> env end)

      for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
        assert conn |> get(route) |> get_resp_header("x-robots-tags") == ["noindex, nofollow"]
      end
    end
  end
end
