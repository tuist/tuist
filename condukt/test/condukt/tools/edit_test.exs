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

    assert String.starts_with?(result, "Successfully replaced 1 block(s) in edit.txt.")
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

    assert String.contains?(error, "Could not find the exact text")
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

  test "applies several edits matched against the original", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "multi.ex")
    File.write!(path, "a = 1\nb = 2\nc = 3\n")

    edits = [%{"oldText" => "c = 3", "newText" => "c = 30"}, %{"oldText" => "a = 1", "newText" => "a = 10\nz = 0"}]
    assert {:ok, result} = Edit.call(%{"path" => "multi.ex", "edits" => edits}, context)

    assert File.read!(path) == "a = 10\nz = 0\nb = 2\nc = 30\n"
    assert result =~ "Successfully replaced 2 block(s)"
    assert result =~ "-1 a = 1\n+1 a = 10\n+2 z = 0"
    assert result =~ "-3 c = 3\n+4 c = 30"
  end

  test "accepts edits sent as a JSON string", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "json.txt")
    File.write!(path, "x")

    assert {:ok, _} = Edit.call(%{"path" => "json.txt", "edits" => ~s([{"oldText":"x","newText":"y"}])}, context)
    assert File.read!(path) == "y"
  end

  test "refuses overlapping edits and leaves the file alone", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "o.txt")
    File.write!(path, "abcdef")

    edits = [%{"oldText" => "abcd", "newText" => "1"}, %{"oldText" => "cdef", "newText" => "2"}]
    assert {:error, error} = Edit.call(%{"path" => "o.txt", "edits" => edits}, context)
    assert error =~ "edits[0] and edits[1] overlap"
    assert File.read!(path) == "abcdef"
  end

  test "keeps CRLF line endings and a byte order mark", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "crlf.txt")
    File.write!(path, <<0xEF, 0xBB, 0xBF>> <> "one\r\ntwo\r\nthree\r\n")

    edits = [%{"oldText" => "two\nthree", "newText" => "2\n3\n3.5"}]
    assert {:ok, _} = Edit.call(%{"path" => "crlf.txt", "edits" => edits}, context)
    assert File.read!(path) == <<0xEF, 0xBB, 0xBF>> <> "one\r\n2\r\n3\r\n3.5\r\n"
  end

  test "matches smart quotes and trailing whitespace fuzzily, rewriting only touched lines",
       %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "fuzzy.txt")
    File.write!(path, "keep \u201Cthis\u201D   \nsay \u201Chi\u201D  \nend")

    edits = [%{"oldText" => ~s(say "hi"), "newText" => ~s(say "bye")}]
    assert {:ok, _} = Edit.call(%{"path" => "fuzzy.txt", "edits" => edits}, context)
    assert File.read!(path) == "keep \u201Cthis\u201D   \nsay \"bye\"\nend"
  end

  test "counts duplicates across fuzzy forms", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "dup.txt"), "it's\nit\u2019s")

    assert {:error, error} =
             Edit.call(%{"path" => "dup.txt", "edits" => [%{"oldText" => "it's", "newText" => "x"}]}, context)

    assert error =~ "Found 2 occurrences"
  end

  test "edits files that are not UTF-8 by exact match", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "latin1.txt")
    File.write!(path, <<"caf", 0xE9, " ok\n">>)

    assert {:ok, _} =
             Edit.call(%{"path" => "latin1.txt", "edits" => [%{"oldText" => "ok", "newText" => "fine"}]}, context)

    assert File.read!(path) == <<"caf", 0xE9, " fine\n">>

    assert {:error, error} =
             Edit.call(%{"path" => "latin1.txt", "edits" => [%{"oldText" => "fine ", "newText" => "x"}]}, context)

    assert error =~ "Could not find the exact text"
  end

  test "refuses empty oldText and counts whitespace-only oldText exactly", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "ws.txt")
    File.write!(path, "a  b  c")

    assert {:error, "oldText must not be empty in ws.txt."} =
             Edit.call(%{"path" => "ws.txt", "edits" => [%{"oldText" => "", "newText" => "x"}]}, context)

    assert {:error, "edits[1].oldText must not be empty in ws.txt."} =
             Edit.call(
               %{
                 "path" => "ws.txt",
                 "edits" => [%{"oldText" => "a", "newText" => "x"}, %{"oldText" => "", "newText" => "y"}]
               },
               context
             )

    assert {:error, error} =
             Edit.call(%{"path" => "ws.txt", "edits" => [%{"oldText" => "  ", "newText" => "_"}]}, context)

    assert error =~ "Found 2 occurrences"

    File.write!(path, "a  b")
    assert {:ok, _} = Edit.call(%{"path" => "ws.txt", "edits" => [%{"oldText" => "  ", "newText" => "_"}]}, context)
    assert File.read!(path) == "a_b"
  end

  # Line endings of inserted text and kept text, as pi's applyReplacementsToOriginal.
  test "line endings follow pi", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "endings.txt")

    cases = [
      # An unterminated last line takes the previous line's ending, not the file's first CRLF.
      {"a\r\nb\nc\nlast", "last", "l1\nl2", "a\r\nb\nc\nl1\nl2"},
      # Classic Mac files keep lone CRs.
      {"one\rtwo\rthree", "two", "2\n2b", "one\r2\r2b\rthree"},
      # A kept lone CR next to a removed range must not merge with the LF after it into one CRLF.
      {"a\rb\nc", "b", "", "a\r\n\nc"}
    ]

    for {before, old, new, expected} <- cases do
      File.write!(path, before)

      assert {:ok, _} =
               Edit.call(%{"path" => "endings.txt", "edits" => [%{"oldText" => old, "newText" => new}]}, context)

      assert File.read!(path) == expected, "editing #{inspect(before)}"
    end
  end
end
