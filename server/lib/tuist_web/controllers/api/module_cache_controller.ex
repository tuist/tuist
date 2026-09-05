defmodule TuistWeb.API.ModuleCacheController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds.Analytics
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :run)

  tags ["Module cache"]

  @account_handle [in: :path, type: :string, required: true, description: "The handle of the account."]
  @project_handle [in: :path, type: :string, required: true, description: "The handle of the project."]
  @module_name [in: :path, type: :string, required: true, description: "The name of the module."]

  @start_datetime [
    in: :query,
    type: %Schema{type: :string, format: :"date-time"},
    description: "Inclusive start of the window. Defaults to 30 days ago."
  ]
  @end_datetime [
    in: :query,
    type: %Schema{type: :string, format: :"date-time"},
    description: "Inclusive end of the window. Defaults to now."
  ]
  @is_ci [
    in: :query,
    type: :boolean,
    description: "Restrict to runs executed on CI (true) or locally (false). Covers both when omitted."
  ]
  @git_branch [in: :query, type: :string, description: "Restrict to a single git branch."]

  @module_properties %{
    name: %Schema{type: :string, description: "The module name."},
    product: %Schema{type: :string, description: "The product the module builds."},
    appearances: %Schema{type: :integer, description: "Builds the module took part in."},
    invalidations: %Schema{type: :integer, description: "Builds where the module was a cache miss."},
    invalidation_rate: %Schema{type: :number, description: "Percentage of appearances that were misses."},
    hit_rate: %Schema{type: :number, description: "Percentage of appearances that were hits."},
    self_changes: %Schema{type: :integer, description: "Invalidations caused by the module's own content changing."},
    dependency_induced: %Schema{type: :integer, description: "Invalidations caused only by a dependency changing."},
    unclassified: %Schema{
      type: :integer,
      description: "Invalidations with no comparable prior build: first-seen, cold or evicted."
    },
    blast_radius: %Schema{
      type: :integer,
      nullable: true,
      description:
        "How many modules transitively depend on this one, or null when no build in the window carries dependency edges."
    }
  }

  @module_required [
    :name,
    :product,
    :appearances,
    :invalidations,
    :invalidation_rate,
    :hit_rate,
    :self_changes,
    :dependency_induced,
    :unclassified
  ]

  operation(:index,
    summary: "List a project's modules ranked by module cache invalidations.",
    operation_id: "listModuleCacheModules",
    parameters: [
      account_handle: @account_handle,
      project_handle: @project_handle,
      start_datetime: @start_datetime,
      end_datetime: @end_datetime,
      is_ci: @is_ci,
      git_branch: @git_branch,
      limit: [
        in: :query,
        type: %Schema{
          title: "ModuleCacheModulesLimit",
          description: "The maximum number of modules to return, most invalidated first.",
          type: :integer,
          default: 30,
          minimum: 1,
          maximum: 200
        }
      ]
    ],
    responses: %{
      ok:
        {"List of modules", "application/json",
         %Schema{
           type: :object,
           properties: %{
             modules: %Schema{
               type: :array,
               items: %Schema{type: :object, properties: @module_properties, required: @module_required}
             },
             module_count: %Schema{
               type: :integer,
               description: "The number of modules on the project's latest commit on module_count_branch."
             },
             module_count_branch: %Schema{
               type: :string,
               description: "The branch module_count was read from: git_branch, or the project's default branch."
             }
           },
           required: [:modules, :module_count, :module_count_branch]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    opts = analytics_opts(project, params)
    limit = Map.get(params, :limit, 30)
    modules = opts |> Keyword.put(:limit, limit) |> Analytics.module_invalidations()
    branch = Keyword.get(opts, :git_branch) || project.default_branch || "main"

    json(conn, %{
      modules: Enum.map(modules, &module_json/1),
      module_count: Analytics.module_count(Keyword.put(opts, :git_branch, branch)),
      module_count_branch: branch
    })
  end

  operation(:show,
    summary: "Get a module's cache invalidations and its dependency graph neighbours.",
    operation_id: "getModuleCacheModule",
    parameters: [
      account_handle: @account_handle,
      project_handle: @project_handle,
      module_name: @module_name,
      start_datetime: @start_datetime,
      end_datetime: @end_datetime,
      is_ci: @is_ci,
      git_branch: @git_branch
    ],
    responses: %{
      ok:
        {"The module", "application/json",
         %Schema{
           type: :object,
           properties:
             Map.merge(@module_properties, %{
               depends_on: %Schema{
                 type: :array,
                 items: %Schema{type: :string},
                 nullable: true,
                 description:
                   "The modules this one directly depends on, from the dependency graph of the project's latest commit. Null when no build in the window carries dependency edges. These are graph edges, not the `dependencies` entry of a target's subhashes."
               },
               dependents: %Schema{
                 type: :array,
                 items: %Schema{type: :string},
                 nullable: true,
                 description: "The modules that directly depend on this one."
               },
               transitive_dependents: %Schema{
                 type: :array,
                 items: %Schema{type: :string},
                 nullable: true,
                 description: "Every module this one invalidates downstream when it changes. Sized by blast_radius."
               }
             }),
           required: @module_required
         }},
      not_found: {"Module not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def show(%{assigns: %{selected_project: project}, params: %{module_name: name} = params} = conn, _params) do
    opts = project |> analytics_opts(params) |> Keyword.put(:name, name)

    case Analytics.module_summary(opts) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Module not found."})

      row ->
        json(conn, Map.merge(module_json(row), Analytics.module_neighbors(opts)))
    end
  end

  operation(:builds,
    summary: "List the builds a module took part in, with why the module cache missed.",
    operation_id: "listModuleCacheModuleBuilds",
    parameters: [
      account_handle: @account_handle,
      project_handle: @project_handle,
      module_name: @module_name,
      start_datetime: @start_datetime,
      end_datetime: @end_datetime,
      is_ci: @is_ci,
      git_branch: @git_branch,
      commit_sha: [in: :query, type: :string, description: "Restrict to commits whose sha starts with this prefix."],
      reason: [
        in: :query,
        type: %Schema{
          title: "ModuleCacheBuildReason",
          type: :string,
          enum: ["hit", "changed", "upstream", "cold"]
        },
        description: "Restrict to builds with this outcome."
      ],
      order: [
        in: :query,
        type: %Schema{
          title: "ModuleCacheBuildsOrder",
          type: :string,
          enum: ["asc", "desc"],
          default: "desc"
        },
        description: "Newest first (desc) or oldest first (asc)."
      ],
      limit: [
        in: :query,
        type: %Schema{
          title: "ModuleCacheBuildsLimit",
          description: "The maximum number of builds to return in a single page.",
          type: :integer,
          default: 25,
          minimum: 1,
          maximum: 200
        }
      ],
      after: [
        in: :query,
        type: :string,
        description: "Pass the `end_cursor` of a previous response to fetch the next page."
      ],
      before: [
        in: :query,
        type: :string,
        description: "Pass the `start_cursor` of a previous response to fetch the previous page."
      ]
    ],
    responses: %{
      ok:
        {"List of builds", "application/json",
         %Schema{
           type: :object,
           properties: %{
             builds: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   run_id: %Schema{type: :string, description: "The ID of the command run."},
                   scheme: %Schema{
                     type: :string,
                     description: "Empty for commands that produce no activity log, such as generate and cache."
                   },
                   ran_at: %Schema{type: :string, format: :"date-time", description: "When the run happened."},
                   git_branch: %Schema{type: :string, description: "The branch the run was on."},
                   git_commit_sha: %Schema{type: :string, description: "The commit the run was on."},
                   cache_status: %Schema{
                     type: :string,
                     enum: ["miss", "local", "remote"],
                     description: "Whether the module cache hit, and from where."
                   },
                   reason: %Schema{
                     type: :string,
                     enum: ["hit", "changed", "upstream", "cold"],
                     description:
                       "Why the module missed: changed (its own content differed), upstream (only a dependency differed) or cold (no comparable prior build)."
                   }
                 },
                 required: [:run_id, :scheme, :ran_at, :git_branch, :git_commit_sha, :cache_status, :reason]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:builds, :pagination_metadata]
         }},
      bad_request: {"The request was invalid", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def builds(%{assigns: %{selected_project: project}, params: %{module_name: name} = params} = conn, _params) do
    if present?(params[:after]) and present?(params[:before]) do
      conn
      |> put_status(:bad_request)
      |> json(%{message: "Use only one of `after` and `before`."})
    else
      limit = Map.get(params, :limit, 25)

      page =
        project
        |> analytics_opts(params)
        |> Keyword.put(:name, name)
        |> Keyword.put(:limit, limit)
        |> put_present(params, [:commit_sha, :reason, :order, :after, :before])
        |> Analytics.module_build_history()

      json(conn, %{
        builds: Enum.map(page.rows, &build_json/1),
        pagination_metadata: %{
          has_next_page: page.has_next_page,
          has_previous_page: page.has_previous_page,
          page_size: limit,
          start_cursor: page.start_cursor,
          end_cursor: page.end_cursor
        }
      })
    end
  end

  operation(:metrics,
    summary: "Daily module cache metrics for a project, or for a single module.",
    operation_id: "moduleCacheMetrics",
    parameters: [
      account_handle: @account_handle,
      project_handle: @project_handle,
      start_datetime: @start_datetime,
      end_datetime: @end_datetime,
      is_ci: @is_ci,
      git_branch: @git_branch,
      name: [
        in: :query,
        type: :string,
        description: "Restrict the cache and miss reason series to one module. Covers every module when omitted."
      ]
    ],
    responses: %{
      ok:
        {"Module cache metrics", "application/json",
         %Schema{
           type: :object,
           properties: %{
             dates: %Schema{type: :array, items: %Schema{type: :string, format: :date}},
             invalidations: %Schema{type: :array, items: %Schema{type: :integer}},
             reuses: %Schema{type: :array, items: %Schema{type: :integer}},
             hit_rates: %Schema{type: :array, items: %Schema{type: :number}},
             miss_reasons: %Schema{
               type: :object,
               properties: %{
                 changed: %Schema{type: :array, items: %Schema{type: :integer}},
                 upstream: %Schema{type: :array, items: %Schema{type: :integer}},
                 cold: %Schema{type: :array, items: %Schema{type: :integer}}
               },
               required: [:changed, :upstream, :cold]
             },
             module_counts: %Schema{
               type: :array,
               items: %Schema{type: :integer},
               description: "Distinct modules the project built each day. Never scoped to `name`."
             },
             dependents_counts: %Schema{
               type: :array,
               items: %Schema{type: :integer},
               nullable: true,
               description: "How many modules transitively depended on `name` each day. Null when `name` is omitted."
             }
           },
           required: [:dates, :invalidations, :reuses, :hit_rates, :miss_reasons, :module_counts]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def metrics(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    opts = analytics_opts(project, params)
    name = if present?(params[:name]), do: params.name
    scoped = if name, do: Keyword.put(opts, :name, name), else: opts

    cache = Analytics.module_invalidation_timeseries(scoped)
    miss_reasons = Analytics.module_miss_reasons_timeseries(scoped)

    json(conn, %{
      dates: cache.dates,
      invalidations: cache.invalidations,
      reuses: cache.reuses,
      hit_rates: hit_rates(cache),
      miss_reasons: Map.take(miss_reasons, [:changed, :upstream, :cold]),
      module_counts: Analytics.modules_timeseries(opts).counts,
      dependents_counts: if(name, do: Analytics.module_dependents_timeseries(scoped).counts)
    })
  end

  defp analytics_opts(project, params) do
    Enum.reject(
      [
        project_id: project.id,
        start_datetime: params[:start_datetime],
        end_datetime: params[:end_datetime],
        is_ci: params[:is_ci],
        git_branch: blank_to_nil(params[:git_branch])
      ],
      fn {_key, value} -> is_nil(value) end
    )
  end

  defp put_present(opts, params, keys) do
    Enum.reduce(keys, opts, fn key, acc ->
      if present?(params[key]), do: Keyword.put(acc, key, params[key]), else: acc
    end)
  end

  defp module_json(row) do
    Map.take(row, [
      :name,
      :product,
      :appearances,
      :invalidations,
      :invalidation_rate,
      :hit_rate,
      :self_changes,
      :dependency_induced,
      :unclassified,
      :blast_radius
    ])
  end

  defp build_json(row) do
    %{
      run_id: row.id,
      scheme: row.scheme,
      ran_at: row.ran_at |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601(),
      git_branch: row.branch,
      git_commit_sha: row.commit_sha,
      cache_status: row.hit,
      reason: row.reason
    }
  end

  # A day with no build has no rate, so it reports as zero, matching the dashboard.
  defp hit_rates(%{invalidations: invalidations, reuses: reuses}) do
    Enum.zip_with(invalidations, reuses, fn misses, hits ->
      case misses + hits do
        0 -> 0.0
        total -> Float.round(hits / total * 100, 1)
      end
    end)
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(value), do: not is_nil(value)

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
