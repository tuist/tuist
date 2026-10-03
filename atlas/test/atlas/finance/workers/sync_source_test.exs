defmodule Atlas.Finance.Workers.SyncSourceTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Workers.SyncSource

  setup :verify_on_exit!

  test "delegates to the finance sync function" do
    parent = self()

    expect(Finance, :sync_source, fn source_key ->
      send(parent, {:synced_source_key, source_key})
      {:ok, %{accounts_seen: 1}}
    end)

    assert :ok = SyncSource.perform(%Oban.Job{args: %{"source_key" => "qonto-main"}})

    assert_receive {:synced_source_key, "qonto-main"}
  end

  test "cancels when the source is not configured" do
    expect(Finance, :sync_source, fn "missing" -> {:error, :source_not_configured} end)

    assert {:cancel, :source_not_configured} = SyncSource.perform(%Oban.Job{args: %{"source_key" => "missing"}})
  end
end
