defmodule Atlas.Repo.Migrations.BackfillInternalEntityTransfers do
  use Ecto.Migration

  import Ecto.Query

  # Re-classify already-synced intercompany transfers (counterparty matches one
  # of our configured legal entities) as non-runway. Supersedes the earlier
  # backfill, which derived entities from the finance_source -> account link
  # that is unset in production. Syncs only re-fetch recent transactions, so the
  # sync-time flagging cannot fix historical rows on its own.
  def up do
    # Use the same source of truth (Application env via Config) and normalization
    # rules as the runtime sync flagging, so the backfill can't diverge.
    names = Atlas.Finance.Config.normalized_internal_entity_names()

    if names != [] do
      from(transaction in "finance_transactions",
        where: transaction.affects_runway == true,
        where: not is_nil(transaction.counterparty_name),
        where: fragment("lower(btrim(?))", transaction.counterparty_name) in ^names,
        update: [set: [affects_runway: false]]
      )
      |> Atlas.Repo.update_all([])
    end
  end

  # Not reversible: backfilled rows are indistinguishable from rows that were
  # already non-runway.
  def down, do: :ok
end
