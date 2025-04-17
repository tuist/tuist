defmodule Tuist.IncidentsTest do
  use ExUnit.Case, async: false
  use Mimic

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  describe "any_ongoing_incident?/0" do
    test "retries if the request fails" do
      # Given
      cache = String.to_atom(UUIDv7.generate())
      {:ok, _} = Cachex.start_link(name: cache)

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

      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev" ->
          {:error, %Req.TransportError{reason: :timeout}}
        end
      )

      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev" ->
          {:ok, %Req.Response{status: 200, body: status}}
        end
      )

      # When
      first_result = Tuist.Incidents.any_ongoing_incident?(cache: cache)
      cached_result = Tuist.Incidents.any_ongoing_incident?(cache: cache)

      # Then
      assert first_result == true
      assert cached_result == true
    end

    test "returns true if there are ongoing incidents" do
      # Given
      cache = String.to_atom(UUIDv7.generate())
      {:ok, _} = Cachex.start_link(name: cache)

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

      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev" ->
          {:ok, %Req.Response{status: 200, body: status}}
        end
      )

      # When
      first_result = Tuist.Incidents.any_ongoing_incident?(cache: cache)
      cached_result = Tuist.Incidents.any_ongoing_incident?(cache: cache)

      # Then
      assert first_result == true
      assert cached_result == true
    end
  end
end
