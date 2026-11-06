defmodule Atlas.Repo.Migrations.AddMacosPushPlatform do
  use Ecto.Migration

  def up do
    drop constraint(:push_installations, :supported_platform)

    create constraint(:push_installations, :supported_platform,
             check: "platform IS NULL OR platform IN ('ios', 'macos', 'android')"
           )
  end

  def down do
    # Validate rather than removing desktop registrations or tombstones to make
    # old code fit. Keep this additive migration when rolling application code back.
    drop constraint(:push_installations, :supported_platform)

    create constraint(:push_installations, :supported_platform,
             check: "platform IS NULL OR platform IN ('ios', 'android')"
           )
  end
end
