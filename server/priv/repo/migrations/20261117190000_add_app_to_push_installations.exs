defmodule Tuist.Repo.Migrations.AddAppToPushInstallations do
  use Ecto.Migration

  # Tuist Guild registers its installations next to the Tuist app's. `app` picks
  # the APNs topic, which notifications reach the row and which first-party OAuth
  # client its grant belongs to. Guild's macOS app registers APNs tokens as `macos`.
  def up do
    alter table(:push_installations) do
      add :app, :string, null: false, default: "tuist"
    end

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_app, check: "app IN ('tuist', 'guild')")

    drop constraint(:push_installations, :supported_platform)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_platform,
             check: "platform IS NULL OR platform IN ('ios', 'macos', 'android')"
           )
  end

  def down do
    execute "DELETE FROM push_installations WHERE app <> 'tuist' OR platform = 'macos'"

    drop constraint(:push_installations, :supported_platform)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_platform,
             check: "platform IS NULL OR platform IN ('ios', 'android')"
           )

    drop constraint(:push_installations, :supported_app)

    alter table(:push_installations) do
      remove :app
    end
  end
end
