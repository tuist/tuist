defmodule Atlas.Repo.Migrations.BackfillAccountCommercialSummaryFromTerms do
  use Ecto.Migration

  def up do
    execute("""
    WITH selected_terms AS (
      SELECT DISTINCT ON (account_id)
        account_id,
        total,
        currency,
        end_date
      FROM account_terms
      WHERE total IS NOT NULL
      ORDER BY
        account_id,
        CASE
          WHEN start_date <= CURRENT_DATE
            AND (end_date IS NULL OR end_date >= CURRENT_DATE)
          THEN 0
          WHEN start_date > CURRENT_DATE THEN 1
          ELSE 2
        END,
        CASE WHEN start_date > CURRENT_DATE THEN start_date END ASC,
        start_date DESC,
        inserted_at DESC
    )
    UPDATE accounts AS account
    SET
      current_value = term.total,
      currency = COALESCE(NULLIF(term.currency, ''), account.currency),
      next_renewal_date = term.end_date,
      updated_at = NOW()
    FROM selected_terms AS term
    WHERE term.account_id = account.id
      AND (
        account.current_value IS DISTINCT FROM term.total
        OR account.currency IS DISTINCT FROM COALESCE(NULLIF(term.currency, ''), account.currency)
        OR account.next_renewal_date IS DISTINCT FROM term.end_date
      )
    """)
  end

  def down do
    :ok
  end
end
