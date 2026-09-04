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
    assert {:error, :invalid_report} = JunitReport.parse("<!DOCTYPE testsuite><testsuite />")
  end

  test "returns an error for malformed XML without exiting the caller" do
    assert {:error, :invalid_report} = JunitReport.parse("<testsuite><testcase></testsuite>")
  end

  test "parses arbitrary element names without creating atoms" do
    suffix = System.unique_integer([:positive])
    element_name = "extension_#{suffix}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(element_name) end

    assert {:ok, %{test_cases: []}} =
             JunitReport.parse("<testsuite><#{element_name}>value</#{element_name}></testsuite>")

    assert_raise ArgumentError, fn -> String.to_existing_atom(element_name) end
  end

  test "sanitizes credential-shaped failure details and local paths" do
    report = """
    <testsuite name="ExampleTests">
      <testcase name="fails">
        <failure file="/Users/developer/project/test.exs" line="7">Authorization: Bearer secret-token --token another-token</failure>
      </testcase>
    </testsuite>
    """

    assert {:ok, %{test_cases: [%{failures: [failure]}]}} = JunitReport.parse(report)
    assert failure.message == "Authorization: <REDACTED> --token <REDACTED>"
    assert failure.path == "<LOCAL_PATH>"
  end

  test "does not redact ordinary parser diagnostics" do
    report = """
    <testsuite name="ExampleTests">
      <testcase name="fails">
        <failure>unexpected token: identifier</failure>
      </testcase>
    </testsuite>
    """

    assert {:ok, %{test_cases: [%{failures: [failure]}]}} = JunitReport.parse(report)
    assert failure.message == "unexpected token: identifier"
  end
end
