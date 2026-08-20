defmodule Tuist.ClickHouseCapabilitiesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouseCapabilities
  alias Tuist.Environment

  defmodule KeeperRepo do
    @moduledoc false
    def query(_statement), do: {:ok, %{rows: [[1]]}}
  end

  defmodule KeeperlessRepo do
    @moduledoc false
    def query(_statement), do: {:ok, %{rows: [[0]]}}
  end

  defmodule UnreachableRepo do
    @moduledoc false
    def query(_statement), do: {:error, %Ch.Error{code: 210, message: "connection refused"}}
  end

  defmodule ModernRepo do
    @moduledoc false
    def query(_statement), do: {:ok, %{rows: [["26.1.2.11"]]}}
  end

  defmodule LegacyRepo do
    @moduledoc false
    def query(_statement), do: {:ok, %{rows: [["25.7.7.68"]]}}
  end

  defmodule RebuiltRepo do
    @moduledoc false
    def query(_statement), do: {:ok, %{rows: [["25.3.6.10034.altinitystable"]]}}
  end

  describe "serial_ids_supported?/1" do
    test "is true when the server has coordination configured" do
      assert ClickHouseCapabilities.serial_ids_supported?(KeeperRepo)
    end

    test "is false on a single-node server with no Keeper, like the one every preview runs" do
      refute ClickHouseCapabilities.serial_ids_supported?(KeeperlessRepo)
    end

    test "raises rather than guessing when the server cannot answer" do
      assert_raise RuntimeError, ~r/Could not determine/, fn ->
        ClickHouseCapabilities.serial_ids_supported?(UnreachableRepo)
      end
    end
  end

  describe "use_serial_ids?/1" do
    test "opts out in test even when the server supports serial ids" do
      assert Environment.test?()

      refute ClickHouseCapabilities.use_serial_ids?(KeeperRepo)
    end

    test "opts out in dev even when the server supports serial ids" do
      stub(Environment, :test?, fn -> false end)
      stub(Environment, :dev?, fn -> true end)

      refute ClickHouseCapabilities.use_serial_ids?(KeeperRepo)
    end

    test "follows the server outside dev and test" do
      stub(Environment, :test?, fn -> false end)
      stub(Environment, :dev?, fn -> false end)

      assert ClickHouseCapabilities.use_serial_ids?(KeeperRepo)
      refute ClickHouseCapabilities.use_serial_ids?(KeeperlessRepo)
    end
  end

  describe "server_version/1" do
    test "reads the running server's version" do
      assert ClickHouseCapabilities.server_version(ModernRepo) == [26, 1, 2, 11]
    end

    test "stops at the first component a rebuilt distribution appends" do
      assert ClickHouseCapabilities.server_version(RebuiltRepo) == [25, 3, 6, 10_034]
    end

    test "raises rather than guessing when the server cannot answer" do
      assert_raise RuntimeError, ~r/Could not determine/, fn ->
        ClickHouseCapabilities.server_version(UnreachableRepo)
      end
    end
  end

  describe "insert_select_deduplication_settings/1" do
    test "asks for deduplication when the server can enforce it" do
      assert ClickHouseCapabilities.insert_select_deduplication_settings(ModernRepo) ==
               [deduplicate_insert_select: "force_enable"]
    end

    test "is empty on a server that predates the setting, which deduplicates anyway" do
      assert ClickHouseCapabilities.insert_select_deduplication_settings(LegacyRepo) == []
      assert ClickHouseCapabilities.insert_select_deduplication_settings(RebuiltRepo) == []
    end
  end
end
