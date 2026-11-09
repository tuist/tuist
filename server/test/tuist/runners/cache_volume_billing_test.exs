defmodule Tuist.Runners.CacheVolumeBillingTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumeBilling
  alias Tuist.Runners.CacheVolumes.SavedSize
  alias Tuist.Runners.CacheVolumes.Volume
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @gigabyte 1_000_000_000
  @hour 3600
  @month_seconds 730 * @hour

  setup do
    %{account: AccountsFixtures.account_fixture()}
  end

  defp volume(account, attrs \\ []) do
    Repo.insert!(
      struct(
        %Volume{
          account_id: account.id,
          repository_id: System.unique_integer([:positive]),
          repository: "org/app",
          key: "deps",
          architecture: "arm64",
          uid: 501
        },
        attrs
      )
    )
  end

  defp saved(volume, observed_at, size_bytes) do
    Repo.insert!(%SavedSize{
      volume_id: volume.id,
      size_bytes: size_bytes,
      observed_at: DateTime.add(observed_at, 0, :microsecond)
    })
  end

  describe "byte_seconds_per_day/3" do
    test "weights each saved size by how long it was held, per UTC day", %{account: account} do
      volume = volume(account)
      saved(volume, ~U[2026-09-30 08:00:00.000000Z], 10 * @gigabyte)
      saved(volume, ~U[2026-10-02 12:00:00.000000Z], 30 * @gigabyte)

      assert CacheVolumeBilling.byte_seconds_per_day(
               account.id,
               ~U[2026-10-01 00:00:00.000000Z],
               ~U[2026-10-03 00:00:00.000000Z]
             ) == [
               %{date: ~D[2026-10-01], repository: "org/app", byte_seconds: 10 * @gigabyte * 86_400},
               %{
                 date: ~D[2026-10-02],
                 repository: "org/app",
                 byte_seconds: 10 * @gigabyte * 43_200 + 30 * @gigabyte * 43_200
               }
             ]
    end

    test "counts a volume only from its first saved size", %{account: account} do
      volume = volume(account)
      saved(volume, ~U[2026-10-01 18:00:00.000000Z], @gigabyte)

      assert [%{byte_seconds: byte_seconds}] =
               CacheVolumeBilling.byte_seconds_per_day(
                 account.id,
                 ~U[2026-10-01 00:00:00.000000Z],
                 ~U[2026-10-02 00:00:00.000000Z]
               )

      assert byte_seconds == @gigabyte * 6 * @hour
    end

    test "leaves out docker and checkout volumes and other accounts", %{account: account} do
      other = AccountsFixtures.account_fixture()

      for {owner, key} <- [{account, "docker"}, {account, "checkout"}, {other, "deps"}] do
        owner |> volume(key: key) |> saved(~U[2026-09-01 00:00:00.000000Z], 50 * @gigabyte)
      end

      account |> volume(key: "tuist-xcode") |> saved(~U[2026-09-01 00:00:00.000000Z], @gigabyte)

      assert [%{byte_seconds: byte_seconds}] =
               CacheVolumeBilling.byte_seconds_per_day(
                 account.id,
                 ~U[2026-10-01 00:00:00.000000Z],
                 ~U[2026-10-02 00:00:00.000000Z]
               )

      assert byte_seconds == @gigabyte * 86_400
    end

    test "counts unmeasured and cleared heads as nothing", %{account: account} do
      volume = volume(account)
      saved(volume, ~U[2026-09-30 00:00:00.000000Z], 4 * @gigabyte)
      saved(volume, ~U[2026-10-01 06:00:00.000000Z], nil)
      saved(volume, ~U[2026-10-01 12:00:00.000000Z], 4 * @gigabyte)
      saved(volume, ~U[2026-10-01 18:00:00.000000Z], 0)

      assert [%{byte_seconds: byte_seconds}] =
               CacheVolumeBilling.byte_seconds_per_day(
                 account.id,
                 ~U[2026-10-01 00:00:00.000000Z],
                 ~U[2026-10-02 00:00:00.000000Z]
               )

      assert byte_seconds == 4 * @gigabyte * 12 * @hour
    end

    test "takes the later of two observations at the same instant", %{account: account} do
      volume = volume(account)
      saved(volume, ~U[2026-10-01 00:00:00.000000Z], 9 * @gigabyte)
      saved(volume, ~U[2026-10-01 00:00:00.000000Z], @gigabyte)

      assert [%{byte_seconds: byte_seconds}] =
               CacheVolumeBilling.byte_seconds_per_day(
                 account.id,
                 ~U[2026-10-01 00:00:00.000000Z],
                 ~U[2026-10-02 00:00:00.000000Z]
               )

      assert byte_seconds == @gigabyte * 86_400
    end
  end

  describe "meter_value/3" do
    test "reports a 100 GB head held for a 730-hour month as the whole allowance", %{account: account} do
      account |> volume() |> saved(~U[2026-09-01 00:00:00.000000Z], 100 * @gigabyte)
      period_start = ~U[2026-10-01 00:00:00.000000Z]

      assert CacheVolumeBilling.meter_value(account.id, period_start, DateTime.add(period_start, @month_seconds)) ==
               CacheVolumeBilling.meter_price().included
    end

    test "sums a split day to what the whole day reports", %{account: account} do
      volume = volume(account)
      saved(volume, ~U[2026-09-01 00:00:00.000000Z], 7 * @gigabyte)
      saved(volume, ~U[2026-10-01 09:30:00.000000Z], 11 * @gigabyte)
      day_start = ~U[2026-10-01 00:00:00.000000Z]
      cut = ~U[2026-10-01 15:00:00.000000Z]
      day_end = ~U[2026-10-02 00:00:00.000000Z]

      whole = CacheVolumeBilling.meter_value(account.id, day_start, day_end)

      assert whole == div((7 * 34_200 + 11 * 52_200) * 1_000, 2_628_000)

      assert_in_delta CacheVolumeBilling.meter_value(account.id, day_start, cut) +
                        CacheVolumeBilling.meter_value(account.id, cut, day_end),
                      whole,
                      1
    end
  end

  describe "stored_bytes/2" do
    test "sums every billed volume's latest saved size", %{account: account} do
      first = volume(account)
      saved(first, ~U[2026-10-01 00:00:00.000000Z], 2 * @gigabyte)
      saved(first, ~U[2026-10-02 00:00:00.000000Z], 3 * @gigabyte)
      account |> volume(key: "other") |> saved(~U[2026-10-01 00:00:00.000000Z], nil)
      account |> volume(key: "docker") |> saved(~U[2026-10-01 00:00:00.000000Z], 90 * @gigabyte)

      assert CacheVolumeBilling.stored_bytes(account.id, ~U[2026-10-01 12:00:00.000000Z]) == 2 * @gigabyte
      assert CacheVolumeBilling.stored_bytes(account.id, ~U[2026-10-03 00:00:00.000000Z]) == 3 * @gigabyte
    end
  end

  describe "period_breakdown/2" do
    test "charges the GB-months past the allowance at $0.10 each", %{account: account} do
      period_start = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      period_end = DateTime.add(period_start, @month_seconds)
      account |> volume() |> saved(DateTime.add(period_start, -1, :day), 150 * @gigabyte)

      breakdown = CacheVolumeBilling.period_breakdown(account, {period_start, period_end})

      assert breakdown.history_complete
      assert breakdown.byte_months == 150 * @gigabyte
      assert breakdown.billable == 50 * @gigabyte
      assert breakdown.gross == Money.new(1_500, :USD)
      assert breakdown.included_credit == Money.new(1_000, :USD)
      assert breakdown.charge == Money.new(500, :USD)
      # No subscription to bill it to.
      assert breakdown.billed == nil
      assert breakdown.projected == nil
      assert breakdown.projected_days == []
    end

    test "leaves what a runner trial covered out of the allowance and the charge", %{account: account} do
      period_start = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      period_end = DateTime.add(period_start, @month_seconds)
      trial_end = DateTime.add(period_start, div(@month_seconds, 2))

      account =
        account
        |> Ecto.Changeset.change(
          runner_trial_started_at: DateTime.add(period_start, -10, :day),
          runner_trial_ended_at: trial_end
        )
        |> Repo.update!()

      account |> volume() |> saved(DateTime.add(period_start, -1, :day), 300 * @gigabyte)

      breakdown = CacheVolumeBilling.period_breakdown(account, {period_start, period_end})

      assert breakdown.trial_covered == 150 * @gigabyte
      assert breakdown.billable == 50 * @gigabyte
      assert breakdown.trial_credit == Money.new(1_500, :USD)
      assert breakdown.charge == Money.new(500, :USD)
    end

    test "projects the open period at what is saved now", %{account: account} do
      now = DateTime.utc_now()
      period_start = DateTime.add(now, -10, :day)
      period_end = DateTime.add(now, 20, :day)
      account |> volume() |> saved(DateTime.add(period_start, -1, :day), 73 * @gigabyte)

      breakdown = CacheVolumeBilling.period_breakdown(account, {period_start, period_end})

      assert breakdown.stored_bytes == 73 * @gigabyte
      assert_in_delta breakdown.projected, 73 * @gigabyte * 30 * 86_400 / @month_seconds, @gigabyte
      assert length(breakdown.projected_days) in 19..20
      assert Enum.all?(breakdown.projected_days, &(&1.bytes == 73 * @gigabyte))
    end

    test "reports no figures for a period older than the saved-size history", %{account: account} do
      period_start = DateTime.add(DateTime.utc_now(), -120, :day)

      breakdown =
        CacheVolumeBilling.period_breakdown(account, {period_start, DateTime.add(period_start, 30, :day)})

      refute breakdown.history_complete
      refute Map.has_key?(breakdown, :charge)
    end
  end
end
