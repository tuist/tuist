defmodule Atlas.GTM.SocialPost do
  @moduledoc """
  A published post on a connected social account, with its latest metrics.
  Daily history lives in `Atlas.GTM.SocialPostSnapshot`.
  """

  use Atlas.Schema

  @formats ~w(text image video link quote)
  @metrics ~w(impressions likes reposts quotes replies bookmarks url_clicks profile_clicks)a

  def formats, do: @formats
  def metrics, do: @metrics

  schema "social_posts" do
    field :platform, :string
    field :external_id, :string
    field :account_id, :string
    field :account_handle, :string
    field :url, :string
    field :text, :string
    field :format, :string
    field :thread, :boolean, default: false
    field :posted_at, :utc_datetime

    field :impressions, :integer, default: 0
    field :likes, :integer, default: 0
    field :reposts, :integer, default: 0
    field :quotes, :integer, default: 0
    field :replies, :integer, default: 0
    field :bookmarks, :integer, default: 0
    field :url_clicks, :integer
    field :profile_clicks, :integer
    field :metrics_updated_at, :utc_datetime

    timestamps()
  end

  @doc "Public interactions: likes, reposts, quotes, replies and bookmarks."
  def engagements(post), do: post.likes + post.reposts + post.quotes + post.replies + post.bookmarks

  @doc "Engagements per impression, or nil before the post has impressions."
  def engagement_rate(%{impressions: impressions} = post) when impressions > 0, do: engagements(post) / impressions
  def engagement_rate(_post), do: nil
end
