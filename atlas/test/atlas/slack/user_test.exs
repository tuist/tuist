defmodule Atlas.Slack.UserTest do
  use ExUnit.Case, async: true

  alias Atlas.Slack.User

  describe "best_display_name/1" do
    test "prefers display_name when present" do
      user = %User{
        slack_user_id: "U1",
        name: "alice",
        real_name: "Alice Real",
        display_name: "alice.display"
      }

      assert User.best_display_name(user) == "alice.display"
    end

    test "falls back to real_name when display_name is missing" do
      user = %User{slack_user_id: "U1", name: "alice", real_name: "Alice Real"}
      assert User.best_display_name(user) == "Alice Real"
    end

    test "skips blank display_name" do
      user = %User{
        slack_user_id: "U1",
        name: "alice",
        real_name: "Alice Real",
        display_name: "  "
      }

      assert User.best_display_name(user) == "Alice Real"
    end

    test "falls back to name when real_name is missing" do
      user = %User{slack_user_id: "U1", name: "alice"}
      assert User.best_display_name(user) == "alice"
    end

    test "falls back to slack_user_id when nothing else is set" do
      user = %User{slack_user_id: "U1"}
      assert User.best_display_name(user) == "U1"
    end

    test "returns nil for non-struct input" do
      assert User.best_display_name(nil) == nil
    end
  end
end
