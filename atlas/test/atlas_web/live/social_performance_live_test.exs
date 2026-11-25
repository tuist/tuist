defmodule AtlasWeb.SocialPerformanceLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.GTM.SocialPost
  alias Atlas.MCP.Tools.ListSocialPostPerformance

  defp insert_post!(attrs) do
    n = System.unique_integer([:positive])

    %SocialPost{
      platform: "x",
      external_id: "post#{n}",
      account_id: "acct",
      account_handle: "@perf#{n}",
      url: "https://x.com/perf/status/#{n}",
      text: "Post #{n}",
      format: "text",
      posted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metrics_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
    |> Ecto.Changeset.change(attrs)
    |> Atlas.Repo.insert!()
  end

  test "shows posts with their metrics and the per-format medians", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    video = insert_post!(%{format: "video", thread: true, impressions: 12_345, likes: 100, url_clicks: 9})

    old =
      insert_post!(%{posted_at: DateTime.add(DateTime.utc_now(), -60 * 86_400, :second) |> DateTime.truncate(:second)})

    {:ok, view, _html} = live(conn, ~p"/commercial/gtm/social/performance")

    assert view |> element("#social-posts-table", video.text) |> has_element?()
    assert view |> element("#social-posts-table", "12,345") |> has_element?()
    assert view |> element("#social-by-format", "video thread") |> has_element?()
    refute view |> element("#social-posts-table", old.text) |> has_element?()

    view |> element("#social-period-90") |> render_click()
    assert view |> element("#social-posts-table", old.text) |> has_element?()

    {:ok, payload} = ListSocialPostPerformance.execute(nil, %{"account" => video.account_handle})
    assert [%{format: "video", thread: true, impressions: 12_345, engagements: 100, url_clicks: 9}] = payload.posts
  end
end
