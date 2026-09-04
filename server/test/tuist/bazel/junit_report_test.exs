defmodule Tuist.Bazel.JunitReportTest do
  use ExUnit.Case, async: true

  alias Tuist.Bazel.JunitReport

  test "parses individual JUnit test cases and their failures" do
    report = """
    <?xml version="1.0" encoding="UTF-8"?>
    <testsuites>
      <testsuite name="ExampleTests">
        <testcase name="testPasses" time="0.125" />
        <testcase name="testFails" time="0.250">
          <failure message="Expected true" file="Tests/ExampleTests.swift" line="42">Expected true to be false</failure>
        </testcase>
        <testcase name="testSkipped" time="0.001"><skipped /></testcase>
      </testsuite>
    </testsuites>
    """

    assert {:ok, parsed} = JunitReport.parse(report)

    assert parsed.test_suites == [%{name: "ExampleTests", status: "failure", duration: 376}]

    assert parsed.test_cases == [
             %{
               name: "testPasses",
               test_suite_name: "ExampleTests",
               status: "success",
               duration: 125,
               failures: []
             },
             %{
               name: "testFails",
               test_suite_name: "ExampleTests",
               status: "failure",
               duration: 250,
               failures: [
                 %{
                   message: "Expected true",
                   path: "Tests/ExampleTests.swift",
                   line_number: 42,
                   issue_type: "assertion_failure"
                 }
               ]
             },
             %{
               name: "testSkipped",
               test_suite_name: "ExampleTests",
               status: "skipped",
               duration: 1,
               failures: []
             }
           ]
  end

  test "rejects documents containing declarations" do
    assert {:error, :unsafe_document} = JunitReport.parse("<!DOCTYPE testsuite><testsuite />")
  end
end
