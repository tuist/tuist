defmodule Tuist.Repo.Migrations.PinRunnerKuraStorageClaims do
  use Ecto.Migration

  # Enroll legacy runner caches immediately to release scheduler reservations.
  # Never grow beyond their old 50Gi here: growth needs normal admission checks.
  # Plan defaults are intentionally frozen at enrollment time. Replaying this
  # historical migration must not use a future Regions ladder; change existing
  # pins through measured sizing or a new migration when that ladder changes.
  @units %{
    "" => 1,
    "Ki" => 1024,
    "Mi" => 1_048_576,
    "Gi" => 1_073_741_824,
    "Ti" => 1_099_511_627_776
  }
  @legacy_bytes 50 * 1_073_741_824

  def up, do: pin_existing_claims!(repo())

  def pin_existing_claims!(repo) do
    repo.transaction(fn ->
      # Start at the small enrollable set and lock those rows while resolving
      # budgets, so a concurrent lifecycle or explicit pin update cannot race us.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      %{rows: rows} =
        repo.query!("""
        SELECT s.id,
          COALESCE(pc.claim_size, CASE bs.plan WHEN 1 THEN '16Gi' ELSE '8Gi' END)
        FROM kura_servers s
        LEFT JOIN kura_placer_claims pc ON pc.account_id = s.account_id
        LEFT JOIN LATERAL (
          SELECT plan FROM subscriptions
          WHERE account_id = s.account_id AND status IN ('active', 'trialing')
          ORDER BY inserted_at DESC NULLS LAST, id DESC
          LIMIT 1
        ) bs ON true
        WHERE s.region = 'scw-fr-par-runners'
          AND s.storage_claim_size IS NULL
          AND s.status NOT IN (3, 4, 7)
        ORDER BY s.id
        FOR UPDATE OF s
        """)

      # Validate the whole batch before writing any pins. Unknown historical or
      # manually inserted formats need repair, not a silent substitution of 50Gi.
      claims = Enum.map(rows, fn [id, claim] -> {id, enrollment_claim!(id, claim)} end)

      Enum.each(claims, fn {id, claim} ->
        # excellent_migrations:safety-assured-for-next-line raw_sql_executed
        repo.query!("UPDATE kura_servers SET storage_claim_size = $1 WHERE id = $2", [claim, id])
      end)
    end)
  end

  defp enrollment_claim!(id, claim) do
    case Regex.run(~r/\A([1-9][0-9]*)(Ki|Mi|Gi|Ti|)\z/, claim, capture: :all_but_first) do
      [value, unit] ->
        if String.to_integer(value) * Map.fetch!(@units, unit) <= @legacy_bytes,
          do: claim,
          else: "50Gi"

      _ ->
        raise ArgumentError,
              "invalid runner storage claim #{inspect(claim)} for kura_server #{id}; repair before enrollment"
    end
  end

  # Retain the applied budgets on rollback; restoring 50Gi would reintroduce
  # the scheduling blockage and cannot restore content already evicted.
  def down, do: :ok
end
