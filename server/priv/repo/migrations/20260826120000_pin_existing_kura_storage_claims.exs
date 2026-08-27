defmodule Tuist.Repo.Migrations.PinExistingKuraStorageClaims do
  use Ecto.Migration

  # A governed instance with no pinned claim resolves one from its account at
  # render time, so it silently follows the plan constants. Those constants just
  # came down (enterprise 50Gi to 16Gi, pro 30Gi to 8Gi), which would have
  # re-rendered every unpinned instance smaller on the next reconcile and made
  # Kura evict the difference: the largest account in the fleet would have lost
  # about two thirds of its ring without a decision being taken anywhere.
  #
  # So pin what they render today, before the new constants can apply. The
  # values are the pre-change constants, hardcoded because this is a
  # point-in-time backfill rather than something that should track the ladder,
  # and the plan is resolved the way Tuist.Billing.effective_plan/1 resolves it:
  # the latest active or trialing subscription, or Air when there is none.
  # Instances created since claims began being pinned already carry one and are
  # left alone; archived and destroyed rows hold no volume and take the current
  # claim when they are next built, which is the intended start-small path.
  @governed_regions ["us-east", "us-west", "eu-central", "ca-east", "ap-southeast"]
  @volumeless_statuses [3, 4, 7]

  def up, do: pin_existing_claims!(repo())

  def pin_existing_claims!(repo) do
    regions = Enum.map_join(@governed_regions, ",", &"'#{&1}'")
    statuses = Enum.join(@volumeless_statuses, ",")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    repo.query!("""
    UPDATE kura_servers AS s
    SET storage_claim_size = CASE latest.plan
      WHEN 1 THEN '50Gi'
      WHEN 3 THEN '30Gi'
      ELSE '8Gi'
    END
    FROM (
      SELECT DISTINCT ON (a.id) a.id AS account_id, bs.plan AS plan
      FROM accounts a
      LEFT JOIN subscriptions bs
        ON bs.account_id = a.id AND bs.status IN ('active', 'trialing')
      ORDER BY a.id, bs.inserted_at DESC NULLS LAST, bs.id DESC NULLS LAST
    ) AS latest
    WHERE s.account_id = latest.account_id
      AND s.storage_claim_size IS NULL
      AND s.status NOT IN (#{statuses})
      AND s.region IN (#{regions})
    """)
  end

  def down do
    :ok
  end
end
