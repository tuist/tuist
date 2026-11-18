defmodule Condukt.Session.ParkingTest do
  use ExUnit.Case, async: true

  alias Condukt.Park
  alias Condukt.Session.Parking

  defmodule Answer do
    @behaviour Condukt.Signal

    @impl true
    def cast(value), do: {:ok, value}
  end

  @a {Answer, "a"}
  @b {Answer, "b"}
  @c {Answer, "c"}

  test "a signal wake consumes its key and closes the wait's other keys, also when they arrived early" do
    parking = apply_all(Parking.new(), [{:signal, @b, "early b"}])
    parking = park!(parking, "call_1", [@a, @b])

    assert %{"call_1" => %{wake: {:signal, @b, "early b"}}} = parking.waits
    assert parking.inbox == %{}
    assert Parking.signal(parking, @a, "late a") == {:error, :closed}
    assert Parking.signal(parking, @b, "retry b") == {:error, :duplicate}
    assert Parking.park(parking, {"call_2", "t"}, nil, %Park{signals: [@a]}) == {:error, {:signal_key_used, @a}}
  end

  test "ending the turn drops its waits and early signals and keeps every key it used closed" do
    parking =
      Parking.new()
      |> park!("call_1", [@a])
      |> apply_all([{:signal, @c, "unclaimed"}])
      |> apply_all([:end_turn])

    assert parking.waits == %{}
    assert parking.inbox == %{}
    assert Parking.signal(parking, @a, "x") == {:error, :closed}
    assert Parking.signal(parking, @c, "x") == {:error, :closed}
    assert {:ok, _records} = Parking.signal(parking, @b, "new key")
  end

  test "unclaimed signals are capped, but a key a call waits on is still accepted" do
    parking =
      Enum.reduce(1..100, park!(Parking.new(), "call_1", [@a]), fn n, parking ->
        {:ok, records} = Parking.signal(parking, {Answer, "k#{n}"}, n)
        apply_all(parking, records)
      end)

    assert Parking.signal(parking, {Answer, "k101"}, 101) == {:error, :inbox_full}
    assert {:ok, _records} = Parking.signal(parking, @a, "claimed")
  end

  test "replaying the records rebuilds waits, early signals, and closed keys" do
    records = [
      {:park, "call_1", %{tool: "t", signals: [@a], until: 1_000, state: :one}},
      {:signal, @c, "early c"},
      {:park, "call_2", %{tool: "t", signals: [@b, @c], until: nil, state: :two}},
      {:timeout, "call_1"},
      # A late timeout for a woken wait changes nothing.
      {:timeout, "call_2"},
      {:done, "call_2"}
    ]

    parking = Parking.replay(records)

    assert Map.keys(parking.waits) == ["call_1"]
    assert parking.waits["call_1"].wake == :timeout
    assert parking.inbox == %{}
    assert parking.settled == %{@a => :closed, @b => :closed, @c => :consumed}
    assert Parking.replay(records) == parking
  end

  defp park!(parking, id, signals) do
    {:ok, records} = Parking.park(parking, {id, "t"}, nil, %Park{signals: signals})
    apply_all(parking, records)
  end

  defp apply_all(parking, records), do: Enum.reduce(records, parking, &Parking.apply_record(&2, &1))
end
