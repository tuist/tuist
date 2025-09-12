defmodule Tuist.Repo.Migrations.AddTokenUsagesAccountTimestampIndex do
  use Ecto.Migration

  def change do
    create index(:token_usages, [:account_id, :timestamp])
  end
end
