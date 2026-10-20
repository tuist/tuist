defmodule Tuist.Runners.Buildkite.LogParserTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.Buildkite.LogParser

  @fallback ~U[2026-09-04 12:00:00.000000Z]

  # The parser normalizes to microsecond precision for the ClickHouse
  # column, and `DateTime.==` compares precision too, so the expected
  # value has to be normalized the same way.
  defp at(milliseconds) do
    %{DateTime.from_unix!(milliseconds, :millisecond) | microsecond: {0, 6}}
  end

  describe "parse/3" do
    test "reads the agent's inline timestamp and strips it from the message" do
      line = "\e_bk;t=1756900000000\aRunning tests"

      assert [%{line_number: 1, ts: ts, message: "Running tests"}] =
               LogParser.parse([line], 1, @fallback)

      assert ts == at(1_756_900_000_000)
    end

    test "numbers lines from the chunk's offset so a resend lands on the same rows" do
      lines = ["one", "two", "three"]

      assert [%{line_number: 5001}, %{line_number: 5002}, %{line_number: 5003}] =
               LogParser.parse(lines, 5001, @fallback)
    end

    test "carries the previous timestamp forward across unmarked lines" do
      lines = [
        "\e_bk;t=1756900000000\afirst",
        "continuation",
        "\e_bk;t=1756900005000\asecond"
      ]

      assert [first, middle, last] = LogParser.parse(lines, 1, @fallback)

      assert first.ts == at(1_756_900_000_000)
      assert middle.ts == first.ts
      assert middle.message == "continuation"
      assert last.ts == at(1_756_900_005_000)
    end

    test "falls back to the given timestamp before the first marker" do
      assert [%{ts: @fallback, message: "no marker yet"}] =
               LogParser.parse(["no marker yet"], 1, @fallback)
    end

    test "trims the carriage return a CRLF log leaves behind" do
      assert [%{message: "trailing"}] = LogParser.parse(["trailing\r"], 1, @fallback)
    end

    test "keeps a malformed marker's line rather than dropping it" do
      assert [%{ts: @fallback, message: "text"}] =
               LogParser.parse(["\e_bk;t=notanumber\atext"], 1, @fallback)
    end

    test "advertises microsecond precision for the ClickHouse column" do
      [%{ts: %DateTime{microsecond: {_value, precision}}}] =
        LogParser.parse(["\e_bk;t=1756900000123\ax"], 1, @fallback)

      assert precision == 6
    end
  end
end
