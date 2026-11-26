defmodule Tuist.Repo.Migrations.AddMfaRequiredAtToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      # When the organization starts requiring two-factor authentication from
      # its members. Nil means it does not. Set to a future instant to give
      # members a grace period to enroll.
      add :mfa_required_at, :timestamptz
    end
  end
end
