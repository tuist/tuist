defmodule Atlas.Repo.Migrations.AddPriorityToPostmortemActionItems do
  use Ecto.Migration

  def change do
    alter table(:postmortem_action_items) do
      add :priority, :string, null: false, default: "medium"
    end

    create constraint(
             :postmortem_action_items,
             :postmortem_action_items_priority_check,
             check: "priority IN ('immediate', 'high', 'medium', 'low')"
           )
  end
end
