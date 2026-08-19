defmodule TuistWeb.Marketing.MarketingCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "GET /cache" do
    test "renders the legacy design and stylesheet by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/cache")

      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_cache -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/cache")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
      assert html =~ "Never build the"
      assert html =~ "Everything you&#39;d want from a cache"
    end

    test "renders the new design for a user actor-gated onto the page flag", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      user_id = user.id

      stub(FunWithFlags, :enabled?, fn _flag -> false end)

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_cache, [for: %{id: ^user_id}] -> true
        _flag, _opts -> false
      end)

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/cache")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end
  end
end
