defmodule Atlas.Repo.Migrations.AddVisibilityToSpecs do
  use Ecto.Migration

  def change do
    alter table(:specs) do
      add :visibility, :string, null: false, default: "public"
    end

    create constraint(:specs, :specs_visibility_check,
             check: "visibility in ('public', 'private')"
           )

    create index(:specs, [:visibility, :inserted_at])
  end
end
