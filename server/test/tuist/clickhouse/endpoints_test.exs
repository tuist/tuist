defmodule Tuist.ClickHouse.EndpointsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouse.Endpoints

  @endpoint_descriptor %{repo: Tuist.IngestRepo, database: "in_cluster"}

  describe "await_ready/2" do
    test "returns once the endpoint answers" do
      stub(Tuist.IngestRepo, :query, fn _sql, _params, _opts -> {:ok, %{rows: [[1]]}} end)

      assert Endpoints.await_ready(@endpoint_descriptor) == :ok
    end

    test "keeps asking while the endpoint is still coming back" do
      # The window this exists for: the destination is rolled by the same
      # release, so the first queries land while its pod is restarting and the
      # pool refuses them within seconds.
      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      stub(Tuist.IngestRepo, :query, fn _sql, _params, _opts ->
        case Agent.get_and_update(attempts, &{&1 + 1, &1 + 1}) do
          attempt when attempt < 3 -> {:error, %DBConnection.ConnectionError{message: "connection not available"}}
          _ -> {:ok, %{rows: [[1]]}}
        end
      end)

      assert Endpoints.await_ready(@endpoint_descriptor, ready_interval: 1, ready_timeout: 1_000) == :ok
      assert Agent.get(attempts, & &1) == 3
    end

    test "gives up with the refusal it last saw" do
      stub(Tuist.IngestRepo, :query, fn _sql, _params, _opts ->
        {:error, %DBConnection.ConnectionError{message: "connection not available"}}
      end)

      assert {:error, {:not_ready, "in_cluster", %DBConnection.ConnectionError{}}} =
               Endpoints.await_ready(@endpoint_descriptor, ready_interval: 1, ready_timeout: 0)
    end
  end
end
