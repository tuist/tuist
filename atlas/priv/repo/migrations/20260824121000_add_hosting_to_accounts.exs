defmodule Atlas.Repo.Migrations.AddHostingToAccounts do
  use Ecto.Migration

  @self_hosted_account_keys [
    "granola:getmidas-com",
    "operate:489c38d9-ba68-473c-82b3-7989d121a075",
    "enterprise:trendyol",
    "operate:59031885-ea64-41f0-979e-818d38a33c55",
    "granola:toss-im",
    "operate:a52406e5-c33f-4da2-a069-075473ceaab5",
    "operate:32e2ce7f-b28b-42ff-8603-d21cd21dddce"
  ]

  def up do
    alter table(:accounts) do
      add :hosting, :string, null: false, default: "unknown"
    end

    create constraint(:accounts, :accounts_hosting_check,
             check: "hosting IN ('unknown', 'cloud', 'self_hosted')"
           )

    execute(
      "UPDATE accounts SET hosting = 'self_hosted' WHERE account_key IN (#{quoted_account_keys()})",
      "UPDATE accounts SET hosting = 'unknown' WHERE account_key IN (#{quoted_account_keys()})"
    )

    execute(
      "UPDATE accounts SET hosting = 'cloud' WHERE account_key = 'enterprise:zillow'",
      "UPDATE accounts SET hosting = 'unknown' WHERE account_key = 'enterprise:zillow'"
    )
  end

  def down do
    drop constraint(:accounts, :accounts_hosting_check)

    alter table(:accounts) do
      remove :hosting
    end
  end

  defp quoted_account_keys do
    @self_hosted_account_keys
    |> Enum.map_join(", ", &"'#{&1}'")
  end
end
