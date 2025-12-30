defmodule Tuist.Repo.Migrations.MakeInviteeEmailCaseInsensitive do
  use Ecto.Migration

  def up do
    alter table(:invitations) do
      modify :invitee_email, :citext
    end
  end

  def down do
    alter table(:invitations) do
      modify :invitee_email, :string
    end
  end
end
