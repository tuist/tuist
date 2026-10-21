defmodule Tuist.Runners.LogFormatterTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.LogFormatter

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

    test "wraps a composite action's step into an {:action, header, children} node" do
      lines = [
        line(1, "##[group]Run ./.github/actions/simulator-workaround"),
        line(2, "##[endgroup]"),
        line(3, "##[start-action display=Apply Simulator Workaround;id=__self_5.__run]"),
        line(4, "##[group]Run echo workaround"),
        line(5, "##[endgroup]"),
        line(6, "##[error]Process completed with exit code 26."),
        line(7, "##[end-action id=__self_5.__run;outcome=failure;conclusion=failure;duration_ms=204]")
      ]

      assert [
               {:group, %{line_number: 1}, []},
               {:action, header, children}
             ] = LogFormatter.group_lines(lines)

      assert header == %{
               line: Enum.at(lines, 2),
               name: "Apply Simulator Workaround",
               conclusion: "failure",
               duration_ms: 204
             }

      assert [
               {:group, %{line_number: 4}, []},
               {:line, %{line_number: 6}}
             ] = children
    end

    test "nests composite actions and keeps names containing semicolons" do
      lines = [
        line(1, "##[start-action display=Upload Tuist Logs;id=__self_7.__self]"),
        line(2, "##[start-action display=Archive; then upload;id=__self_7.__self.archive]"),
        line(3, "archived"),
        line(4, "##[end-action id=__self_7.__self.archive;outcome=success;conclusion=success;duration_ms=15]"),
        line(5, "##[start-action display=Upload;id=__self_7.__self.upload]"),
        line(6, "##[end-action id=__self_7.__self.upload;outcome=skipped;conclusion=skipped;duration_ms=0]"),
        line(7, "##[end-action id=__self_7.__self;outcome=success;conclusion=success;duration_ms=265]")
      ]

      assert [{:action, %{name: "Upload Tuist Logs", conclusion: "success"}, children}] =
               LogFormatter.group_lines(lines)

      assert [
               {:action, %{name: "Archive; then upload", duration_ms: 15}, [{:line, %{message: "archived"}}]},
               {:action, %{name: "Upload", conclusion: "skipped"}, []}
             ] = children
    end

    test "an end-action closes groups left open inside its action" do
      lines = [
        line(1, "##[start-action display=Step;id=__self.__run]"),
        line(2, "##[group]Unterminated"),
        line(3, "inside"),
        line(4, "##[end-action id=__self.__run;outcome=success;conclusion=success;duration_ms=1]"),
        line(5, "after")
      ]

      assert [
               {:action, %{name: "Step"}, [{:group, %{line_number: 2}, [{:line, %{message: "inside"}}]}]},
               {:line, %{message: "after"}}
             ] = LogFormatter.group_lines(lines)
    end

    test "closes unterminated actions at end-of-stream" do
      lines = [
        line(1, "##[start-action display=Step;id=__self.__run]"),
        line(2, "running")
      ]

      assert [{:action, %{name: "Step", conclusion: nil, duration_ms: nil}, [{:line, %{message: "running"}}]}] =
               LogFormatter.group_lines(lines)
    end

    test "drops closers whose opener is outside the lines, as when a page starts mid-group" do
      lines = [
        line(1, "inside a group"),
        line(nil, "##[endgroup]"),
        line(2, "inside an action"),
        line(nil, "##[end-action id=__self.__run;outcome=success;conclusion=success;duration_ms=1]"),
        line(3, "after")
      ]

      assert [
               {:line, %{message: "inside a group"}},
               {:line, %{message: "inside an action"}},
               {:line, %{message: "after"}}
             ] = LogFormatter.group_lines(lines)
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

  describe "annotation/1" do
    test "returns the kind of an error, warning, or notice line" do
      assert LogFormatter.annotation("##[error]Process completed with exit code 26.") == "error"
      assert LogFormatter.annotation("##[warning]Node.js 20 is deprecated.") == "warning"
      assert LogFormatter.annotation("##[notice]Cache restored") == "notice"
    end

    test "accepts workflow command properties before the closing bracket" do
      assert LogFormatter.annotation("##[error file=App.swift,line=3]Missing return") == "error"
    end

    test "returns nil for any other line" do
      assert LogFormatter.annotation("##[group]Run echo hi") == nil
      assert LogFormatter.annotation("error: something failed") == nil
    end
  end

  describe "render_message/1" do
    defp rendered(message), do: message |> LogFormatter.render_message() |> Phoenix.HTML.safe_to_string()

    test "replaces the error marker with an Error: label" do
      assert rendered("##[error]Process completed with exit code 26.") ==
               ~s(<span class="log-annotation-label">Error:</span> Process completed with exit code 26.)
    end

    test "labels warnings and notices, dropping command properties" do
      assert rendered("##[warning file=a.js,line=1]Deprecated") ==
               ~s(<span class="log-annotation-label">Warning:</span> Deprecated)

      assert rendered("##[notice]Cache restored") == ~s(<span class="log-annotation-label">Notice:</span> Cache restored)
    end

    test "escapes the annotation text and keeps its ANSI colours" do
      assert rendered("##[error]\e[31m<b>bad</b>\e[0m") ==
               ~s(<span class="log-annotation-label">Error:</span> <span class="ansi-fg-1">&lt;b&gt;bad&lt;/b&gt;</span>)
    end

    test "renders other lines unchanged" do
      assert rendered("plain <text>") == "plain &lt;text&gt;"
    end
  end
end
