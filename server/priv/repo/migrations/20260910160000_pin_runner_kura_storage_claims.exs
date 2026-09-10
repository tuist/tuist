defmodule Tuist.Repo.Migrations.PinRunnerKuraStorageClaims do
  use Ecto.Migration

  # Enroll legacy runner caches immediately to release scheduler reservations.
  # Never grow beyond their old 50Gi here: growth needs normal admission checks.
  def up, do: pin_existing_claims!(repo())

  def pin_existing_claims!(repo) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    repo.query!("""
    WITH budgets AS (
      SELECT DISTINCT ON (a.id) a.id AS account_id,
        COALESCE(pc.claim_size, CASE bs.plan WHEN 1 THEN '16Gi' ELSE '8Gi' END) AS claim
      FROM accounts a
      LEFT JOIN kura_placer_claims pc ON pc.account_id = a.id
      LEFT JOIN subscriptions bs
        ON bs.account_id = a.id AND bs.status IN ('active', 'trialing')
      ORDER BY a.id, bs.inserted_at DESC NULLS LAST, bs.id DESC NULLS LAST
    ), parsed AS (
      SELECT account_id, claim, regexp_match(claim, '^([1-9][0-9]*)(Ki|Mi|Gi|Ti)?$') AS parts
      FROM budgets
    )
    UPDATE kura_servers AS s
    SET storage_claim_size = CASE
      WHEN parts[1]::numeric * CASE parts[2]
        WHEN 'Ki' THEN 1024::numeric
        WHEN 'Mi' THEN 1048576::numeric
        WHEN 'Gi' THEN 1073741824::numeric
        WHEN 'Ti' THEN 1099511627776::numeric
        ELSE 1::numeric
      END <= 53687091200::numeric THEN parsed.claim
      ELSE '50Gi'
    END
    FROM parsed
    WHERE s.account_id = parsed.account_id
      AND s.region = 'scw-fr-par-runners'
      AND s.storage_claim_size IS NULL
      AND s.status NOT IN (3, 4, 7)
    """)
  end

  # Retain the applied budgets on rollback; restoring 50Gi would reintroduce
  # the scheduling blockage and cannot restore content already evicted.
  def down, do: :ok
end
