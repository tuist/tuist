defmodule Atlas.Repo.Migrations.BackfillQontoTransferRunwayFlag do
  use Ecto.Migration

  import Ecto.Query

  alias Atlas.Finance.Config
  alias Atlas.Repo

  # Qonto previously flagged every SEPA credit transfer (the provider sets a
  # `transfer` object on them) as non-runway. That wrongly excluded payroll and
  # vendor payments — our largest operating expenses — from burn/runway, which is
  # why the dashboard showed ~0 burn while the bank balance was clearly
  # declining. The provider now mirrors cash impact and relies on
  # counterparty-based intercompany detection instead. Re-flag the historical
  # Qonto rows so burn/runway reflect reality; syncs only re-fetch recent
  # transactions, so they cannot fix older rows on their own.
  def up do
    # Keep genuine intercompany movement (counterparty is one of our own legal
    # entities) excluded, reusing the same Application-env source of truth and
    # normalization as the runtime sync flagging so the two cannot diverge.
    names = Config.normalized_internal_entity_names()

    base =
      from(transaction in "finance_transactions",
        where: transaction.provider == "qonto",
        where: transaction.affects_cash_balance == true,
        where: transaction.affects_runway == false
      )

    query =
      if names == [] do
        base
      else
        from(transaction in base,
          where:
            is_nil(transaction.counterparty_name) or
              fragment("lower(btrim(?))", transaction.counterparty_name) not in ^names
        )
      end

    query
    |> update(set: [affects_runway: true])
    |> Repo.update_all([])
  end

  # Not reversible: re-flagged rows are indistinguishable from rows that were
  # already runway-relevant.
  def down, do: :ok
end
