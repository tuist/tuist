defmodule TuistEx.Analytics.ActorTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Actor

  defp options(env), do: [environment: &Map.get(env, &1), project_config: []]

  test "automatically reports an environment user with an explicit override and opt-out" do
    assert Actor.identifier(options(%{"USER" => "developer"})) == "developer"
    assert Actor.identifier(options(%{"USERNAME" => "windows-user"})) == "windows-user"

    assert Actor.identifier(options(%{"USER" => "developer", "TUIST_ACTOR_ID" => "employee-123"})) ==
             "employee-123"

    assert Actor.identifier(options(%{"USER" => "developer", "TUIST_ACTOR_ID" => ""})) == nil
  end

  test "environment overrides runtime options, which override project config and automatic detection" do
    options = [
      environment: &Map.get(%{"USER" => "developer"}, &1),
      actor_id: "runtime",
      project_config: [actor_id: "project"]
    ]

    assert Actor.identifier(options) == "runtime"
    assert Actor.identifier(Keyword.delete(options, :actor_id)) == "project"

    assert Actor.identifier(
             Keyword.put(options, :environment, &Map.get(%{"TUIST_ACTOR_ID" => "env"}, &1))
           ) == "env"
  end

  test "rejects unsafe, empty, invalid and oversized identifiers without falling back" do
    for id <- ["", "a\r\nb", "a b", "é", <<255>>, String.duplicate("a", 129)] do
      assert Actor.headers(options(%{"TUIST_ACTOR_ID" => id, "USER" => "developer"})) == []
    end

    for id <- [false, 123, [], %{}] do
      assert Actor.headers(Keyword.put(options(%{"USER" => "developer"}), :actor_id, id)) == []

      assert Actor.headers(
               Keyword.put(options(%{"USER" => "developer"}), :project_config, actor_id: id)
             ) == []
    end

    assert Actor.headers(options(%{"TUIST_ACTOR_ID" => "employee-123"})) == [
             {"x-tuist-actor-id", "employee-123"}
           ]
  end
end
