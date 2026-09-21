defmodule Tuist.Tests.EnumerationTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Enumeration
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

  test "reports the candidates a run left out, by the test case's stable id", %{project: project} do
    test = run(project, [])

    Enumeration.record(test, [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true},
      %{module: "AppTests", suite: "MathTests", name: "testSubtract()", enabled: true},
      %{"module" => "AppTests", "suite" => "", "name" => "freeFunction()"},
      %{module: "AppTests", suite: "MathTests", name: "testDisabled()", enabled: false}
    ])

    assert Enumeration.summary(test) == %{enumerated: 4, enabled: 3, not_run: 2}

    assert [
             %{module_name: "AppTests", suite_name: "", name: "freeFunction()"},
             %{module_name: "AppTests", suite_name: "MathTests", name: "testSubtract()", test_case_id: id}
           ] = Enumeration.list_not_run(test)

    assert id == Tests.generate_test_case_id(project.id, "testSubtract()", "AppTests", "MathTests")
    assert [%{name: "testSubtract()"}] = Enumeration.list_not_run(test, page: 2, page_size: 1)
  end

  test "stores and reports nothing while the account's coverage flag is off", %{project: project} do
    test = run(project, [])
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    Enumeration.record(test, [%{module: "AppTests", suite: "MathTests", name: "testSubtract()"}])
    assert Enumeration.summary(test) == nil

    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> true end)
    assert Enumeration.summary(test) == nil
  end

  test "has nothing to say about a run whose client enumerated no tests", %{project: project} do
    assert Enumeration.summary(run(project, [])) == nil
  end
end
