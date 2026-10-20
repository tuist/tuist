defmodule Atlas.Finance.Workers.ScheduleSourceSyncsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Workers.ScheduleSourceSyncs

  setup :verify_on_exit!

  test "enqueues one sync job per configured source key" do
    parent = self()

    expect(Finance, :configured_source_keys, fn -> ["qonto-main", "mercury-main"] end)

    expect(Oban, :insert, 2, fn changeset ->
      source_key = changeset.changes.args[:source_key] || changeset.changes.args["source_key"]
      send(parent, {:inserted_source_key, source_key})
      {:ok, %Oban.Job{}}
    end)

    assert {:ok, 2} = ScheduleSourceSyncs.perform(%Oban.Job{})

    assert_receive {:inserted_source_key, "qonto-main"}
    assert_receive {:inserted_source_key, "mercury-main"}
  end

  test "cancels when there are no configured sources" do
    expect(Finance, :configured_source_keys, fn -> [] end)

    assert {:cancel, :source_not_configured} = ScheduleSourceSyncs.perform(%Oban.Job{})
  end
end
