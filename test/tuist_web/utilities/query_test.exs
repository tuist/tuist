defmodule TuistWeb.Utilities.QueryTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Utilities.Query

  describe "put/3" do
    test "puts query parameter in encoded query string" do
      assert Query.put("foo=bar", "baz", "qux") == "baz=qux&foo=bar"
    end

    test "puts existing query parameter in encoded query string" do
      result = Query.put("foo=bar&baz=old", "baz", "new")
      assert result =~ "foo=bar"
      assert result =~ "baz=new"
      refute result =~ "baz=old"
    end

    test "puts query parameter in decoded map" do
      result = Query.put(%{"foo" => "bar"}, "baz", "qux")
      assert result =~ "foo=bar"
      assert result =~ "baz=qux"
    end

    test "handles empty query string" do
      assert Query.put("", "foo", "bar") == "foo=bar"
    end

    test "handles empty map" do
      assert Query.put(%{}, "foo", "bar") == "foo=bar"
    end

    test "handles nil query string" do
      assert Query.put(nil, "foo", "bar") == "foo=bar"
    end
  end

  describe "drop/2" do
    test "drops query parameter from encoded query string" do
      result = Query.drop("foo=bar&baz=qux", "baz")
      assert result == "foo=bar"
    end

    test "drops query parameter from decoded map" do
      result = Query.drop(%{"foo" => "bar", "baz" => "qux"}, "baz")
      assert result == "foo=bar"
    end

    test "handles dropping non-existent parameter" do
      assert Query.drop("foo=bar", "nonexistent") == "foo=bar"
    end

    test "handles empty query string" do
      assert Query.drop("", "foo") == ""
    end

    test "handles empty map" do
      assert Query.drop(%{}, "foo") == ""
    end

    test "handles nil query string" do
      assert Query.drop(nil, "foo") == ""
    end

    test "drops all parameters results in empty string" do
      assert Query.drop("foo=bar", "foo") == ""
    end
  end
end
