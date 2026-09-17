defmodule Atlas.Repo.Migrations.BackfillIntercompanyCounterpartyPrefix do
  use Ecto.Migration

  import Ecto.Query

  alias Atlas.Finance.Config
  alias Atlas.Repo

  # Intercompany transfers were matched by exact counterparty name, so SWIFT
  # credits where the bank appends the address — e.g. a EUR 256K receipt labelled
  # "Tuist Inc.\n, 1111B S Governors Ave" — escaped the match and stayed
  # runway-relevant. A single such phantom inflow poisons every trailing burn
  # window that contains it, zeroing burn for ~6 months. Matching now uses a
  # prefix (see Atlas.Finance.Config.internal_counterparty?/2); re-flag the
  # historical rows the exact match missed.
  def up do
    names = Config.normalized_internal_entity_names()

    if names != [] do
      from(transaction in "finance_transactions",
        where: transaction.affects_runway == true,
        where: not is_nil(transaction.counterparty_name),
        where:
          fragment(
            "EXISTS (SELECT 1 FROM unnest(?::text[]) AS internal_name WHERE lower(btrim(?)) LIKE internal_name || '%')",
            ^names,
            transaction.counterparty_name
          ),
        update: [set: [affects_runway: false]]
      )
      |> Repo.update_all([])
    end
  end

  # Not reversible: re-flagged rows are indistinguishable from rows that were
  # already non-runway.
  def down, do: :ok
end
