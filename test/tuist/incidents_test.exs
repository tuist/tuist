defmodule Tuist.IncidentsTest do
  use ExUnit.Case
  use Mimic

  describe "any_ongoing_incident?/0" do
    test "returns true if there are ongoing incidents" do
      # Given
      ongoing_incidents = [
        %{
          "id" => "1",
          "status" => "ongoing"
        }
      ]

      status = %{
        "summary" => %{
          "ongoing_incidents" => ongoing_incidents
        }
      }

      Req
      |> stub(
        :get,
        fn "https://status.tuist.io/proxy/status.tuist.io" ->
          {:ok, %Req.Response{status: 200, body: Jason.encode!(status)}}
        end
      )

      # When
      got = Tuist.Incidents.any_ongoing_incident?()

      # Then
      assert got == true
    end
  end
end
