defmodule Atlas.Repo.Migrations.AddDynamicRulesToEmailAudiences do
  use Ecto.Migration

  def change do
    alter table(:gtm_audiences) do
      add :membership_type, :string, null: false, default: "static"
      add :rules, :map, null: false, default: %{}
    end

    create constraint(:gtm_audiences, :gtm_audiences_membership_type,
             check: "membership_type IN ('static', 'dynamic')"
           )
  end
end
