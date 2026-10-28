defmodule Atlas.Repo.Migrations.DisableDailyLeadershipFinancialPulse do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE brief_subscriptions
    SET enabled = FALSE
    WHERE audience_key = 'leadership'
      AND cadence = 'daily'
      AND enabled = TRUE
    """)
  end

  def down do
    execute("""
    UPDATE brief_subscriptions
    SET enabled = TRUE
    WHERE audience_key = 'leadership'
      AND cadence = 'daily'
      AND domains = ARRAY['finance']::varchar[]
      AND enabled = FALSE
    """)
  end
end
