defmodule Tuist.Repo.Migrations.CreateSignupAttributions do
  use Ecto.Migration

  def change do
    # Where a user came from when they signed up in the browser (first touch):
    # the UTM parameters the visit carried to the sign-up page, or the
    # referring site as a `referral`. One row per user, deleted with the user.
    create table(:signup_attributions, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :source, :string, null: false
      add :medium, :string
      add :campaign, :string
      add :content, :string
      add :term, :string
      add :inserted_at, :timestamptz, null: false
    end

    # Atlas' acquisition funnel reads signups by date and source.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:signup_attributions, [:inserted_at])
  end
end
