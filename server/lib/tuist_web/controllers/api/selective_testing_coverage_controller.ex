defmodule TuistWeb.API.SelectiveTestingCoverageController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.FeatureFlags
  alias Tuist.TestImpactAnalysis.Baselines
  alias Tuist.TestImpactAnalysis.Runs
  alias Tuist.TestImpactAnalysis.Storage
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Tests.TestImpact.Baseline
  alias TuistWeb.API.Schemas.Tests.TestImpact.Run

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  @path_parameters [
    account_handle: [
      in: :path,
      type: :string,
      required: true,
      description: "The handle of the project's account."
    ],
    project_handle: [
      in: :path,
      type: :string,
      required: true,
      description: "The handle of the project."
    ]
  ]

  @xcode_schema %Schema{
    type: :object,
    description: "Xcode only: the scope the invocation tests.",
    properties: %{
      scheme: %Schema{type: :string, description: "The scheme being tested."},
      test_plan: %Schema{type: :string, description: "The test plan being run."},
      destination: %Schema{type: :string, description: "The destination the tests run on."}
    }
  }

  operation(:baseline,
    summary: "Resolve the baseline for coverage-based test selection.",
    description:
      "Returns the nearest ancestor of the checked-out commit with a full run on the same platform, within 20 commits with coverage, and whether the diff between the two is already stored. Returns a reason instead when there's none, including `not_enabled` when test impact analysis isn't enabled for the project, after which the client runs default selective testing.",
    operation_id: "resolveTestImpactBaseline",
    parameters: @path_parameters,
    request_body:
      {"Baseline params", "application/json",
       %Schema{
         title: "ResolveTestImpactBaselineParams",
         type: :object,
         properties: %{
           build_system: %Schema{
             type: :string,
             description: "The build system, `xcode` first. A plain string so new build systems don't need a new client."
           },
           commit_sha: %Schema{
             type: :string,
             description:
               "The checked-out commit, such as GitHub's synthetic merge commit on `pull_request` runs. It keys the stored diff."
           },
           parent_shas: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "The parents of the checked-out commit (the pull request head and the base-branch tip) when it's a merge commit the server's history doesn't have. The walk then starts from both."
           },
           ancestor_shas: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "The checked-out commit's ancestors the client has locally, nearest first, at most 200 (the rest are ignored). Sent on the retry after `history_unknown`, once the client deepened its checkout by 100 commits. The walk also starts from every one of them the server's history has. A known ancestor's distance from the checkout is its position in the list: exact for linear history, approximate across merges."
           },
           platform: %Schema{
             type: :string,
             description:
               "The platform the tests run on. Only a baseline on the same platform is picked. Absent where the build system has none."
           },
           xcode: @xcode_schema
         },
         required: [:build_system, :commit_sha]
       }},
    responses: %{
      ok: {"The baseline, or why there's none", "application/json", Baseline},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      too_many_requests: Responses.authorization_throttled(),
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def baseline(%{assigns: %{selected_project: selected_project}} = conn, _params) do
    if FeatureFlags.test_impact_analysis_enabled?(selected_project.account, selected_project) do
      json(conn, resolve_baseline(selected_project, conn.body_params))
    else
      json(conn, %{baseline_sha: nil, reason: "not_enabled", diff_cached: false})
    end
  end

  defp resolve_baseline(project, params) do
    commit_sha = params.commit_sha

    scope = %{
      commit_sha: commit_sha,
      parent_shas: Map.get(params, :parent_shas) || [],
      ancestor_shas: Map.get(params, :ancestor_shas) || [],
      platform: Map.get(params, :platform),
      scheme: get_in(params, [:xcode, :scheme])
    }

    case Baselines.resolve(project, scope) do
      {:ok, %{sha: baseline_sha}} ->
        %{
          baseline_sha: baseline_sha,
          diff_cached: match?({:ok, _diff}, Storage.get_diff(project.id, commit_sha, baseline_sha))
        }

      {:error, reason} ->
        %{baseline_sha: nil, reason: Atom.to_string(reason), diff_cached: false}
    end
  end

  operation(:create_run,
    summary: "Create an impact run for coverage-based test selection.",
    description:
      "Decides which tests one `tuist test` invocation runs. With a baseline, the server stores or reuses the diff, applies the impact analysis rules, and returns the tests not to run. Without one, it records a fallback with the client's reason. On `fallback` the client runs every test in scope or default selective testing, depending on the reason, and default selective testing on an error or when the request times out.",
    operation_id: "createTestImpactRun",
    parameters: @path_parameters,
    request_body:
      {"Impact run params", "application/json",
       %Schema{
         title: "CreateTestImpactRunParams",
         type: :object,
         properties: %{
           build_system: %Schema{
             type: :string,
             description: "The build system, `xcode` first, then `gradle`, `mix` and `cargo`. Recorded on the impact run."
           },
           head_sha: %Schema{
             type: :string,
             description:
               "The pull request head, or the checked-out commit outside pull requests. Used for display and branch history."
           },
           commit_sha: %Schema{
             type: :string,
             description:
               "The checked-out commit the diff ran against, such as the synthetic merge commit. Defaults to `head_sha`. Keys the diff."
           },
           parent_shas: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "The parents of the checked-out commit, as sent to the baseline request, so the server can resolve the same baseline again."
           },
           ancestor_shas: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "The checked-out commit's ancestors, as sent to the baseline request, so the server can resolve the same baseline again."
           },
           baseline_sha: %Schema{
             type: :string,
             description: "The baseline the baseline request returned. When absent, `fallback_reason` says why."
           },
           fallback_reason: %Schema{
             type: :string,
             description:
               "The baseline request's reason, `excluded_branch` on the project's default branch, or `history_unavailable` when deepening didn't reach the baseline within its budget. The server records a fallback without running the rules."
           },
           changed_files: %Schema{
             type: :array,
             description:
               "The files that differ between the baseline and the checked-out commit, plus dirty and untracked files. Sent when the baseline request said the diff isn't cached, or when the checkout is dirty. At most 5,000 entries: past that, the first 5,000 in path order, with the total in `changed_files_count`.",
             items: %Schema{
               type: :object,
               properties: %{
                 path: %Schema{type: :string, description: "The repository-relative path."},
                 status: %Schema{type: :string, description: "The change, as `git diff --raw` reports it."},
                 blob: %Schema{
                   type: :string,
                   description: "The file's blob in the checkout. Required except for deleted files."
                 },
                 affected_modules: %Schema{
                   type: :array,
                   items: %Schema{type: :string},
                   description:
                     "The test modules the file can affect, from the client's project graph. An empty list means no target owns the file; absent means the client couldn't classify it."
                 }
               },
               required: [:path, :status]
             }
           },
           changed_files_count: %Schema{
             type: :integer,
             description:
               "Sent with `changed_files`: the total number of changed files, larger than the list when it was capped."
           },
           dirty: %Schema{
             type: :boolean,
             default: false,
             description: "Whether the checkout had dirty or untracked files. When true, the diff isn't stored or reused."
           },
           modules: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "The test modules left to decide: what the invocation asked for, minus the targets whose hash matched. Absent when neither narrowed the scope, meaning every module the baseline measured."
           },
           platform: %Schema{
             type: :string,
             description: "The platform the tests run on. Absent where the build system has none."
           },
           git_branch: %Schema{type: :string, description: "The git branch, shown on the overview."},
           xcode: @xcode_schema
         },
         required: [:build_system, :head_sha]
       }},
    responses: %{
      ok: {"The impact run", "application/json", Run},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      too_many_requests: Responses.authorization_throttled(),
      not_found: {"The project doesn't exist or test impact analysis isn't enabled for it", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create_run(%{assigns: %{selected_project: selected_project}} = conn, _params) do
    if FeatureFlags.test_impact_analysis_enabled?(selected_project.account, selected_project) do
      {:ok, %{run: run, skipped_tests: skipped_tests}} = Runs.create(selected_project, conn.body_params)
      json(conn, run_response(run, skipped_tests))
    else
      conn
      |> put_status(:not_found)
      |> json(%{message: "Test impact analysis isn't enabled for this project."})
    end
  end

  defp run_response(%{outcome: "selected"} = run, skipped_tests) do
    %{
      id: run.id,
      outcome: run.outcome,
      counts: %{requested: run.requested_count, selected: run.selected_count, skipped: run.skipped_count},
      skipped_tests: skipped_tests
    }
  end

  defp run_response(run, _skipped_tests) do
    %{id: run.id, outcome: run.outcome}
    |> put_present(:reason, run.reason)
    |> put_present(:matched_path, run.matched_path)
  end

  defp put_present(response, _key, value) when value in [nil, ""], do: response
  defp put_present(response, key, value), do: Map.put(response, key, value)
end
