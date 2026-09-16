defmodule AtlasWeb.Utilities.QueryTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.Utilities.Query

  doctest Query

  describe "parse_page/1" do
    test "returns positive integer pages" do
      assert Query.parse_page(2) == 2
      assert Query.parse_page("3") == 3
    end

    test "defaults invalid pages to 1" do
      assert Query.parse_page(nil) == 1
      assert Query.parse_page(0) == 1
      assert Query.parse_page("-1") == 1
      assert Query.parse_page("1abc") == 1
    end
  end

  describe "put_present/3" do
    test "keeps nil and blank values out of query params" do
      assert %{} |> Query.put_present("q", nil) |> Query.put_present("sort", "") == %{}
      assert Query.put_present(%{}, "q", "atlas") == %{"q" => "atlas"}
    end
  end

  describe "present_string/1" do
    test "trims strings and returns nil for blanks" do
      assert Query.present_string(" atlas ") == "atlas"
      assert Query.present_string(" ") == nil
      assert Query.present_string(nil) == nil
    end
  end

  describe "copy_legacy_search/3" do
    test "copies trimmed legacy search only when the current key is blank" do
      assert Query.copy_legacy_search(%{"query" => " atlas "}, "query", "q") == %{
               "query" => " atlas ",
               "q" => "atlas"
             }

      assert Query.copy_legacy_search(%{"query" => "legacy", "q" => "current"}, "query", "q") == %{
               "query" => "legacy",
               "q" => "current"
             }
    end
  end

  describe "copy_legacy_filters/3" do
    test "copies legacy filters into Noora query params without overwriting current filters" do
      params =
        Query.copy_legacy_filters(
          %{"provider" => " qonto ", "filter_currency_val" => "EUR"},
          ~w(provider currency)
        )

      assert params["filter_provider_op"] == "=="
      assert params["filter_provider_val"] == "qonto"
      assert params["filter_currency_val"] == "EUR"
      refute Map.has_key?(params, "filter_currency_op")
    end
  end
end
