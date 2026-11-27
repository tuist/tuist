defmodule Tuist.RemoteExecution.LearnedFloorTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.RemoteExecution.Action
  alias Tuist.RemoteExecution.LearnedFloor
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp account!(memory_gb_limit) do
    AccountsFixtures.user_fixture().account
    |> Ecto.Changeset.change(remote_execution_memory_gb_limit: memory_gb_limit)
    |> Repo.update!()
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  # A build of `account` that started `started_ago` seconds ago and queued
  # the 4 GiB actions `offsets_ms` milliseconds after its start.
  defp build!(account, started_ago, offsets_ms, opts \\ []) do
    invocation_id = Ecto.UUID.generate()
    start = ago(started_ago)

    rows =
      for offset <- offsets_ms do
        queued_at = start |> DateTime.add(offset, :millisecond) |> DateTime.to_naive()

        %{
          operation_id: Ecto.UUID.generate(),
          account_id: account.id,
          project_id: 1,
          invocation_id: invocation_id,
          memory_gb: 4,
          cached_result: Keyword.get(opts, :cached_result, false),
          queued_at: queued_at,
          inserted_at: queued_at
        }
      end

    {_, _} = IngestRepo.insert_all(Action, rows)
  end

  # `n` actions spread over the first second.
  defp wave(n), do: Enum.map(1..n, &div(&1 * 1_000, n))

  test "is the 90th percentile of an active account's first waves, in slots" do
    account = account!(1_024)

    # Ten builds whose first 2 s queue 3..12 actions of 4 GiB, plus
    # actions after the first 2 s, which do not count. Each 4 GiB action
    # charges 4,160 MiB, so n actions need n slots.
    for {n, i} <- Enum.with_index(3..12) do
      build!(account, 86_400 * (i + 1), wave(n) ++ [5_000, 6_000, 7_000, 8_000, 9_000])
    end

    build!(account, 600, wave(1))

    # Builds' slots: 1, 3, 4, ..., 12. p90 (exact) over 11 values is 11.
    assert LearnedFloor.by_account()[account.id] == 11
  end

  test "is zero while the account has not started a build in 30 minutes" do
    account = account!(1_024)

    build!(account, 3_600, wave(20))
    build!(account, 7_200, wave(20))

    refute Map.has_key?(LearnedFloor.by_account(), account.id)
  end

  test "ignores cached results and builds older than two weeks" do
    account = account!(1_024)

    build!(account, 15 * 86_400, wave(50))
    build!(account, 86_400, wave(30), cached_result: true)
    build!(account, 300, wave(5))

    assert LearnedFloor.by_account()[account.id] == 5
  end

  test "is capped at what the account limit lets it run at once" do
    account = account!(16)

    build!(account, 300, wave(20))

    assert LearnedFloor.by_account()[account.id] == 4
  end

  test "sums the active accounts' floors" do
    a = account!(1_024)
    b = account!(1_024)

    build!(a, 300, wave(7))
    build!(b, 300, wave(9))

    floors = LearnedFloor.by_account()
    assert floors[a.id] == 7
    assert floors[b.id] == 9
    assert LearnedFloor.slots() >= 16
  end
end
