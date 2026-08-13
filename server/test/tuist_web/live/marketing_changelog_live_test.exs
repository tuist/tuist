defmodule TuistWeb.Marketing.MarketingChangelogLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Changelog
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "GET /changelog" do
    test "renders the legacy design and stylesheet by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/changelog")

      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_changelog -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/changelog")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "renders the new design for a user actor-gated onto the page flag", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      user_id = user.id

      stub(FunWithFlags, :enabled?, fn _flag -> false end)

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_changelog, [for: %{id: ^user_id}] -> true
        _flag, _opts -> false
      end)

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/changelog")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end
  end

  describe "GET /changelog (new design)" do
    setup do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_changelog -> true
        _ -> false
      end)

      :ok
    end

    test "renders the first page of entries as a timeline", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/changelog")

      entries = find(html, ~s([data-part="timeline"] > [data-part="entry"]))
      dates = find(html, ~s([data-part="timeline"] > [data-part="date-cell"] [data-part="date"]))

      assert length(entries) == 10
      assert length(dates) == 10

      latest_entry = List.first(Changelog.get_entries())
      assert html =~ latest_entry.title
    end

    test "load more appends the next page of entries", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/changelog")

      html = lv |> element(~s([data-part="more"] button)) |> render_click()

      assert length(find(html, ~s([data-part="timeline"] > [data-part="entry"]))) == 20
      assert_patched(lv, "/changelog?page=2")
    end

    test "category pills filter the timeline", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/changelog")

      html =
        lv
        |> element(~s([data-part="categories"] > [data-part="category"]), "OSS")
        |> render_click()

      entries = find(html, ~s([data-part="timeline"] > [data-part="entry"]))

      assert entries != []

      oss_count = Enum.count(Changelog.get_entries(), &(&1.category == "OSS"))
      assert length(entries) == min(oss_count, 10)
      assert_patched(lv, "/changelog?category=OSS")
    end

    test "the category dropdown lists every category plus All", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/changelog")

      labels =
        html
        |> find(~s([data-part="item"]))
        |> Enum.map(&Floki.attribute(&1, "data-label"))

      assert ["All"] in labels
      assert ["Product"] in labels
    end
  end

  defp find(html, selector) do
    html |> Floki.parse_document!() |> Floki.find(selector)
  end
end
