defmodule Tuist.ClickHouse.EndpointsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouse.Endpoints
  alias Tuist.ClickHouseRepo

  describe "database/1" do
    test "asks the connection which database it is on" do
      # The read-path repositories are configured with a URL and nothing else,
      # so their configuration carries no database to read.
      stub(ClickHouseRepo, :config, fn -> [url: "http://user:password@clickhouse:8123/tuist"] end)

      expect(ClickHouseRepo, :query!, fn "SELECT currentDatabase()", [], [log: false] ->
        %{rows: [["tuist"]]}
      end)

      assert Endpoints.database(ClickHouseRepo) == "tuist"
    end

    test "reads the configured database when there is one, without asking" do
      stub(ClickHouseRepo, :config, fn -> [database: "tuist_test", url: "http://clickhouse:8123"] end)
      reject(&ClickHouseRepo.query!/3)

      assert Endpoints.database(ClickHouseRepo) == "tuist_test"
    end
  end
end
