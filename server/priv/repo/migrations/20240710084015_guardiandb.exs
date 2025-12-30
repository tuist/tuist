defmodule Tuist.Repo.Migrations.CreateGuardianDBTokensTable do
  use Ecto.Migration

  def change do
    create table(:tokens, primary_key: false) do
      add(:jti, :string, primary_key: true)
      add(:aud, :string, primary_key: true)
      add(:typ, :string)
      add(:iss, :string)
      add(:sub, :string)
      add(:exp, :bigint)
      add(:jwt, :text)
      add(:claims, :map)
      # credo:disable-for-next-line Credo.Checks.TimestampsType
      timestamps()
    end
  end
end
