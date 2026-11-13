defmodule TuistWeb.Marketing.BazelShowcaseControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Marketing.BazelShowcase

  describe "GET /blog/bazel/timeline.json" do
    test "serves the showcase timeline's steps with a public cache header", %{conn: conn} do
      stub(BazelShowcase, :timeline_steps, fn "invocation-id" -> {:ok, %{events: [], duration: 1}} end)

      conn = get(conn, "/blog/bazel/timeline.json?invocation_id=invocation-id")

      assert json_response(conn, 200) == %{"events" => [], "duration" => 1}
      assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    end

    test "GET and HEAD return uncacheable retryable failures when loading is unavailable", %{conn: conn} do
      stub(BazelShowcase, :timeline_steps, fn "invocation-id" -> {:error, :unavailable} end)

      for method <- [:get, :head] do
        response = dispatch(conn, @endpoint, method, "/blog/bazel/timeline.json?invocation_id=invocation-id")
        assert response(response, 503) == ""
        assert get_resp_header(response, "cache-control") == ["no-store"]
        assert get_resp_header(response, "retry-after") == ["1"]
      end
    end

    test "returns not found for any other invocation", %{conn: conn} do
      stub(BazelShowcase, :timeline_steps, fn _invocation_id -> {:error, :not_found} end)

      assert_error_sent :not_found, fn ->
        get(conn, "/blog/bazel/timeline.json?invocation_id=other")
      end
    end

    test "returns not found without an invocation", %{conn: conn} do
      assert_error_sent :not_found, fn ->
        get(conn, "/blog/bazel/timeline.json")
      end
    end
  end
end
