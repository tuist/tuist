defmodule Atlas.Repo.Migrations.BackfillInternalTransferRunwayFlag do
  use Ecto.Migration

  # Re-classify already-synced intercompany transfers (counterparty == one of our
  # own legal entities) as non-runway. Syncs only re-fetch recent transactions,
  # so the new sync-time flagging would not touch historical rows on its own.
  def up do
    execute("""
    UPDATE finance_transactions
    SET affects_runway = false
    WHERE affects_runway = true
      AND counterparty_name IS NOT NULL
      AND lower(btrim(counterparty_name)) IN (
        SELECT lower(btrim(accounts.name))
        FROM accounts
        JOIN finance_sources ON finance_sources.atlas_account_id = accounts.id
        WHERE accounts.name IS NOT NULL
        UNION
        SELECT lower(btrim(accounts.legal_name))
        FROM accounts
        JOIN finance_sources ON finance_sources.atlas_account_id = accounts.id
        WHERE accounts.legal_name IS NOT NULL
      )
    """)
  end

  # Not reversible: backfilled rows are indistinguishable from rows that were
  # already non-runway, so there is nothing safe to restore.
  def down, do: :ok
end
