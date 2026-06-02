defmodule Tuist.Runners.LogFormatterTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.LogFormatter

  describe "strip_ansi/1" do
    test "drops every SGR escape sequence, preserving the surrounding text" do
      assert LogFormatter.strip_ansi("\e[36;1mset -euo pipefail\e[0m") == "set -euo pipefail"
    end

    test "leaves text without escapes untouched" do
      assert LogFormatter.strip_ansi("plain text") == "plain text"
    end

    test "handles empty SGR (treated as reset)" do
      assert LogFormatter.strip_ansi("a\e[mb") == "ab"
    end
  end

  describe "to_segments/1" do
    test "splits a basic colour run into the coloured text + reset tail" do
      assert LogFormatter.to_segments("\e[36;1mhello\e[0m world") == [
               {"hello", ["ansi-bold", "ansi-fg-6"]},
               {" world", []}
             ]
    end

    test "carries style across multiple runs until reset" do
      assert LogFormatter.to_segments("\e[31ma\e[1mb\e[0mc") == [
               {"a", ["ansi-fg-1"]},
               {"b", ["ansi-bold", "ansi-fg-1"]},
               {"c", []}
             ]
    end

    test "preserves plain text when there are no codes" do
      assert LogFormatter.to_segments("plain") == [{"plain", []}]
    end

    test "ignores unknown SGR codes but keeps the surrounding text intact" do
      # 38;5;208 (256-colour) — we ignore the colour, keep the text.
      assert LogFormatter.to_segments("\e[38;5;208mhi\e[0m") == [{"hi", []}]
    end
  end

  describe "group_lines/1" do
    defp line(n, msg), do: %{line_number: n, ts: ~U[2026-06-02 12:00:00.000000Z], message: msg}

    test "wraps `##[group]…##[endgroup]` into a {:group, header, children} node" do
      lines = [
        line(1, "before"),
        line(2, "##[group]Run echo hi"),
        line(3, "echo hi"),
        line(4, "hi"),
        line(5, "##[endgroup]"),
        line(6, "after")
      ]

      tree = LogFormatter.group_lines(lines)

      assert [
               {:line, %{line_number: 1}},
               {:group, %{message: "##[group]Run echo hi"}, group_children},
               {:line, %{line_number: 6}}
             ] = tree

      assert Enum.map(group_children, fn {:line, l} -> l.message end) == ["echo hi", "hi"]
    end

    test "handles nested groups" do
      lines = [
        line(1, "##[group]outer"),
        line(2, "outer-pre"),
        line(3, "##[group]inner"),
        line(4, "inner-content"),
        line(5, "##[endgroup]"),
        line(6, "outer-post"),
        line(7, "##[endgroup]")
      ]

      [{:group, %{message: "##[group]outer"}, outer_children}] = LogFormatter.group_lines(lines)

      assert [
               {:line, %{message: "outer-pre"}},
               {:group, %{message: "##[group]inner"}, inner_children},
               {:line, %{message: "outer-post"}}
             ] = outer_children

      assert Enum.map(inner_children, fn {:line, l} -> l.message end) == ["inner-content"]
    end

    test "closes unterminated groups at end-of-stream" do
      # A live-tail snapshot can land mid-group; the renderer must
      # not silently drop those rows.
      lines = [
        line(1, "##[group]Run partial"),
        line(2, "first-line")
      ]

      [{:group, _header, children}] = LogFormatter.group_lines(lines)
      assert Enum.map(children, fn {:line, l} -> l.message end) == ["first-line"]
    end

    test "lines without any group markers come through as flat :line nodes" do
      lines = [line(1, "a"), line(2, "b")]

      assert LogFormatter.group_lines(lines) == [
               {:line, Enum.at(lines, 0)},
               {:line, Enum.at(lines, 1)}
             ]
    end
  end

  describe "group_label/1" do
    test "strips the marker prefix" do
      assert LogFormatter.group_label(%{message: "##[group]Run echo hi"}) == "Run echo hi"
    end

    test "returns the message verbatim if it's not a group header (defensive)" do
      assert LogFormatter.group_label(%{message: "plain"}) == "plain"
    end
  end
end
