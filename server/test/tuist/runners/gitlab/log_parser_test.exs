defmodule Tuist.Runners.GitLab.LogParserTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.GitLab.LogParser

  @fallback ~U[2026-09-10 12:00:00.000000Z]

  test "parses real timestamped stdout, stderr and continuation records" do
    lines = [
      "2026-09-10T12:35:16.931572Z 00O+\e[0Ksection_start:1789043716:prepare_executor\r\e[0KPreparing executor",
      "2026-09-10T12:35:17.123456Z 01E Error from script",
      "2026-09-10T12:35:18.000000Z ffO Masked sentinel=[MASKED]"
    ]

    assert [first, second, third] = LogParser.parse(lines, 101, @fallback)
    assert first == %{line_number: 101, ts: ~U[2026-09-10 12:35:16.931572Z], message: "Preparing executor"}
    assert second == %{line_number: 102, ts: ~U[2026-09-10 12:35:17.123456Z], message: "Error from script"}
    assert third.message == "Masked sentinel=[MASKED]"
  end

  test "supports untimestamped stream records and legacy section timestamps" do
    lines = ["00O section_start:1756900000:script\r\e[0KRunning tests", "01O+continued\r", "plain line"]
    assert [first, second, third] = LogParser.parse(lines, 1, @fallback)
    assert first.ts == ~U[2025-09-03 11:46:40.000000Z]
    assert first.message == "Running tests"
    assert second.message == "continued"
    assert third.message == "plain line"
    assert second.ts == first.ts
    assert third.ts == first.ts
  end

  test "uses the fallback before a timestamp and preserves ANSI colors for the renderer" do
    assert [%{ts: @fallback, message: "\e[31mError\e[0m"}] =
             LogParser.parse(["00E \e[0K\e[31mError\e[0m"], 1, @fallback)
  end
end
