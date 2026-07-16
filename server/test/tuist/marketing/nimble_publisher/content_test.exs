defmodule Tuist.Marketing.NimblePublisher.ContentTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Blog

  test "tracks production content files for recompilation" do
    assert function_exported?(Blog, :__mix_recompile__?, 0)
    refute Blog.__mix_recompile__?()

    external_resources = :attributes |> Blog.module_info() |> Keyword.get_values(:external_resource) |> List.flatten()

    assert Enum.any?(external_resources, &String.ends_with?(&1, ".md"))
  end
end
