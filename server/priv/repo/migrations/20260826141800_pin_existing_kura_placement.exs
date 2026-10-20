defmodule Tuist.Repo.Migrations.PinExistingKuraPlacement do
  use Ecto.Migration

  # Record where every live account is served from today, before resolution
  # starts consulting anything new.
  #
  # This is a precondition rather than hygiene. Resolution used to answer with
  # the first live instance's region, so an account's placement was whatever
  # its history left behind; once origin can decide, an account with no
  # recorded placement could resolve somewhere else the moment its traffic was
  # attributed. That does not move an instance, it cold-provisions a second one
  # and strands the first, because the plans holding most of the fleet are
  # never archived by inactivity and nothing else would ever reclaim it.
  #
  # So the present becomes stated intent: the oldest live public instance is
  # the primary, any others are secondaries, and every one of them is a
  # `desired` row the placer must decide its way out of rather than drift past.
  #
  # `(inserted_at, id)` is the same total order resolution used to pick a live
  # region with, so this writes down the answer that was already being given.
  @volumeless_statuses [3, 4, 7]
  @private_regions ["scw-fr-par-runners", "hetzner-staging-runners"]

  def up, do: pin_existing_placement!(repo())

  def pin_existing_placement!(repo) do
    statuses = Enum.join(@volumeless_statuses, ",")
    private = Enum.map_join(@private_regions, ",", &"'#{&1}'")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    repo.query!("""
    INSERT INTO kura_placer_regions (account_id, region, role, status, evidence, inserted_at, updated_at)
    SELECT
      ranked.account_id,
      ranked.region,
      CASE WHEN ranked.position = 1 THEN 'primary' ELSE 'secondary' END,
      'desired',
      '{"signal": "pinned_existing_placement"}'::jsonb,
      NOW(),
      NOW()
    FROM (
      SELECT
        s.account_id,
        s.region,
        ROW_NUMBER() OVER (PARTITION BY s.account_id ORDER BY s.inserted_at ASC, s.id ASC) AS position
      FROM kura_servers s
      WHERE s.status NOT IN (#{statuses})
        AND s.move_phase = 0
        AND s.region NOT IN (#{private})
    ) AS ranked
    ON CONFLICT (account_id, region) DO NOTHING
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    repo().query!(
      "DELETE FROM kura_placer_regions WHERE evidence->>'signal' = 'pinned_existing_placement'"
    )

    :ok
  end
end
