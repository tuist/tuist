defmodule TuistCommon.HTTP.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  alias TuistCommon.HTTP.Telemetry

  test "classifies Bandit request timeouts" do
    conn =
      :post
      |> conn("/webhooks/github", "")
      |> Map.put(:private, %{phoenix_route: "/webhooks/github"})

    metadata = %{conn: conn, error: "Body read timeout"}

    assert Telemetry.bandit_request_timeout?(metadata)

    assert Telemetry.bandit_timeout_tag_values(metadata) == %{
             method: "POST",
             route: "/webhooks/github"
           }
  end

  test "classifies Bandit request failures" do
    conn =
      :get
      |> conn("/api/projects", "")
      |> Map.put(:status, 503)
      |> Map.put(:private, %{phoenix_route: "/api/projects"})

    metadata = %{conn: conn}

    assert Telemetry.bandit_request_failure_reason(metadata) == "server_error"

    assert Telemetry.bandit_failure_tag_values(metadata) == %{
             method: "GET",
             route: "/api/projects",
             reason: "server_error"
           }
  end

  test "classifies Bandit exceptions" do
    metadata = %{conn: conn(:get, "/api/projects")}

    assert Telemetry.bandit_exception_tag_values(metadata) == %{
             method: "GET",
             route: "/api/projects",
             reason: "exception"
           }
  end

  test "classifies Thousand Island connection drops" do
    assert Telemetry.thousand_island_connection_drop_reason(%{error: :timeout}) == "timeout"
    assert Telemetry.thousand_island_connection_drop_reason(%{error: :closed}) == "closed"
    assert Telemetry.thousand_island_connection_drop_reason(%{}) == nil
  end

  test "classifies Thousand Island connection errors" do
    assert Telemetry.thousand_island_connection_error_metadata(:recv_error) == %{
             event: "recv_error"
           }

    assert Telemetry.thousand_island_connection_error_metadata(:send_error) == %{
             event: "send_error"
           }
  end

  test "logs request timeouts and connection drops from native events" do
    log =
      capture_log(fn ->
        Telemetry.handle_event(
          [:bandit, :request, :stop],
          %{
            duration: System.convert_time_unit(50, :millisecond, :native),
            req_body_start_time: System.convert_time_unit(10, :millisecond, :native),
            req_body_end_time: System.convert_time_unit(40, :millisecond, :native)
          },
          %{conn: conn(:post, "/upload"), error: "Body read timeout"},
          nil
        )

        Telemetry.handle_event(
          [:thousand_island, :connection, :stop],
          %{},
          %{error: :closed},
          nil
        )
      end)

    assert log =~ "Bandit request body timeout"
    assert log =~ "Thousand Island connection dropped"
  end
end
