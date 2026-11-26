defmodule AtlasWeb.SocialPerformanceLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.GTM.SocialAccount
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

  test "lists Atlas-held accounts, splits brand from personal, and lets GTM writers disconnect", %{conn: conn} do
    {reader_conn, _} = log_in_user(conn)
    {writer_conn, writer} = log_in_user(conn, %{scopes: ["gtm:write"], name: "Connector"})

    account =
      %SocialAccount{platform: "x", external_id: "brand-acct", connected_by_id: writer.id}
      |> SocialAccount.changeset(%{handle: "@brandperf", kind: "brand", access_token: "secret-token"})
      |> Atlas.Repo.insert!()

    insert_post!(%{account_id: "brand-acct", account_handle: "@brandperf", impressions: 500})
    insert_post!(%{account_id: "gone", account_handle: "@gone"})

    {:ok, view, html} = live(reader_conn, ~p"/commercial/gtm/social/performance")
    refute html =~ "secret-token"
    assert view |> element("#social-accounts", "@brandperf") |> has_element?()
    assert view |> element("#social-accounts", "Connector") |> has_element?()
    assert view |> element("#social-by-kind", "Brand") |> has_element?()
    assert view |> element("#social-by-kind", "Disconnected") |> has_element?()
    refute has_element?(view, "#social-connect-brand")
    refute has_element?(view, "#social-disconnect-#{account.id}")

    {:ok, view, _html} = live(writer_conn, ~p"/commercial/gtm/social/performance")
    assert has_element?(view, "#social-connect-personal")
    view |> element("#social-disconnect-#{account.id}") |> render_click()
    refute view |> element("#social-accounts", "@brandperf") |> has_element?()
    refute Atlas.Repo.reload(account)
  end
end
