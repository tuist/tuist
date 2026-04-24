defmodule ProcessorWeb.StatsControllerTest do
  use ExUnit.Case, async: false
  use Mimic

  import Phoenix.ConnTest

  @endpoint ProcessorWeb.Endpoint

  describe "GET /stats" do
    test "returns the current in-flight count" do
      expect(Processor.InFlight, :count, fn -> 3 end)

      conn = get(build_conn(), "/stats")

      assert conn.status == 200
      assert json_response(conn, 200) == %{"in_flight" => 3}
    end
  end
end
