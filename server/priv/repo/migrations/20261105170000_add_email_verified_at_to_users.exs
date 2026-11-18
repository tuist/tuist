defmodule Tuist.Repo.Migrations.AddEmailVerifiedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # When control of the account's address was proved: a
      # confirmation or password-reset link, a one-time code, or a sign-in
      # through an instance-configured provider. Null for accounts that never
      # proved it, such as auto-confirmed and SCIM-provisioned ones.
      add :email_verified_at, :timestamptz
    end
  end
end
