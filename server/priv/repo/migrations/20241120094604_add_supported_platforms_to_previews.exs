defmodule Tuist.Repo.Migrations.AddSupportedPlatformsToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :supported_platforms, {:array, :integer}
    end
  end
end
