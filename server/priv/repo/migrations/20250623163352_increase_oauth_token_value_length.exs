defmodule Tuist.Repo.Migrations.IncreaseOauthTokenValueLength do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:value, :string, size: 500)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:refresh_token, :string, size: 500)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:previous_code, :string, size: 500)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:previous_token, :string, size: 500)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:state, :string, size: 500)
    end
  end

  def down do
    alter table(:oauth_tokens) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:value, :string)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:refresh_token, :string)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:previous_code, :string)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:previous_token, :string)
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify(:state, :string)
    end
  end
end
