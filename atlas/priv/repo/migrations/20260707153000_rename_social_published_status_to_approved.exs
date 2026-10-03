defmodule Atlas.Repo.Migrations.RenameSocialPublishedStatusToApproved do
  use Ecto.Migration

  def up do
    # A social idea's status and a revision's promoted state are an editorial
    # "approved" (this is the copy to post), not a "published" that went live.
    drop constraint(:social_channel_ideas, :social_channel_ideas_status_check)

    drop unique_index(:social_post_revisions, [:social_channel_idea_id],
           name: :social_post_revisions_one_published_per_idea_index
         )

    execute("UPDATE social_channel_ideas SET status = 'approved' WHERE status = 'published'")
    execute("UPDATE social_post_revisions SET status = 'approved' WHERE status = 'published'")

    create constraint(:social_channel_ideas, :social_channel_ideas_status_check,
             check: "status IN ('idea', 'approved')"
           )

    create unique_index(:social_post_revisions, [:social_channel_idea_id],
             where: "status = 'approved'",
             name: :social_post_revisions_one_approved_per_idea_index
           )
  end

  def down do
    drop constraint(:social_channel_ideas, :social_channel_ideas_status_check)

    drop unique_index(:social_post_revisions, [:social_channel_idea_id],
           name: :social_post_revisions_one_approved_per_idea_index
         )

    execute("UPDATE social_channel_ideas SET status = 'published' WHERE status = 'approved'")
    execute("UPDATE social_post_revisions SET status = 'published' WHERE status = 'approved'")

    create constraint(:social_channel_ideas, :social_channel_ideas_status_check,
             check: "status IN ('idea', 'published')"
           )

    create unique_index(:social_post_revisions, [:social_channel_idea_id],
             where: "status = 'published'",
             name: :social_post_revisions_one_published_per_idea_index
           )
  end
end
