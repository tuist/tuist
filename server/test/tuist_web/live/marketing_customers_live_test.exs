defmodule TuistWeb.Marketing.MarketingCustomersLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /customers" do
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
