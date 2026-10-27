defmodule Slack.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations) do
      add :email, :string, null: false
      add :reason, :text, null: false
      add :code_of_conduct_accepted, :boolean, null: false, default: false
      add :status, :string, null: false, default: "unconfirmed"
      add :confirmation_token, :string, null: false
      add :confirmed_at, :utc_datetime
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:email])
    create unique_index(:invitations, [:confirmation_token])
    create index(:invitations, [:status])
  end
end
