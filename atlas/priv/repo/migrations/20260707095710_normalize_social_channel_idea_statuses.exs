defmodule Atlas.Repo.Migrations.NormalizeSocialChannelIdeaStatuses do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE social_channel_ideas
    SET status = CASE
      WHEN status = 'shared' THEN 'published'
      ELSE 'idea'
    END
    WHERE status NOT IN ('idea', 'published')
    """)

    create constraint(:social_channel_ideas, :social_channel_ideas_status_check,
             check: "status IN ('idea', 'published')"
           )
  end

  def down do
    drop constraint(:social_channel_ideas, :social_channel_ideas_status_check)
  end
end
