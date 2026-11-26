defmodule Atlas.GTM.LinkedInTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialPost
  alias Atlas.GTM.SocialPosts

  setup do
    n = System.unique_integer([:positive])

    account =
      %SocialAccount{platform: "linkedin", external_id: "#{n}"}
      |> SocialAccount.changeset(%{
        handle: "Page #{n}",
        kind: "brand",
        access_token: "li-access",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })
      |> Repo.insert!()

    %{account: account, n: n}
  end

  defp ms(days_ago), do: DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.to_unix(:millisecond)

  test "syncs the page's recent posts with their lifetime statistics", %{account: account, n: n} do
    share = "urn:li:share:#{n}1"
    ugc = "urn:li:ugcPost:#{n}2"
    test = self()

    stub(Req, :request, fn opts ->
      assert opts[:auth] == {:bearer, "li-access"}
      assert {"x-restli-protocol-version", "2.0.0"} in opts[:headers]
      url = opts[:url]

      body =
        cond do
          url =~ "/rest/posts?" ->
            assert url =~ "author=urn%3Ali%3Aorganization%3A#{n}"

            %{
              "elements" => [
                %{
                  "id" => share,
                  "commentary" => "Runners are here",
                  "publishedAt" => ms(1),
                  "lifecycleState" => "PUBLISHED",
                  "content" => %{"media" => %{"id" => "urn:li:video:abc"}}
                },
                %{
                  "id" => ugc,
                  "commentary" => "Read the post",
                  "publishedAt" => ms(3),
                  "lifecycleState" => "PUBLISHED",
                  "content" => %{"article" => %{"source" => "https://tuist.dev"}}
                },
                # Older than the sync window: not stored.
                %{"id" => "urn:li:share:#{n}3", "publishedAt" => ms(30), "lifecycleState" => "PUBLISHED"}
              ]
            }

          url =~ "/rest/organizationalEntityShareStatistics?" ->
            send(test, {:stats_url, url})

            # LinkedIn leaves out posts with no impressions or actions.
            %{
              "elements" => [
                %{
                  "share" => share,
                  "totalShareStatistics" => %{
                    "impressionCount" => 900,
                    "likeCount" => 20,
                    "commentCount" => 3,
                    "shareCount" => 2,
                    "clickCount" => 15
                  }
                }
              ]
            }
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end)

    assert {:ok, 2} = SocialPosts.sync_account(account)

    assert_received {:stats_url, stats_url}
    assert stats_url =~ "shares=List(urn%3Ali%3Ashare%3A#{n}1)"
    assert stats_url =~ "ugcPosts=List(urn%3Ali%3AugcPost%3A#{n}2)"

    video = Repo.get_by!(SocialPost, platform: "linkedin", external_id: share)

    assert %{format: "video", impressions: 900, likes: 20, replies: 3, reposts: 2, url_clicks: 15} = video
    assert video.account_handle == account.handle
    assert video.url == "https://www.linkedin.com/feed/update/#{share}/"
    assert SocialPost.engagements(video) == 25

    assert %{format: "link", impressions: 0} = Repo.get_by!(SocialPost, platform: "linkedin", external_id: ugc)

    assert [%{kind: "brand"}, %{kind: "brand"}] = SocialPosts.list_posts(account: account.handle)
  end

  test "keeps LinkedIn post text for six months and its numbers for a year; X posts are untouched", %{n: n} do
    insert = fn platform, days_ago ->
      %SocialPost{
        platform: platform,
        external_id: "#{platform}-#{n}-#{days_ago}",
        account_id: "acct",
        account_handle: "Page",
        url: "https://example.com",
        text: "Post text",
        format: "text",
        posted_at: DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second),
        metrics_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()
    end

    recent = insert.("linkedin", 100)
    half_year = insert.("linkedin", 200)
    old = insert.("linkedin", 400)
    old_x = insert.("x", 400)

    SocialPosts.prune_linkedin()

    assert Repo.reload!(recent).text == "Post text"
    assert Repo.reload!(half_year).text == ""
    refute Repo.reload(old)
    assert Repo.reload!(old_x).text == "Post text"
  end
end
