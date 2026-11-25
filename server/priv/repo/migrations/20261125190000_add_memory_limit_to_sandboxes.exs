defmodule Tuist.Repo.Migrations.AddMemoryLimitToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The guest memory a Linux agent sandbox boots with and bursts up to,
      # above its request (`memory_mb`); NULL boots it at its request.
      add :memory_limit_mb, :integer
    end
  end
end
