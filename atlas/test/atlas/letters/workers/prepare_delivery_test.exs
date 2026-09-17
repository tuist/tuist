defmodule Atlas.Letters.Workers.PrepareDeliveryTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit
  alias Atlas.Letters
  alias Atlas.Letters.Workers.PrepareDelivery

  setup :verify_on_exit!

  test "prepares delivery details with a worker audit context" do
    expect(Letters, :prepare_delivery_details, fn "letter-123" ->
      assert Audit.current_context().interface == "worker"
      {:ok, %{id: "letter-123"}}
    end)

    assert :ok = PrepareDelivery.perform(%Oban.Job{args: %{"letter_id" => "letter-123"}})
  end

  test "cancels when the letter no longer exists" do
    expect(Letters, :prepare_delivery_details, fn "missing-letter" -> {:error, :not_found} end)

    assert {:cancel, :letter_not_found} =
             PrepareDelivery.perform(%Oban.Job{args: %{"letter_id" => "missing-letter"}})
  end
end
