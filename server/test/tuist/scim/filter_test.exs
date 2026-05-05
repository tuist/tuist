defmodule Tuist.SCIM.FilterTest do
  use ExUnit.Case, async: true

  alias Tuist.SCIM.Filter

  describe "parse/1" do
    test "parses supported eq filters" do
      assert Filter.parse(~s(userName eq "alice@example.com")) == %{
               attribute: "userName",
               op: :eq,
               value: "alice@example.com"
             }
    end

    test "rejects unsupported filters" do
      assert Filter.parse(~s(userName co "alice")) == :error
      assert Filter.parse(~s(userName eq alice@example.com)) == :error
    end
  end

  describe "member_ids_from_path/1" do
    test "extracts member ids from supported SCIM value paths" do
      assert Filter.member_ids_from_path(~s(members[value eq "123"])) == ["123"]
      assert Filter.member_ids_from_path(~s( members [ value EQ "456" ] )) == ["456"]
    end

    test "returns an empty list for unsupported paths" do
      assert Filter.member_ids_from_path(nil) == []
      assert Filter.member_ids_from_path("members") == []
      assert Filter.member_ids_from_path(~s(userName eq "alice@example.com")) == []
    end
  end
end
