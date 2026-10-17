defmodule Atlas.Letters.Workers.SyncDeliveryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Letters
  alias Atlas.Letters.Letter
  alias Atlas.Letters.Workers.SyncDelivery

  setup :verify_on_exit!

  test "synchronizes existing postage without delivering again" do
    id = Atlas.UUIDv7.generate()
    expect(Letters, :sync_delivery, fn ^id -> {:ok, %Letter{id: id, status: "sent"}} end)
    stub(Letters, :deliver, fn _ -> flunk("status checks must not send postage") end)
    assert :ok = SyncDelivery.perform(%Oban.Job{args: %{"letter_id" => id}})
  end

  test "cancels checks for deleted or unsubmitted letters and missing configuration" do
    for {error, reason} <- [
          not_found: :letter_not_found,
          letter_not_submitted: :letter_not_submitted,
          postal_delivery_not_configured: :postal_delivery_not_configured
        ] do
      id = Atlas.UUIDv7.generate()
      expect(Letters, :sync_delivery, fn ^id -> {:error, error} end)
      assert {:cancel, ^reason} = SyncDelivery.perform(%Oban.Job{args: %{"letter_id" => id}})
    end
  end

  test "retries transient provider failures" do
    id = Atlas.UUIDv7.generate()
    reason = {:pingen_letter_status_failed, 503}
    expect(Letters, :sync_delivery, fn ^id -> {:error, reason} end)
    assert {:error, ^reason} = SyncDelivery.perform(%Oban.Job{args: %{"letter_id" => id}})
  end
end
