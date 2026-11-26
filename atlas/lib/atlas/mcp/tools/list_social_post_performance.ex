defmodule Atlas.MCP.Tools.ListSocialPostPerformance do
  @moduledoc """
  Lists published posts from connected social accounts with their metrics, plus
  medians by account kind, account and format.
  """

  use Atlas.MCP.Tool,
    name: "list_social_post_performance",
    schema: %{
      "type" => "object",
      "properties" => %{
        "days" => %{"type" => "integer", "minimum" => 1, "maximum" => 365},
        "account" => %{"type" => "string", "description" => "Account handle such as @tuistdev."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["posts", "by_kind", "by_account", "by_format"],
      "properties" => %{
        "by_kind" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "group" => %{"type" => "string"},
              "posts" => %{"type" => "integer"},
              "median_impressions" => %{"type" => ["number", "null"]},
              "median_engagements" => %{"type" => ["number", "null"]},
              "median_engagement_rate" => %{"type" => ["number", "null"]}
            }
          }
        },
        "by_account" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "group" => %{"type" => "string"},
              "posts" => %{"type" => "integer"},
              "median_impressions" => %{"type" => ["number", "null"]},
              "median_engagements" => %{"type" => ["number", "null"]},
              "median_engagement_rate" => %{"type" => ["number", "null"]}
            }
          }
        },
        "by_format" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "group" => %{"type" => "string"},
              "posts" => %{"type" => "integer"},
              "median_impressions" => %{"type" => ["number", "null"]},
              "median_engagements" => %{"type" => ["number", "null"]},
              "median_engagement_rate" => %{"type" => ["number", "null"]}
            }
          }
        },
        "posts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "platform" => %{"type" => "string"},
              "account" => %{"type" => "string"},
              "kind" => %{"type" => ["string", "null"]},
              "url" => %{"type" => "string"},
              "text" => %{"type" => "string"},
              "format" => %{"type" => "string"},
              "thread" => %{"type" => "boolean"},
              "posted_at" => %{"type" => "string"},
              "impressions" => %{"type" => "integer"},
              "engagements" => %{"type" => "integer"},
              "engagement_rate" => %{"type" => ["number", "null"]},
              "url_clicks" => %{"type" => ["integer", "null"]},
              "profile_clicks" => %{"type" => ["integer", "null"]}
            }
          }
        }
      }
    }

  alias Atlas.GTM.SocialPost
  alias Atlas.GTM.SocialPosts

  @impl EMCP.Tool
  def description,
    do:
      "List posts from connected X accounts and LinkedIn pages in the last `days` days (default 30) with impressions, engagements, engagement rate and clicks, plus medians by account kind (brand or personal), by account and by format (text, image, video, link, quote, with or without a thread). Metrics refresh daily."

  def execute(_conn, args) do
    posts = SocialPosts.list_posts(days: args["days"] || 30, account: args["account"])
    summary = SocialPosts.summarize(posts)

    {:ok,
     %{
       by_kind: summary.by_kind,
       by_account: summary.by_account,
       by_format: summary.by_format,
       posts:
         Enum.map(posts, fn post ->
           %{
             platform: post.platform,
             account: post.account_handle,
             kind: post.kind,
             url: post.url,
             text: post.text,
             format: post.format,
             thread: post.thread,
             posted_at: DateTime.to_iso8601(post.posted_at),
             impressions: post.impressions,
             engagements: SocialPost.engagements(post),
             engagement_rate: SocialPost.engagement_rate(post),
             url_clicks: post.url_clicks,
             profile_clicks: post.profile_clicks
           }
         end)
     }}
  end
end
