defmodule Atlas.Repo.Migrations.AddSenderAndMeetingsToOutreach do
  use Ecto.Migration

  # Outreach is sent by teammates from their own LinkedIn or X accounts. The
  # sender is who sent the message; until now only who logged it was known, so
  # existing attempts take the author of their sent event.
  def up do
    alter table(:outreach_message_attempts) do
      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:outreach_message_attempts, [:sender_id])

    execute("""
    UPDATE outreach_message_attempts AS attempt
    SET sender_id = event.author_id
    FROM account_events AS event
    WHERE event.id = attempt.sent_event_id AND attempt.sender_id IS NULL
    """)

    drop constraint(:outreach_message_attempts, :outreach_message_attempts_channel_check)
    drop constraint(:outreach_message_attempts, :outreach_message_attempts_outcome_check)

    create constraint(:outreach_message_attempts, :outreach_message_attempts_channel_check,
             check: "channel IN ('linkedin', 'x')"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_outcome_check,
             check:
               "outcome IN ('pending', 'replied', 'positive_reply', 'meeting_booked', 'objection', 'not_interested', 'no_reply')"
           )
  end

  def down do
    execute(
      "UPDATE outreach_message_attempts SET outcome = 'positive_reply' WHERE outcome = 'meeting_booked'"
    )

    execute("DELETE FROM outreach_message_attempts WHERE channel = 'x'")

    drop constraint(:outreach_message_attempts, :outreach_message_attempts_channel_check)
    drop constraint(:outreach_message_attempts, :outreach_message_attempts_outcome_check)

    create constraint(:outreach_message_attempts, :outreach_message_attempts_channel_check,
             check: "channel IN ('linkedin')"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_outcome_check,
             check:
               "outcome IN ('pending', 'replied', 'positive_reply', 'objection', 'not_interested', 'no_reply')"
           )

    alter table(:outreach_message_attempts) do
      remove :sender_id
    end
  end
end
