defmodule Tuist.Tests.FlakinessEvidenceTest do
  use ExUnit.Case, async: true

  alias Tuist.Tests.FlakinessEvidence

  test "holds a 435-case crash burst across nine modules out of flakiness evidence" do
    report = report(435, 9)
    annotated = FlakinessEvidence.annotate(report)

    assert length(cases(annotated)) == 435

    assert Enum.all?(
             cases(annotated),
             &(&1.flakiness_exclusion_reason == "correlated_runner_crash")
           )

    assert Enum.map(cases(annotated), &Map.delete(&1, :flakiness_exclusion_reason)) ==
             cases(report)
  end

  test "requires twenty distinct identities and more than one module in the same report" do
    for report <- [report(19, 2), report(435, 1)] do
      assert Enum.all?(
               cases(FlakinessEvidence.annotate(report)),
               &(&1.flakiness_exclusion_reason == "")
             )
    end

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(report(20, 2))),
             &(&1.flakiness_exclusion_reason != "")
           )

    duplicate = %{name: "Module", test_cases: List.duplicate(crash(1), 30)}
    report = %{test_modules: [duplicate, %{duplicate | name: "OtherModule"}]}

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(report)),
             &(&1.flakiness_exclusion_reason == "")
           )
  end

  test "keeps assertions, isolated crashes with timing, and unknown diagnostics eligible within a burst" do
    exceptions = [
      %{crash(1) | duration: 1},
      %{crash(2) | duration: -1},
      %{
        crash(3)
        | failures: [%{message: "XCTAssertEqual failed", path: "Test.swift", line_number: 20}]
      },
      %{crash(4) | failures: [%{message: "Crash: xctest", path: "Test.swift", line_number: 20}]},
      %{crash(5) | failures: [%{message: "Unknown runner error"}]},
      %{crash(6) | failures: []}
    ]

    report =
      Map.update!(
        report(20, 2),
        :test_modules,
        &(&1 ++ [%{name: "Exceptions", test_cases: exceptions}])
      )

    annotated = FlakinessEvidence.annotate(report)

    assert Enum.all?(
             List.last(annotated.test_modules).test_cases,
             &(&1.flakiness_exclusion_reason == "")
           )

    assert Enum.count(cases(annotated), &(&1.flakiness_exclusion_reason != "")) == 20
  end

  test "a crash followed by a successful in-report retry is excluded only with zero-duration failed attempts" do
    report =
      map_cases(report(20, 2), fn test_case ->
        Map.merge(test_case, %{
          status: "success",
          duration: 100,
          repetitions: [%{status: "failure", duration: 0}, %{status: "success", duration: 100}]
        })
      end)

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(report)),
             &(&1.flakiness_exclusion_reason != "")
           )

    measured = map_cases(report, &Map.put(&1, :repetitions, [%{status: "failure", duration: 1}]))

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(measured)),
             &(&1.flakiness_exclusion_reason == "")
           )
  end

  test "caller-supplied exclusions cannot suppress ordinary evidence or other build systems" do
    for build_system <- ["gradle", "bazel", "once", "mix", "cargo"] do
      report =
        20
        |> report(2)
        |> Map.put(:build_system, build_system)
        |> map_cases(&Map.put(&1, :flakiness_exclusion_reason, "forged"))

      assert Enum.all?(
               cases(FlakinessEvidence.annotate(report)),
               &(&1.flakiness_exclusion_reason == "")
             )
    end

    report = map_cases(report(1, 1), &Map.put(&1, :flakiness_exclusion_reason, "forged"))

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(report)),
             &(&1.flakiness_exclusion_reason == "")
           )
  end

  test "remote xcresult reports can omit timing that the CLI encodes as zero" do
    report = map_cases(report(20, 2), &Map.delete(&1, :duration))
    assert Enum.all?(cases(FlakinessEvidence.annotate(report)), &(&1.flakiness_exclusion_reason != ""))
  end

  test "parameterized retry diagnostics participate and any genuine failure keeps the case eligible" do
    report =
      map_cases(report(20, 2), fn test_case ->
        test_case
        |> Map.put(:failures, [])
        |> Map.put(:status, "success")
        |> Map.put(:arguments, [
          %{
            failures: test_case.failures,
            repetitions: [%{status: "failure", duration: 0}, %{status: "success", duration: 10}]
          }
        ])
      end)

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(report)),
             &(&1.flakiness_exclusion_reason != "")
           )

    report =
      map_cases(report, fn test_case ->
        Map.update!(
          test_case,
          :arguments,
          &(&1 ++ [%{failures: [%{message: "assertion failed"}]}])
        )
      end)

    assert Enum.all?(
             cases(FlakinessEvidence.annotate(report)),
             &(&1.flakiness_exclusion_reason == "")
           )
  end

  test "a duplicate identity with a genuine failure is never suppressed" do
    report = report(22, 2)
    [first | rest] = report.test_modules
    ordinary = %{hd(first.test_cases) | failures: [%{message: "assertion failed"}]}

    report = %{
      report
      | test_modules: [%{first | test_cases: first.test_cases ++ [ordinary]} | rest]
    }

    annotated = FlakinessEvidence.annotate(report)

    assert Enum.all?(
             Enum.filter(hd(annotated.test_modules).test_cases, &(&1.name == ordinary.name)),
             &(&1.flakiness_exclusion_reason == "")
           )
  end

  test "a measured parameter failure is not hidden by another parameter's zero-duration retry" do
    report =
      map_cases(report(20, 2), fn test_case ->
        Map.merge(test_case, %{
          status: "success",
          arguments: [
            %{status: "success", repetitions: [%{status: "failure", duration: 0}, %{status: "success", duration: 10}]},
            %{status: "failure", duration: 10}
          ]
        })
      end)

    assert Enum.all?(cases(FlakinessEvidence.annotate(report)), &(&1.flakiness_exclusion_reason == ""))
  end

  defp report(count, modules) do
    test_modules =
      1..count
      |> Enum.group_by(&rem(&1, modules))
      |> Enum.sort()
      |> Enum.map(fn {module, indices} ->
        %{name: "Module#{module}", test_cases: Enum.map(indices, &crash/1)}
      end)

    %{build_system: "xcode", test_modules: test_modules}
  end

  defp crash(index) do
    message =
      Enum.at(
        [
          "Crash: xctest",
          "Crash: xctest at static xctest.main()",
          "Test crashed with signal trap."
        ],
        rem(index, 3)
      )

    %{
      name: "test_#{index}",
      test_suite_name: "Suite",
      status: "failure",
      duration: 0,
      failures: [%{message: message, path: "", line_number: 0, issue_type: "assertion_failure"}]
    }
  end

  defp cases(report), do: Enum.flat_map(report.test_modules, & &1.test_cases)

  defp map_cases(report, transform) do
    Map.update!(report, :test_modules, fn modules ->
      Enum.map(modules, &Map.update!(&1, :test_cases, fn cases -> Enum.map(cases, transform) end))
    end)
  end
end
