defmodule Atlas.Repo.Migrations.AddInmailOutreachAction do
  use Ecto.Migration

  def up do
    drop constraint(:outreach_recommendations, :outreach_recommendations_action_type_check)

    create constraint(:outreach_recommendations, :outreach_recommendations_action_type_check,
             check:
               "action_type IN ('research', 'wait', 'engage', 'connection_request', 'inmail', 'message', 'reply', 'follow_up', 'nurture', 'stop')"
           )

    drop constraint(:outreach_message_attempts, :outreach_message_attempts_kind_check)

    create constraint(:outreach_message_attempts, :outreach_message_attempts_kind_check,
             check: "message_kind IN ('inmail', 'message', 'reply', 'follow_up', 'manual')"
           )

    execute """
    UPDATE outreach_recommendations
    SET action_type = 'inmail', recommended_event_kind = 'message_sent'
    WHERE action_type = 'connection_request' AND draft_subject IS NOT NULL
    """
  end

  def down do
    execute """
    UPDATE outreach_recommendations
    SET action_type = 'connection_request', recommended_event_kind = 'connection_requested'
    WHERE action_type = 'inmail'
    """

    execute """
    UPDATE outreach_message_attempts
    SET message_kind = 'manual'
    WHERE message_kind = 'inmail'
    """

    drop constraint(:outreach_recommendations, :outreach_recommendations_action_type_check)

    create constraint(:outreach_recommendations, :outreach_recommendations_action_type_check,
             check:
               "action_type IN ('research', 'wait', 'engage', 'connection_request', 'message', 'reply', 'follow_up', 'nurture', 'stop')"
           )

    drop constraint(:outreach_message_attempts, :outreach_message_attempts_kind_check)

    create constraint(:outreach_message_attempts, :outreach_message_attempts_kind_check,
             check: "message_kind IN ('message', 'reply', 'follow_up', 'manual')"
           )
  end
end
