defmodule Tuist.Repo.Migrations.AddTrialEndToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add(:trial_end, :utc_datetime)
    end
  end
end
