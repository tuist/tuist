defmodule Tuist.XcodeMirror.SessionTest do
  use ExUnit.Case, async: true

  alias Tuist.XcodeMirror.Session

  describe "load/1" do
    test "decodes a non-empty JSON object" do
      raw = ~s({"myacinfo": "DAW...", "dqsid": "abc"})

      assert {:ok, %{"myacinfo" => "DAW...", "dqsid" => "abc"}} =
               Session.load(raw: raw)
    end

    test "stringifies non-string values defensively" do
      raw = ~s({"myacinfo": "DAW", "session_id": 12345, "trusted": true})

      assert {:ok, cookies} = Session.load(raw: raw)
      assert cookies["session_id"] == "12345"
      assert cookies["trusted"] == "true"
    end

    test "missing env returns :missing" do
      assert {:error, :missing} = Session.load(raw: nil)
      assert {:error, :missing} = Session.load(raw: "")
    end

    test "empty JSON object returns :parse_error :empty_object" do
      assert {:error, {:parse_error, :empty_object}} = Session.load(raw: "{}")
    end

    test "garbage JSON returns :parse_error" do
      assert {:error, {:parse_error, _}} = Session.load(raw: "not json")
    end

    test "JSON array (wrong shape) returns :parse_error :empty_object" do
      assert {:error, {:parse_error, :empty_object}} = Session.load(raw: "[1, 2, 3]")
    end
  end

  describe "to_cookie_header/1" do
    test "joins key=value pairs with '; '" do
      header = Session.to_cookie_header(%{"a" => "1", "b" => "2"})

      # Map iteration order isn't guaranteed; just check the set of
      # pairs and the separator.
      pairs = String.split(header, "; ")
      assert Enum.sort(pairs) == ["a=1", "b=2"]
    end

    test "empty cookie map renders empty string" do
      assert Session.to_cookie_header(%{}) == ""
    end
  end
end
