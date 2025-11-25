defmodule Tuist.Repo.Migrations.ChangeOauthTokensValueColumnsToText do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      modify :value, :text
      modify :refresh_token, :text
      modify :previous_token, :text
      modify :previous_code, :text
    end
  end

  def down do
    alter table(:oauth_tokens) do
      modify :value, :string, size: 500
      modify :refresh_token, :string, size: 500
      modify :previous_token, :string, size: 500
      modify :previous_code, :string, size: 500
    end
  end
end
