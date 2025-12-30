defmodule Tuist.IncidentsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.KeyValueStore

  setup do
    stub(KeyValueStore, :get_or_update, fn _, _, func -> func.() end)
    :ok
  end

  describe "any_ongoing_incident?/0" do
    test "retries if the request fails" do
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
        fn "https://status.tuist.dev/proxy/status.tuist.dev", [finch: Tuist.Finch] ->
          {:error, %Req.TransportError{reason: :timeout}}
        end
      )

      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev", [finch: Tuist.Finch] ->
          {:ok, %Req.Response{status: 200, body: status}}
        end
      )

      # When
      first_result = Tuist.Incidents.any_ongoing_incident?()
      second_result = Tuist.Incidents.any_ongoing_incident?()

      # Then
      assert first_result == true
      assert second_result == true
    end

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

      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev", [finch: Tuist.Finch] ->
          {:ok, %Req.Response{status: 200, body: status}}
        end
      )

      # When
      first_result = Tuist.Incidents.any_ongoing_incident?()
      second_result = Tuist.Incidents.any_ongoing_incident?()

      # Then
      assert first_result == true
      assert second_result == true
    end

    test "returns false when request fails with error response" do
      # Given
      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev", [finch: Tuist.Finch] ->
          {:ok, %Req.Response{status: 500, body: "error code: 500"}}
        end
      )

      # When
      result = Tuist.Incidents.any_ongoing_incident?()

      # Then
      assert result == false
    end

    test "returns false when request fails with error tuple" do
      # Given
      stub(
        Req,
        :get,
        fn "https://status.tuist.dev/proxy/status.tuist.dev", [finch: Tuist.Finch] ->
          {:error, %Req.TransportError{reason: :timeout}}
        end
      )

      # When
      result = Tuist.Incidents.any_ongoing_incident?()

      # Then
      assert result == false
    end
  end
end
