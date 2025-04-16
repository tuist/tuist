defmodule TuistWeb.Controllers.ErrorHTMLTest do
  use ExUnit.Case, async: true
  use Gettext, backend: TuistWeb.Gettext

  setup do
    FunWithFlags |> Mimic.stub(:enabled?, fn _ -> true end)

    :ok
  end

  test "render 401.html" do
    # Given/When
    html =
      TuistWeb.ErrorHTML.render("401.html", %{})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert not is_nil(
             Floki.find(html, "title:fl-contains('#{gettext("Unauthorized")} · Tuist')")
             |> List.first()
           )
  end

  test "render 404.html" do
    # Given/When
    html =
      TuistWeb.ErrorHTML.render("404.html", %{reason: %{message: "reason"}})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert not is_nil(
             Floki.find(html, "title:fl-contains('#{gettext("Not found")} · Tuist')")
             |> List.first()
           )
  end

  test "render 429.html" do
    # Given/When
    html =
      TuistWeb.ErrorHTML.render("429.html", %{reason: %{message: "reason"}})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert not is_nil(
             Floki.find(html, "title:fl-contains('#{gettext("Too many requests")} · Tuist')")
             |> List.first()
           )
  end

  test "render 500.html" do
    # Given/When
    html =
      TuistWeb.ErrorHTML.render("500.html", %{reason: %{message: "reason"}})
      |> Phoenix.LiveViewTest.rendered_to_string()
      |> Floki.parse_document!()

    # Then
    assert not is_nil(
             Floki.find(html, "title:fl-contains('#{gettext("Server error")} · Tuist')")
             |> List.first()
           )
  end
end
