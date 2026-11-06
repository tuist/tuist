defmodule Atlas.Letters.Workers.ScheduleDeliveryChecksTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Letters
  alias Atlas.Letters.Workers.ScheduleDeliveryChecks
  alias Atlas.Letters.Workers.SyncDelivery

  setup :verify_on_exit!

  test "enqueues unique status checks for submitted letters" do
    ids = [Atlas.UUIDv7.generate(), Atlas.UUIDv7.generate()]
    stub(Letters, :configured?, fn -> true end)
    stub(Letters, :list_delivery_check_candidate_ids, fn -> ids end)

    assert :ok = perform_job(ScheduleDeliveryChecks, %{})
    assert :ok = perform_job(ScheduleDeliveryChecks, %{})
    assert length(all_enqueued(worker: SyncDelivery)) == 2

    for id <- ids do
      assert_enqueued(worker: SyncDelivery, args: %{"letter_id" => id})
    end
  end

  test "skips checks when postal delivery is not configured" do
    stub(Letters, :configured?, fn -> false end)
    assert :ok = perform_job(ScheduleDeliveryChecks, %{})
    refute_enqueued(worker: SyncDelivery)
  end
end
