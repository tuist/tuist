defmodule Tuist.Repo.Migrations.AddCommandEventsStatus do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add(:status, :integer, default: 0, required: true)
      add(:error_message, :string)
    end
  end
end
