defmodule TuistWeb.Controllers.ErrorHTMLTest do
  use ExUnit.Case, async: true
  use Gettext, backend: TuistWeb.Gettext
  use Mimic

  import Phoenix.ConnTest, only: [build_conn: 0]

  test "render 401.html" do
    # Given/When
    html =
      "401.html"
      |> TuistWeb.ErrorHTML.render(%{})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert html
           |> Floki.find("title:fl-contains('#{gettext("Unauthorized")} · Tuist')")
           |> List.first()
  end

  test "render 404.html" do
    # Given/When
    html =
      "404.html"
      |> TuistWeb.ErrorHTML.render(%{reason: %{message: "reason"}})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert html
           |> Floki.find("title:fl-contains('#{gettext("Not found")} · Tuist')")
           |> List.first()
  end

  describe "render 404.html with the redesigned page flag" do
    setup do
      # The redesigned footer asks for ongoing incidents; keep that off the
      # network.
      stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, _fun -> false end)
      :ok
    end

    defp render_not_found(conn, flag_enabled) do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_not_found -> flag_enabled
        _flag -> false
      end)

      "404.html"
      |> TuistWeb.ErrorHTML.render(%{conn: conn, status: 404, kind: :error, reason: nil, stack: []})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()
    end

    test "renders the marketing 404 for an unrouted URL when the page flag is on" do
      conn = %{build_conn() | request_path: "/does-not-exist"}

      html = render_not_found(conn, true)

      assert html |> Floki.find("#marketing-not-found") |> List.first()

      assert html
             |> Floki.find("#marketing-not-found-hero[phx-hook='NotFoundOutline'] h1#marketing-not-found-title")
             |> List.first()

      assert html
             |> Floki.find("#marketing-not-found-hero button[data-part='eyebrow'][aria-pressed='false']")
             |> List.first()

      assert html |> Floki.find("#marketing-not-found-hero [data-part='figure']") |> Floki.text() |> String.trim() ==
               "404"

      assert html |> Floki.find("#marketing-navbar") |> List.first()
      assert html |> Floki.find("link[href='/marketing/assets/bundle-new.css']") |> List.first()
      assert html |> Floki.find("title:fl-contains('Page not found · Tuist')") |> List.first()
      assert html |> Floki.find("link[rel='canonical'][href$='/does-not-exist']") |> List.first()
    end

    test "renders the marketing 404 for a request that went through the marketing pipeline" do
      conn =
        build_conn()
        |> Map.put(:request_path, "/blog/missing-post")
        |> Plug.Conn.put_private(:phoenix_pipelines, [:open_api, :browser_marketing, :assign_current_path])

      html = render_not_found(conn, true)

      assert html |> Floki.find("#marketing-not-found") |> List.first()
    end

    test "keeps the dashboard error page while the page flag is off" do
      conn = %{build_conn() | request_path: "/does-not-exist"}

      html = render_not_found(conn, false)

      assert html |> Floki.find("#error-page") |> List.first()
      refute html |> Floki.find("#marketing-not-found") |> List.first()
    end

    test "renders the marketing 404 for dashboard requests too (one host, one not-found page)" do
      conn =
        build_conn()
        |> Map.put(:request_path, "/r")
        |> Plug.Conn.put_private(:phoenix_pipelines, [:browser_app])

      html = render_not_found(conn, true)

      assert html |> Floki.find("#marketing-not-found") |> List.first()
      refute html |> Floki.find("#error-page") |> List.first()
    end
  end

  test "render 429.html" do
    # Given/When
    html =
      "429.html"
      |> TuistWeb.ErrorHTML.render(%{reason: %{message: "reason"}})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert html
           |> Floki.find("title:fl-contains('#{gettext("Too many requests")} · Tuist')")
           |> List.first()
  end

  test "render 500.html" do
    # Given/When
    html =
      "500.html"
      |> TuistWeb.ErrorHTML.render(%{reason: %{message: "reason"}})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert html
           |> Floki.find("title:fl-contains('#{gettext("Server error")} · Tuist')")
           |> List.first()
  end
end
