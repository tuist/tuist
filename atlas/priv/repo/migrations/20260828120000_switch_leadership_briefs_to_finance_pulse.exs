defmodule Atlas.Repo.Migrations.SwitchLeadershipBriefsToFinancePulse do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE brief_subscriptions
    SET domains = ARRAY['finance']::varchar[]
    WHERE audience_key = 'leadership'
      AND cadence IN ('daily', 'weekly')
      AND domains = ARRAY['finance', 'accounts', 'outreach', 'product', 'company']::varchar[]
    """)
  end

  def down do
    :ok
  end
end
