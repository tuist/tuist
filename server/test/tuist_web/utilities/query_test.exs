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

  describe "has_pagination_params?/1" do
    test "returns false for query without pagination params" do
      assert Query.has_pagination_params?("foo=bar") == false
      assert Query.has_pagination_params?("name=test&status=active") == false
    end

    test "returns true for query with 'after' cursor param" do
      assert Query.has_pagination_params?("foo=bar&after=cursor123") == true
      assert Query.has_pagination_params?("after=xyz") == true
    end

    test "returns true for query with 'before' cursor param" do
      assert Query.has_pagination_params?("foo=bar&before=cursor123") == true
      assert Query.has_pagination_params?("before=xyz") == true
    end

    test "returns true for query with 'limit' param" do
      assert Query.has_pagination_params?("foo=bar&limit=10") == true
      assert Query.has_pagination_params?("limit=50") == true
    end

    test "returns true for query with 'offset' param" do
      assert Query.has_pagination_params?("foo=bar&offset=20") == true
      assert Query.has_pagination_params?("offset=100") == true
    end

    test "returns true for query with multiple pagination params" do
      assert Query.has_pagination_params?("limit=10&offset=20") == true
      assert Query.has_pagination_params?("before=abc&after=xyz") == true
      assert Query.has_pagination_params?("foo=bar&limit=10&offset=0") == true
    end

    test "works with decoded map - no pagination params" do
      assert Query.has_pagination_params?(%{"foo" => "bar"}) == false
      assert Query.has_pagination_params?(%{"name" => "test", "status" => "active"}) == false
    end

    test "works with decoded map - cursor pagination params" do
      assert Query.has_pagination_params?(%{"foo" => "bar", "after" => "cursor123"}) == true
      assert Query.has_pagination_params?(%{"before" => "xyz"}) == true
    end

    test "works with decoded map - limit/offset pagination params" do
      assert Query.has_pagination_params?(%{"foo" => "bar", "limit" => "10"}) == true
      assert Query.has_pagination_params?(%{"offset" => "20"}) == true
    end

    test "handles empty query string" do
      assert Query.has_pagination_params?("") == false
    end

    test "handles empty map" do
      assert Query.has_pagination_params?(%{}) == false
    end

    test "handles nil query" do
      assert Query.has_pagination_params?(nil) == false
    end

    test "handles encoded special characters in query" do
      assert Query.has_pagination_params?("foo=bar%20baz&after=cursor%2B123") == true
      assert Query.has_pagination_params?("name=%E2%9C%93&limit=10") == true
    end
  end

  describe "clear_cursors/1" do
    test "removes both after and before cursor params" do
      params = %{"foo" => "bar", "after" => "cursor123", "before" => "cursor456"}
      result = Query.clear_cursors(params)
      assert result == %{"foo" => "bar"}
      refute Map.has_key?(result, "after")
      refute Map.has_key?(result, "before")
    end

    test "removes only after cursor param" do
      params = %{"foo" => "bar", "after" => "cursor123"}
      result = Query.clear_cursors(params)
      assert result == %{"foo" => "bar"}
      refute Map.has_key?(result, "after")
    end

    test "removes only before cursor param" do
      params = %{"foo" => "bar", "before" => "cursor123"}
      result = Query.clear_cursors(params)
      assert result == %{"foo" => "bar"}
      refute Map.has_key?(result, "before")
    end

    test "handles params with no cursor params" do
      params = %{"foo" => "bar", "baz" => "qux"}
      result = Query.clear_cursors(params)
      assert result == %{"foo" => "bar", "baz" => "qux"}
    end

    test "handles empty params" do
      result = Query.clear_cursors(%{})
      assert result == %{}
    end
  end

  describe "has_cursor?/1" do
    test "returns true when after param present" do
      assert Query.has_cursor?(%{"after" => "cursor123"}) == true
      assert Query.has_cursor?(%{"foo" => "bar", "after" => "cursor123"}) == true
    end

    test "returns true when before param present" do
      assert Query.has_cursor?(%{"before" => "cursor123"}) == true
      assert Query.has_cursor?(%{"foo" => "bar", "before" => "cursor123"}) == true
    end

    test "returns true when both params present" do
      assert Query.has_cursor?(%{"after" => "abc", "before" => "xyz"}) == true
    end

    test "returns false when no cursor params present" do
      assert Query.has_cursor?(%{"foo" => "bar"}) == false
      assert Query.has_cursor?(%{"limit" => "10", "offset" => "20"}) == false
    end

    test "returns false for empty params" do
      assert Query.has_cursor?(%{}) == false
    end
  end

  describe "has_explicit_sort_params?/2" do
    test "returns true for hyphen-separated sort params with sort_by" do
      assert Query.has_explicit_sort_params?(%{"build-runs-sort-by" => "duration"}, :"build-runs") ==
               true

      assert Query.has_explicit_sort_params?(%{"bundles-sort-by" => "install-size"}, :bundles) ==
               true
    end

    test "returns true for hyphen-separated sort params with sort_order" do
      assert Query.has_explicit_sort_params?(%{"build-runs-sort-order" => "asc"}, :"build-runs") ==
               true

      assert Query.has_explicit_sort_params?(%{"bundles-sort-order" => "desc"}, :bundles) == true
    end

    test "returns true for hyphen-separated sort params with both" do
      params = %{"build-runs-sort-by" => "duration", "build-runs-sort-order" => "asc"}
      assert Query.has_explicit_sort_params?(params, :"build-runs") == true
    end

    test "returns true for underscore-separated sort params with sort_by" do
      assert Query.has_explicit_sort_params?(%{"generate_runs_sort_by" => "ran_at"}, :generate_runs) ==
               true

      assert Query.has_explicit_sort_params?(%{"test_runs_sort_by" => "created_at"}, :test_runs) ==
               true
    end

    test "returns true for underscore-separated sort params with sort_order" do
      assert Query.has_explicit_sort_params?(%{"generate_runs_sort_order" => "asc"}, :generate_runs) ==
               true
    end

    test "returns true for underscore-separated sort params with both" do
      params = %{"generate_runs_sort_by" => "ran_at", "generate_runs_sort_order" => "desc"}
      assert Query.has_explicit_sort_params?(params, :generate_runs) == true
    end

    test "returns false when no sort params present" do
      assert Query.has_explicit_sort_params?(%{"foo" => "bar"}, :"build-runs") == false
      assert Query.has_explicit_sort_params?(%{"after" => "cursor123"}, :bundles) == false
      assert Query.has_explicit_sort_params?(%{}, :generate_runs) == false
    end

    test "returns false when params have wrong prefix" do
      params = %{"build-runs-sort-by" => "duration"}
      assert Query.has_explicit_sort_params?(params, :bundles) == false
      assert Query.has_explicit_sort_params?(params, :generate_runs) == false
    end
  end

  describe "sort_changed?/4" do
    test "returns true when sort_by changed" do
      socket = %{assigns: %{build_runs_sort_by: "duration", build_runs_sort_order: "desc"}}
      assert Query.sort_changed?(socket, "ran_at", "desc", :build_runs) == true
    end

    test "returns true when sort_order changed" do
      socket = %{assigns: %{build_runs_sort_by: "duration", build_runs_sort_order: "desc"}}
      assert Query.sort_changed?(socket, "duration", "asc", :build_runs) == true
    end

    test "returns true when both sort_by and sort_order changed" do
      socket = %{assigns: %{bundles_sort_by: "created-at", bundles_sort_order: "desc"}}
      assert Query.sort_changed?(socket, "install-size", "asc", :bundles) == true
    end

    test "returns false when sort params unchanged" do
      socket = %{assigns: %{generate_runs_sort_by: "ran_at", generate_runs_sort_order: "desc"}}
      assert Query.sort_changed?(socket, "ran_at", "desc", :generate_runs) == false
    end

    test "returns false when socket has no previous sort assigns" do
      socket = %{assigns: %{}}
      assert Query.sort_changed?(socket, "duration", "asc", :build_runs) == false
    end

    test "returns false when socket has other assigns but not sort assigns" do
      socket = %{assigns: %{project_id: 123, user_id: 456}}
      assert Query.sort_changed?(socket, "duration", "asc", :build_runs) == false
    end

    test "handles different prefix formats" do
      socket_hyphen = %{assigns: %{build_runs_sort_by: "duration", build_runs_sort_order: "desc"}}
      assert Query.sort_changed?(socket_hyphen, "ran_at", "asc", :build_runs) == true

      socket_underscore = %{
        assigns: %{generate_runs_sort_by: "ran_at", generate_runs_sort_order: "desc"}
      }

      assert Query.sort_changed?(socket_underscore, "duration", "asc", :generate_runs) == true
    end
  end
end
