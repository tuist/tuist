defmodule Tuist.Tests.StressNewTestsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Tests
  alias Tuist.Tests.StressNewTests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestRunStressCandidate
  alias Tuist.Tests.TestRunStressRepetition
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{account: account, project: Tuist.Repo.preload(project, :account)}
  end

  defp run_on_main(project, account, test_cases, opts \\ []) do
    {:ok, test} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        git_branch: Keyword.get(opts, :git_branch, "main"),
        git_commit_sha: "abc123",
        ran_at: Keyword.get(opts, :ran_at, NaiveDateTime.utc_now()),
        is_ci: Keyword.get(opts, :is_ci, true),
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1000,
            test_cases:
              Enum.map(test_cases, fn name ->
                %{name: name, test_suite_name: "CheckoutTests", status: "success", duration: 10}
              end)
          }
        ]
      })

    test
  end

  defp case_attrs(name, duration \\ 10) do
    %{name: name, suite_name: "CheckoutTests", module_name: "AppTests", duration: duration}
  end

  describe "verdict/3" do
    test "returns nothing when the account is not entitled", %{project: project, account: account} do
      stub(Environment, :env, fn -> :prod end)
      expect(FunWithFlags, :enabled?, fn :stress_new_tests, [for: ^account] -> false end)

      verdict = StressNewTests.verdict(project, account, [case_attrs("testNew")])

      assert verdict.enabled == false
      assert verdict.candidates == []
      assert verdict.guard == nil
      assert verdict.parameters.candidate_cap == 200
    end

    test "fires the premise guard when the project has no default branch", %{project: project, account: account} do
      project = %{project | default_branch: nil}

      verdict = StressNewTests.verdict(project, account, [case_attrs("testNew")])

      assert verdict.enabled == true
      assert verdict.candidates == []
      assert verdict.guard == %{kind: "no_default_branch", new_count: 1, inventory_count: 0}
    end

    test "fires the premise guard when the default branch has no CI history", %{project: project, account: account} do
      run_on_main(project, account, ["testOld"], is_ci: false)
      run_on_main(project, account, ["testOld"], git_branch: "feature")

      verdict = StressNewTests.verdict(project, account, [case_attrs("testNew"), case_attrs("testOld")])

      assert verdict.candidates == []
      assert verdict.guard == %{kind: "no_default_branch_history", new_count: 2, inventory_count: 0}
    end

    test "prices the test cases with no default-branch history and leaves the known ones out", %{
      project: project,
      account: account
    } do
      run_on_main(project, account, ["testOld", "testOlder"])

      verdict =
        StressNewTests.verdict(project, account, [
          case_attrs("testOld"),
          case_attrs("testSlow", 400_000),
          case_attrs("testMedium", 20_000),
          case_attrs("testFast", 4),
          case_attrs("testFast", 4)
        ])

      assert verdict.guard == nil
      assert verdict.inventory_count == 2

      assert verdict.candidates == [
               %{
                 name: "testFast",
                 suite_name: "CheckoutTests",
                 module_name: "AppTests",
                 repetitions: 10,
                 excluded_reason: nil
               },
               %{
                 name: "testMedium",
                 suite_name: "CheckoutTests",
                 module_name: "AppTests",
                 repetitions: 3,
                 excluded_reason: nil
               },
               %{
                 name: "testSlow",
                 suite_name: "CheckoutTests",
                 module_name: "AppTests",
                 repetitions: 0,
                 excluded_reason: "too_slow"
               }
             ]
    end

    test "excludes candidates beyond the project's cap", %{project: project, account: account} do
      run_on_main(project, account, ["testOld"])
      project = %{project | stress_new_tests_candidate_cap: 1}

      verdict = StressNewTests.verdict(project, account, [case_attrs("testB"), case_attrs("testA")])

      assert Enum.map(verdict.candidates, &{&1.name, &1.repetitions, &1.excluded_reason}) == [
               {"testA", 10, nil},
               {"testB", 0, "candidate_cap"}
             ]
    end

    test "fires the bulk-change guard only above the floor", %{project: project, account: account} do
      run_on_main(project, account, ["testOld"])
      new_cases = Enum.map(1..3, &case_attrs("testNew#{&1}"))

      below_floor = StressNewTests.verdict(project, account, new_cases)
      assert below_floor.guard == nil
      assert length(below_floor.candidates) == 3

      project = %{project | stress_new_tests_bulk_change_floor: 3}
      above_floor = StressNewTests.verdict(project, account, new_cases)
      assert above_floor.guard == %{kind: "bulk_change", new_count: 3, inventory_count: 1}
      assert above_floor.candidates == []
    end
  end

  describe "repetitions_for/2" do
    test "returns the first bucket the duration fits in and zero past the curve" do
      curve = StressNewTests.parameters(%Project{}).repetition_curve

      assert StressNewTests.repetitions_for(nil, curve) == 10
      assert StressNewTests.repetitions_for(5_000, curve) == 10
      assert StressNewTests.repetitions_for(5_001, curve) == 5
      assert StressNewTests.repetitions_for(30_000, curve) == 3
      assert StressNewTests.repetitions_for(299_999, curve) == 2
      assert StressNewTests.repetitions_for(300_001, curve) == 0
    end
  end

  describe "recording" do
    test "stores the gate's verdict on the run and its candidates beside it", %{project: project, account: account} do
      {:ok, test} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration: 1000,
          status: "success",
          git_branch: "feature",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "testNew", test_suite_name: "CheckoutTests", status: "success", duration: 10}]
            }
          ],
          stress_new_tests: %{
            mode: "report",
            outcome: "disagreed",
            new_count: 2,
            stressed_count: 1,
            excluded_count: 1,
            inventory_count: 40,
            test_cases: [
              %{
                name: "testNew",
                suite_name: "CheckoutTests",
                module_name: "AppTests",
                repetitions: 10,
                failed_repetitions: 2,
                outcome: "disagreed",
                is_quarantined: false,
                repetition_results: [
                  %{repetition_number: 1, status: "success", duration: 5},
                  %{
                    repetition_number: 2,
                    status: "failure",
                    duration: 6,
                    failure: %{
                      message: "Bool.random()",
                      path: "AppTests.swift",
                      line_number: 7,
                      issue_type: "assertion_failure"
                    }
                  }
                ]
              },
              %{
                name: "testSlow",
                suite_name: "CheckoutTests",
                module_name: "AppTests",
                repetitions: 0,
                failed_repetitions: 0,
                outcome: "excluded_too_slow"
              }
            ]
          }
        })

      {:ok, stored} = Tests.get_test(test.id)
      assert stored.stress_mode == "report"
      assert stored.stress_outcome == "disagreed"
      assert stored.stress_skip_reason == ""
      assert stored.stress_new_count == 2
      assert stored.stress_stressed_count == 1
      assert stored.stress_excluded_count == 1
      assert stored.stress_inventory_count == 40

      candidates = StressNewTests.list_candidates(test.id)

      assert Enum.map(candidates, &{&1.name, &1.repetitions, &1.failed_repetitions, &1.outcome}) == [
               {"testNew", 10, 2, "disagreed"},
               {"testSlow", 0, 0, "excluded_too_slow"}
             ]

      assert Enum.map(candidates, &StressNewTests.blocking_candidate?/1) == [true, false]

      [candidate | _] = candidates
      assert candidate.test_case_id == Tests.generate_test_case_id(project.id, "testNew", "AppTests", "CheckoutTests")

      # The repetitions are stored so the dashboard can render the finding like a failure,
      # and are keyed on the same identity the test case runs use.
      repetitions = StressNewTests.repetitions_by_test_case(test.id)
      stored_repetitions = Map.fetch!(repetitions, candidate.test_case_id)

      assert Enum.map(stored_repetitions, &{&1.repetition_number, &1.status}) == [
               {1, "success"},
               {2, "failure"}
             ]

      failed = Enum.find(stored_repetitions, &(&1.status == "failure"))

      assert TestRunStressRepetition.failure(failed) == %{
               message: "Bool.random()",
               path: "AppTests.swift",
               line_number: 7,
               issue_type: "assertion_failure"
             }

      assert TestRunStressRepetition.failure(Enum.find(stored_repetitions, &(&1.status == "success"))) == nil

      [blocking] = StressNewTests.blocking_candidates_with_repetitions(test.id)
      assert blocking.name == "testNew"
      assert length(blocking.stress_repetitions) == 2

      by_identity = StressNewTests.candidates_by_identity(test.id)

      assert by_identity |> Map.fetch!({"AppTests", "CheckoutTests", "testNew"}) |> Map.get(:outcome) ==
               "disagreed"

      # The pass is never recorded as organic evidence.
      {:ok, stored_with_runs} = Tests.get_test(test.id, preload: [:test_case_runs])
      assert Enum.all?(stored_with_runs.test_case_runs, &(&1.is_flaky == false))
      assert stored.is_flaky == false
    end

    test "leaves the columns blank for a run that did not carry the gate", %{project: project, account: account} do
      test = run_on_main(project, account, ["testOld"])

      {:ok, stored} = Tests.get_test(test.id)
      assert stored.stress_mode == ""
      assert stored.stress_outcome == ""
      assert StressNewTests.list_candidates(test.id) == []
    end
  end

  describe "the trailing window" do
    test "a test case last seen inside the window is not new", %{project: project, account: account} do
      run_on_main(project, account, ["testOld"], ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -89, :day))

      verdict = StressNewTests.verdict(project, account, [case_attrs("testOld")])

      assert verdict.candidates == []
      assert verdict.inventory_count == 1
    end

    test "a test case dormant for longer than the window reads as new again", %{project: project, account: account} do
      run_on_main(project, account, ["testDormant"], ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -91, :day))
      run_on_main(project, account, ["testRecent"])

      verdict = StressNewTests.verdict(project, account, [case_attrs("testDormant"), case_attrs("testRecent")])

      assert Enum.map(verdict.candidates, & &1.name) == ["testDormant"]

      # The dormant case leaves the inventory with it, so the bulk-change ratio
      # keeps comparing two halves of one population.
      assert verdict.inventory_count == 1
    end
  end

  describe "changeset contracts" do
    test "a candidate accepts a recorded outcome and rejects one the gate never assigns" do
      attrs = %{
        id: UUIDv7.generate(),
        test_run_id: UUIDv7.generate(),
        project_id: 1,
        test_case_id: UUIDv7.generate(),
        name: "testNew",
        suite_name: "CheckoutTests",
        module_name: "AppTests",
        repetitions: 10,
        failed_repetitions: 3,
        outcome: "disagreed"
      }

      assert %{valid?: true} = TestRunStressCandidate.create_changeset(%TestRunStressCandidate{}, attrs)

      changeset =
        TestRunStressCandidate.create_changeset(
          %TestRunStressCandidate{},
          %{attrs | outcome: "flaky"}
        )

      refute changeset.valid?
      assert %{outcome: ["is invalid"]} = errors_on(changeset)

      changeset =
        TestRunStressCandidate.create_changeset(
          %TestRunStressCandidate{},
          Map.delete(attrs, :test_case_id)
        )

      refute changeset.valid?
      assert %{test_case_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "a repetition only accepts the two statuses the gate records" do
      attrs = %{
        id: UUIDv7.generate(),
        test_run_id: UUIDv7.generate(),
        project_id: 1,
        test_case_id: UUIDv7.generate(),
        repetition_number: 1,
        status: "success"
      }

      assert %{valid?: true} =
               TestRunStressRepetition.create_changeset(%TestRunStressRepetition{}, attrs)

      changeset =
        TestRunStressRepetition.create_changeset(
          %TestRunStressRepetition{},
          %{attrs | status: "skipped"}
        )

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "a project accepts a curve and rejects parameters outside their bounds", %{project: project} do
      curve = [%{"max_duration_ms" => 5_000, "repetitions" => 10}]

      changeset =
        Project.update_changeset(project, %{
          stress_new_tests_repetition_curve: curve,
          stress_new_tests_candidate_cap: 50,
          stress_new_tests_wall_clock_ceiling_ms: 60_000,
          stress_new_tests_bulk_change_ratio: 0.5,
          stress_new_tests_bulk_change_floor: 0
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :stress_new_tests_repetition_curve) == curve

      changeset =
        Project.update_changeset(project, %{
          stress_new_tests_candidate_cap: 0,
          stress_new_tests_wall_clock_ceiling_ms: 0,
          stress_new_tests_bulk_change_ratio: 1.5,
          stress_new_tests_bulk_change_floor: -1
        })

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:stress_new_tests_candidate_cap]
      assert errors[:stress_new_tests_wall_clock_ceiling_ms]
      assert errors[:stress_new_tests_bulk_change_ratio]
      assert errors[:stress_new_tests_bulk_change_floor]
    end

    test "the stored curve is what the verdict prices repetitions from", %{project: project, account: account} do
      run_on_main(project, account, ["testOld"])
      project = %{project | stress_new_tests_repetition_curve: [%{"max_duration_ms" => 100, "repetitions" => 2}]}

      verdict = StressNewTests.verdict(project, account, [case_attrs("testFast", 50), case_attrs("testSlow", 500)])

      assert Enum.map(verdict.candidates, &{&1.name, &1.repetitions, &1.excluded_reason}) == [
               {"testFast", 2, nil},
               {"testSlow", 0, "too_slow"}
             ]
    end
  end

  describe "merge_run_attrs/2" do
    test "adds the shards' counts and keeps the worst outcome" do
      existing = %Test{
        stress_mode: "enforce",
        stress_outcome: "passed",
        stress_skip_reason: "",
        stress_new_count: 1,
        stress_stressed_count: 1,
        stress_excluded_count: 0,
        stress_inventory_count: 40
      }

      merged =
        StressNewTests.merge_run_attrs(existing, %{
          mode: "enforce",
          outcome: "disagreed",
          new_count: 2,
          stressed_count: 1,
          excluded_count: 1,
          inventory_count: 40
        })

      assert merged == %{
               stress_mode: "enforce",
               stress_outcome: "disagreed",
               stress_skip_reason: "",
               stress_new_count: 3,
               stress_stressed_count: 2,
               stress_excluded_count: 1,
               stress_inventory_count: 40
             }

      assert StressNewTests.merge_run_attrs(existing, nil).stress_outcome == "passed"
    end
  end
end
