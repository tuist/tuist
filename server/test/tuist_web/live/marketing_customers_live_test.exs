defmodule TuistWeb.Marketing.MarketingCustomersLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "GET /customers" do
    test "renders the legacy design and stylesheet by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/customers")

      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_customers -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/customers")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "renders the new design for a user actor-gated onto the page flag", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      user_id = user.id

      stub(FunWithFlags, :enabled?, fn _flag -> false end)

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_customers, [for: %{id: ^user_id}] -> true
        _flag, _opts -> false
      end)

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/customers")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "renders the localized Hyperconnect title for Korean visitors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/ko/customers")

      assert html =~ "Hyperconnect가 Tuist로 멀티 서비스 파이프라인을 최적화한 방법"
    end

    test "renders the English Hyperconnect title by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/customers")

      assert html =~ "Hyperconnect optimized its multi-service pipeline with Tuist"
    end

    test "links external case studies to their source article", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/customers")

      assert html =~ "Scaling iOS application development with Tuist"

      assert html =~
               ~s(href="https://deliveryhero.jobs/blog/scaling-ios-application-development-with-tuist/")
    end
  end
end
