defmodule SymptomsWeb.HealthControllerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint SymptomsWeb.Endpoint

  test "GET /healthz answers without a database" do
    conn = get(build_conn(), "/healthz")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
