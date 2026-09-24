defmodule Tuist.Tests.EnumerationTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Enumeration
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  defp run(project, attrs) do
    {:ok, test} =
      RunsFixtures.test_fixture(
        Keyword.merge(
          [
            project_id: project.id,
            test_modules: [
              %{
                name: "AppTests",
                status: "success",
                duration: 10,
                test_cases: [
                  %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5}
                ]
              }
            ]
          ],
          attrs
        )
      )

    test
  end

  test "stores every candidate by the test case's stable id, enabled or not", %{project: project} do
    test = run(project, [])

    Enumeration.record(test, [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true},
      %{module: "AppTests", suite: "MathTests", name: "testSubtract()", enabled: true},
      %{"module" => "AppTests", "suite" => "", "name" => "freeFunction()"},
      %{module: "AppTests", suite: "MathTests", name: "testDisabled()", enabled: false}
    ])

    assert [
             %{suite_name: "", name: "freeFunction()", enabled: true},
             %{suite_name: "MathTests", name: "testAdd()", enabled: true},
             %{suite_name: "MathTests", name: "testDisabled()", enabled: false},
             %{suite_name: "MathTests", name: "testSubtract()", enabled: true, test_case_id: id}
           ] = CoverageFixtures.enumerated_tests(test)

    assert id == Tests.generate_test_case_id(project.id, "testSubtract()", "AppTests", "MathTests")
  end

  test "names a test skipped by a later run after the display name an earlier run recorded", %{project: project} do
    ran =
      run(project,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10,
            test_cases: [%{name: "Maps paths", test_suite_name: "MapperTests", status: "success", duration: 5}]
          }
        ]
      )

    Enumeration.record(ran, [
      %{module: "AppTests", suite: "MapperTests", name: "Maps paths", function: "map()", enabled: true}
    ])

    assert [%{name: "Maps paths", function_name: "map()"}] = CoverageFixtures.enumerated_tests(ran)

    skipped = run(project, [])

    Enumeration.record(skipped, [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true},
      %{module: "AppTests", suite: "MapperTests", name: "map()", enabled: true}
    ])

    assert %{test_case_id: id} = Enum.find(CoverageFixtures.enumerated_tests(skipped), &(&1.name == "Maps paths"))
    assert id == Tests.generate_test_case_id(project.id, "Maps paths", "AppTests", "MapperTests")
  end

  test "stores nothing while the account's coverage flag is off", %{project: project} do
    test = run(project, [])
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    Enumeration.record(test, [%{module: "AppTests", suite: "MathTests", name: "testSubtract()"}])

    assert CoverageFixtures.enumerated_tests(test) == []
  end
end
