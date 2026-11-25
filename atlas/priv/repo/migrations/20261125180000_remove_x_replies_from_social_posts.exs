defmodule Atlas.Repo.Migrations.RemoveXRepliesFromSocialPosts do
  use Ecto.Migration

  # The first sync stored three @tuistdev replies to other accounts as posts,
  # because X omitted `in_reply_to_user_id` on them. The sync now also treats
  # `replied_to` references as replies, but these are past its 14-day window.
  # Their snapshots are removed by the foreign key's cascade.
  def up do
    execute("""
    DELETE FROM social_posts
    WHERE platform = 'x'
      AND external_id IN ('2118391636493263095', '2114645501429846209', '2114644577177174381')
    """)
  end

  def down, do: :ok
end
