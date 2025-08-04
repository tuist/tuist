defmodule TuistWeb.Controllers.ErrorHTMLTest do
  use ExUnit.Case, async: true
  use Gettext, backend: TuistWeb.Gettext

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
