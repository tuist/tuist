defmodule Condukt.Tools.EditTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Tools.Edit

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "replaces exact text", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "edit.txt")
    File.write!(path, "Hello, World!")

    {:ok, result} =
      Edit.call(
        %{
          "path" => "edit.txt",
          "old_text" => "World",
          "new_text" => "Elixir"
        },
        context
      )

    assert String.contains?(result, "Successfully edited")
    assert File.read!(path) == "Hello, Elixir!"
  end

  test "returns error when text not found", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "edit.txt"), "Hello, World!")

    {:error, error} =
      Edit.call(
        %{
          "path" => "edit.txt",
          "old_text" => "Goodbye",
          "new_text" => "Hi"
        },
        context
      )

    assert String.contains?(error, "not found")
  end

  test "returns error when text appears multiple times", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "multi.txt")
    File.write!(path, "foo bar foo bar")

    {:error, error} =
      Edit.call(
        %{
          "path" => "multi.txt",
          "old_text" => "foo",
          "new_text" => "baz"
        },
        context
      )

    assert String.contains?(error, "Found 2 occurrences")
    assert File.read!(path) == "foo bar foo bar"
  end

  test "returns error when replacement produces identical content", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "same.txt")
    File.write!(path, "Hello, World!")

    {:error, error} =
      Edit.call(
        %{
          "path" => "same.txt",
          "old_text" => "World",
          "new_text" => "World"
        },
        context
      )

    assert String.contains?(error, "No changes made")
    assert File.read!(path) == "Hello, World!"
  end
end
