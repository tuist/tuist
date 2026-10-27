defmodule Tuist.Repo.Migrations.PinBer1RunnerKuraStorageClaims do
  use Ecto.Migration

  # ber1-runners becomes storage-governed. Its instances were built at the
  # region's flat 50Gi and carry no pin, and a governed instance without one
  # renders its plan's starting claim, so pin each at its account's claim
  # instead: the largest pin its other volume-holding instances carry, then the
  # sized claim, then the plan's starting claim, as
  # Tuist.Kura.PlacerClaims.effective_claim_size/1 resolves it. The plan
  # claims are the ladder's at the time of writing, hardcoded so replaying
  # this never follows a later ladder. local-path volumes cannot expand and the
  # region runs one replica without a mesh, so every changed instance rebuilds
  # its cache cold once.
  @units %{
    "" => 1,
    "Ki" => 1024,
    "Mi" => 1_048_576,
    "Gi" => 1_073_741_824,
    "Ti" => 1_099_511_627_776
  }

  def up, do: pin_existing_claims!(repo())

  def pin_existing_claims!(repo) do
    repo.transaction(fn ->
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      %{rows: rows} =
        repo.query!("""
        SELECT s.id,
          (
            SELECT array_agg(o.storage_claim_size)
            FROM kura_servers o
            WHERE o.account_id = s.account_id
              AND o.region <> 'ber1-runners'
              AND o.storage_claim_size IS NOT NULL
              AND o.status NOT IN (3, 4, 7)
          ),
          pc.claim_size,
          CASE bs.plan WHEN 1 THEN '16Gi' ELSE '8Gi' END
        FROM kura_servers s
        LEFT JOIN kura_placer_claims pc ON pc.account_id = s.account_id
        LEFT JOIN LATERAL (
          SELECT plan FROM subscriptions
          WHERE account_id = s.account_id AND status IN ('active', 'trialing', 'past_due')
          ORDER BY inserted_at DESC NULLS LAST, id DESC
          LIMIT 1
        ) bs ON true
        WHERE s.region = 'ber1-runners'
          AND s.storage_claim_size IS NULL
          AND s.status NOT IN (3, 4, 7)
        ORDER BY s.id
        FOR UPDATE OF s
        """)

      claims =
        Enum.map(rows, fn [id, pins, sized, plan] ->
          {id, largest_pin(pins || []) || valid_claim!(id, sized) || plan}
        end)

      Enum.each(claims, fn {id, claim} ->
        # excellent_migrations:safety-assured-for-next-line raw_sql_executed
        repo.query!("UPDATE kura_servers SET storage_claim_size = $1 WHERE id = $2", [claim, id])
      end)
    end)
  end

  # Unparseable pins are skipped, the way the largest pin is read at runtime.
  defp largest_pin(pins) do
    pins
    |> Enum.flat_map(fn pin ->
      case bytes(pin) do
        nil -> []
        bytes -> [{pin, bytes}]
      end
    end)
    |> case do
      [] -> nil
      parsed -> parsed |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

  defp valid_claim!(_id, nil), do: nil

  defp valid_claim!(id, claim) do
    if bytes(claim),
      do: claim,
      else:
        raise(
          ArgumentError,
          "invalid storage claim #{inspect(claim)} for kura_server #{inspect(id)}; repair before pinning"
        )
  end

  defp bytes(claim) do
    case Regex.run(~r/\A([1-9][0-9]*)(Ki|Mi|Gi|Ti|)\z/, claim, capture: :all_but_first) do
      [value, unit] -> String.to_integer(value) * Map.fetch!(@units, unit)
      _ -> nil
    end
  end

  # The pins are the claims the rebuilt caches now run; restoring 50Gi would
  # rebuild them again.
  def down, do: :ok
end
