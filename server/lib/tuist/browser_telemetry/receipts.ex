defmodule Tuist.BrowserTelemetry.Receipts do
  @moduledoc """
  Shared, bounded replay receipts for browser LCP reports. Only acknowledged
  deliveries become duplicates; failed deliveries remain retryable. An Alloy
  acceptance followed by a lost response is necessarily ambiguous.
  """

  import Ecto.Query

  alias Tuist.Repo

  @lease_seconds 30
  @retention_seconds 172_800
  @prune_batch_size 5_000

  def deliver([], forward), do: forward.(MapSet.new())

  def deliver(keys, forward) do
    keys = keys |> Enum.uniq() |> Enum.sort()
    lease = Ecto.UUID.bingenerate()

    with {:ok, duplicates} <- claim(keys, lease) do
      try do
        case forward.(duplicates) do
          {:ok, _} = result ->
            complete(keys, lease)
            result

          error ->
            error
        end
      after
        release(keys, lease)
      end
    end
  end

  def prune do
    expired =
      from(r in "browser_telemetry_receipts",
        where: r.expires_at <= fragment("now()"),
        select: r.key,
        limit: @prune_batch_size
      )

    {count, _} =
      Repo.delete_all(
        from(r in "browser_telemetry_receipts",
          where: r.key in subquery(expired) and r.expires_at <= fragment("now()")
        )
      )

    count
  end

  def prune_batch_size, do: @prune_batch_size

  defp claim(keys, lease) do
    Repo.transaction(fn ->
      # Sort keys to give overlapping batches the same row-lock order. The
      # transaction ends before HTTP; no database connection waits on Alloy.
      %{rows: claimed} =
        Repo.query!(
          """
          INSERT INTO browser_telemetry_receipts (key, lease_id, expires_at)
          SELECT key, $2, now() + $3 * interval '1 second'
          FROM unnest($1::bytea[]) AS key ORDER BY key
          ON CONFLICT (key) DO UPDATE
          SET lease_id = EXCLUDED.lease_id, expires_at = EXCLUDED.expires_at, completed_at = NULL
          WHERE browser_telemetry_receipts.expires_at <= now()
          RETURNING key
          """,
          [keys, lease, @lease_seconds],
          timeout: 2_000
        )

      claimed = MapSet.new(claimed, fn [key] -> key end)
      remaining = Enum.reject(keys, &MapSet.member?(claimed, &1))

      completed =
        Repo.all(
          from(r in "browser_telemetry_receipts",
            where: r.key in ^remaining and not is_nil(r.completed_at) and r.expires_at > fragment("now()"),
            select: r.key
          )
        )

      if length(completed) != length(remaining), do: Repo.rollback(:in_progress)
      MapSet.new(completed)
    end)
  end

  defp complete(keys, lease) do
    Repo.update_all(
      from(r in "browser_telemetry_receipts",
        where: r.key in ^keys and r.lease_id == ^lease,
        update: [
          set: [
            completed_at: fragment("now()"),
            expires_at: fragment("now() + ? * interval '1 second'", ^@retention_seconds)
          ]
        ]
      ),
      []
    )
  end

  defp release(keys, lease) do
    Repo.delete_all(
      from(r in "browser_telemetry_receipts",
        where: r.key in ^keys and r.lease_id == ^lease and is_nil(r.completed_at)
      )
    )
  end
end
