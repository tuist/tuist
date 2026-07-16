defmodule Tuist.Marketing.Newsletter.IssueParserTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Newsletter.IssueParser

  test "preserves existing inline styles when adding email styles" do
    contents = """
    date: 2026-07-12
    hero:
      subtitle: '<a href="https://tuist.dev" style="font-weight: bold;">Featured work</a>'
    body: |
      <a href="https://tuist.dev" style="font-weight: bold;">Tuist</a>

      <blockquote style="color: red;">A quote</blockquote>

      Run `tuist test` from the command line.
    tools: []
    interview:
      interviewee: Person
      interviewee_intro: Introduction
      questions: []
    food_for_thought: []
    """

    {attrs, _body} = IssueParser.parse("1.yml", contents)
    parsed_body = Floki.parse_fragment!(attrs["body"])

    [link] = Floki.find(parsed_body, "a")
    assert Floki.attribute(link, "style") == ["color: #622ed4; font-weight: bold;"]

    [blockquote] = Floki.find(parsed_body, "blockquote")
    assert Floki.attribute(blockquote, "style") == ["font-style: italic; color: red;"]

    [code] = Floki.find(parsed_body, "code")
    assert Floki.attribute(code, "class") == ["inline"]
  end
end
