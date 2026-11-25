defmodule Atlas.GTM.SocialPostSnapshot do
  @moduledoc """
  A social post's metrics as read on one day, so posts can be compared at the
  same age. X only returns click metrics for posts from the last 30 days, so
  these rows are the only record of them afterwards.
  """

  use Atlas.Schema

  alias Atlas.GTM.SocialPost

  schema "social_post_snapshots" do
    field :captured_on, :date
    field :impressions, :integer
    field :likes, :integer
    field :reposts, :integer
    field :quotes, :integer
    field :replies, :integer
    field :bookmarks, :integer
    field :url_clicks, :integer
    field :profile_clicks, :integer

    belongs_to :social_post, SocialPost

    timestamps()
  end
end
