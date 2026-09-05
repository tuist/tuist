defmodule Tuist.MCP.Components.Tools.ModuleCacheTools do
  @moduledoc false

  alias Tuist.Builds.Analytics

  @max_limit 200

  @doc """
  Builds the option list the module cache analytics functions take from the tool
  arguments, or an error when a datetime argument does not parse.

  Absent options are dropped rather than passed as nil so the analytics layer
  applies its own defaults: a 30 day window, and no environment or branch filter.
  """
  def analytics_opts(project, args) do
    with {:ok, start_datetime} <- parse_datetime(args, "start_datetime"),
         {:ok, end_datetime} <- parse_datetime(args, "end_datetime") do
      opts =
        Enum.reject(
          [
            project_id: project.id,
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            is_ci: boolean_or_nil(Map.get(args, "is_ci")),
            git_branch: blank_to_nil(Map.get(args, "git_branch"))
          ],
          fn {_key, value} -> is_nil(value) end
        )

      {:ok, opts}
    end
  end

  def limit(args, default) do
    case Map.get(args, "limit") do
      value when is_integer(value) and value > 0 -> min(value, @max_limit)
      _ -> default
    end
  end

  def module_name(args) do
    case blank_to_nil(Map.get(args, "name")) do
      nil -> {:error, "Provide the name of the module."}
      name -> {:ok, name}
    end
  end

  @doc """
  The number of modules the project has on `git_branch`, falling back to the
  project's default branch when the caller did not filter by one. Counting every
  module seen in the window instead would include ones since renamed or removed.
  """
  def module_count(project, opts) do
    branch = Keyword.get(opts, :git_branch) || project.default_branch || "main"
    {branch, Analytics.module_count(Keyword.put(opts, :git_branch, branch))}
  end

  def invalidation_row_schema_properties do
    %{
      "name" => %{"type" => "string"},
      "product" => %{"type" => "string"},
      "appearances" => %{"type" => "integer", "description" => "Builds the module took part in."},
      "invalidations" => %{"type" => "integer", "description" => "Builds where it was a cache miss."},
      "invalidation_rate" => %{"type" => "number"},
      "hit_rate" => %{"type" => "number"},
      "self_changes" => %{
        "type" => "integer",
        "description" => "Invalidations where the module's own content changed."
      },
      "dependency_induced" => %{
        "type" => "integer",
        "description" => "Invalidations where only a dependency changed."
      },
      "unclassified" => %{
        "type" => "integer",
        "description" => "Invalidations with no comparable prior build: first-seen, cold or evicted."
      },
      "blast_radius" => %{
        "type" => ["integer", "null"],
        "description" =>
          "How many modules transitively depend on this one, or null when no build carries dependency edges."
      }
    }
  end

  def invalidation_row_required do
    ~w(name product appearances invalidations invalidation_rate hit_rate self_changes dependency_induced unclassified blast_radius)
  end

  def invalidation_row(row) do
    %{
      name: row.name,
      product: row.product,
      appearances: row.appearances,
      invalidations: row.invalidations,
      invalidation_rate: row.invalidation_rate,
      hit_rate: row.hit_rate,
      self_changes: row.self_changes,
      dependency_induced: row.dependency_induced,
      unclassified: row.unclassified,
      blast_radius: row.blast_radius
    }
  end

  @doc """
  The arguments every module cache tool takes: the project it reads, the window
  it reads over, and the two filters the dashboards offer.
  """
  def project_schema_properties do
    %{
      "account_handle" => %{
        "type" => "string",
        "description" => "The account handle (organization or user)."
      },
      "project_handle" => %{"type" => "string", "description" => "The project handle."},
      "start_datetime" => %{
        "type" => "string",
        "description" => "Inclusive ISO 8601 start of the window. Defaults to 30 days ago."
      },
      "end_datetime" => %{
        "type" => "string",
        "description" => "Inclusive ISO 8601 end of the window. Defaults to now."
      },
      "is_ci" => %{
        "type" => "boolean",
        "description" => "Restrict to CI (true) or local (false) runs. Covers both when omitted."
      },
      "git_branch" => %{"type" => "string", "description" => "Restrict to a single git branch."}
    }
  end

  def cursor_pagination_metadata(page) do
    %{
      has_next_page: page.has_next_page,
      has_previous_page: page.has_previous_page,
      start_cursor: page.start_cursor,
      end_cursor: page.end_cursor
    }
  end

  def cursor_pagination_metadata_schema do
    %{
      "type" => "object",
      "properties" => %{
        "has_next_page" => %{"type" => "boolean"},
        "has_previous_page" => %{"type" => "boolean"},
        "start_cursor" => %{"type" => ["string", "null"]},
        "end_cursor" => %{"type" => ["string", "null"]}
      },
      "required" => ["has_next_page", "has_previous_page", "start_cursor", "end_cursor"],
      "additionalProperties" => false
    }
  end

  defp parse_datetime(args, key) do
    case blank_to_nil(Map.get(args, key)) do
      nil ->
        {:ok, nil}

      value ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          _ -> {:error, "#{key} must be an ISO 8601 datetime."}
        end
    end
  end

  defp boolean_or_nil(value) when is_boolean(value), do: value
  defp boolean_or_nil(_value), do: nil

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end

defmodule Tuist.MCP.Components.Tools.ListXcodeModuleInvalidations do
  @moduledoc """
  Rank a project's modules by how often the module cache invalidated them, and split each module's invalidations into the ones its own content caused and the ones a dependency caused. Only available for projects with build_system=xcode.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_module_invalidations",
    title: "List Xcode Module Invalidations",
    read_only_hint: true,
    authorize: [action: :read, category: :run],
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Tuist.MCP.Components.Tools.ModuleCacheTools.project_schema_properties(), "limit", %{
          "type" => "integer",
          "description" => "Modules to return, most invalidated first (default: 30, max: 200)."
        }),
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "modules" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => Tuist.MCP.Components.Tools.ModuleCacheTools.invalidation_row_schema_properties(),
            "required" => Tuist.MCP.Components.Tools.ModuleCacheTools.invalidation_row_required(),
            "additionalProperties" => false
          }
        },
        "module_count" => %{
          "type" => "integer",
          "description" => "Modules on the project's latest commit on module_count_branch."
        },
        "module_count_branch" => %{"type" => "string"}
      },
      "required" => ["modules", "module_count", "module_count_branch"],
      "additionalProperties" => false
    }

  alias Tuist.Builds.Analytics
  alias Tuist.MCP.Components.Tools.ModuleCacheTools

  @impl EMCP.Tool
  def description,
    do:
      "Rank a project's modules by how often the module cache invalidated them, and split each module's invalidations into the ones its own content caused (self_changes) and the ones a dependency caused (dependency_induced). Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    case ModuleCacheTools.analytics_opts(project, args) do
      {:ok, opts} ->
        modules = opts |> Keyword.put(:limit, ModuleCacheTools.limit(args, 30)) |> Analytics.module_invalidations()
        {branch, count} = ModuleCacheTools.module_count(project, opts)

        {:ok,
         %{
           modules: Enum.map(modules, &ModuleCacheTools.invalidation_row/1),
           module_count: count,
           module_count_branch: branch
         }}

      {:error, message} ->
        {:error, message}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetXcodeModule do
  @moduledoc """
  Get one module's cache invalidation summary together with its place in the project's dependency graph: what it is invalidated by, and what it invalidates downstream. Only available for projects with build_system=xcode.
  """

  use Tuist.MCP.Tool,
    name: "get_xcode_module",
    title: "Get Xcode Module",
    read_only_hint: true,
    authorize: [action: :read, category: :run],
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Tuist.MCP.Components.Tools.ModuleCacheTools.project_schema_properties(), "name", %{
          "type" => "string",
          "description" => "The module name."
        }),
      "required" => ["account_handle", "project_handle", "name"]
    },
    output_schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(Tuist.MCP.Components.Tools.ModuleCacheTools.invalidation_row_schema_properties(), %{
          "depends_on" => %{
            "type" => ["array", "null"],
            "items" => %{"type" => "string"},
            "description" =>
              "The modules this one directly depends on, from the dependency graph of the project's latest commit. Null when no build carries dependency edges. These are graph edges, not the dependencies subhash returned by list_xcode_module_cache_targets."
          },
          "dependents" => %{
            "type" => ["array", "null"],
            "items" => %{"type" => "string"},
            "description" => "The modules that directly depend on this one."
          },
          "transitive_dependents" => %{
            "type" => ["array", "null"],
            "items" => %{"type" => "string"},
            "description" => "Everything this module invalidates downstream when it changes. Sized by blast_radius."
          }
        }),
      "required" =>
        Tuist.MCP.Components.Tools.ModuleCacheTools.invalidation_row_required() ++
          ["depends_on", "dependents", "transitive_dependents"],
      "additionalProperties" => false
    }

  alias Tuist.Builds.Analytics
  alias Tuist.MCP.Components.Tools.ModuleCacheTools

  @impl EMCP.Tool
  def description,
    do:
      "Get one module's cache invalidation summary together with its place in the project's dependency graph: what it is invalidated by (depends_on), and what it invalidates downstream (dependents, transitive_dependents). Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    with {:ok, name} <- ModuleCacheTools.module_name(args),
         {:ok, opts} <- ModuleCacheTools.analytics_opts(project, args) do
      scoped = Keyword.put(opts, :name, name)
      neighbors = Analytics.module_neighbors(scoped)

      case Analytics.module_summary(scoped) do
        nil -> {:error, "Module not found: #{name}"}
        row -> {:ok, Map.merge(ModuleCacheTools.invalidation_row(row), neighbors)}
      end
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListXcodeModuleBuilds do
  @moduledoc """
  Walk one module's build history newest first, one row per build it took part in, each saying whether the module cache hit and why it missed. Only available for projects with build_system=xcode.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_module_builds",
    title: "List Xcode Module Builds",
    read_only_hint: true,
    authorize: [action: :read, category: :run],
    schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(Tuist.MCP.Components.Tools.ModuleCacheTools.project_schema_properties(), %{
          "name" => %{"type" => "string", "description" => "The module name."},
          "commit_sha" => %{
            "type" => "string",
            "description" => "Restrict to commits whose sha starts with this prefix."
          },
          "reason" => %{
            "type" => "string",
            "enum" => ["hit", "changed", "upstream", "cold"],
            "description" =>
              "Restrict to builds with this outcome: hit, changed (own content differed), upstream (only a dependency differed) or cold (no comparable prior build)."
          },
          "order" => %{
            "type" => "string",
            "enum" => ["asc", "desc"],
            "description" => "Newest first (desc, the default) or oldest first (asc)."
          },
          "limit" => %{"type" => "integer", "description" => "Rows per page (default: 25, max: 200)."},
          "after" => %{"type" => "string", "description" => "end_cursor of a previous page, to read the next one."},
          "before" => %{"type" => "string", "description" => "start_cursor of a previous page, to read the one before."}
        }),
      "required" => ["account_handle", "project_handle", "name"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "builds" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "run_id" => %{"type" => "string"},
              "scheme" => %{
                "type" => "string",
                "description" => "Empty for commands that produce no activity log, such as generate and cache."
              },
              "ran_at" => %{"type" => "string"},
              "git_branch" => %{"type" => "string"},
              "git_commit_sha" => %{"type" => "string"},
              "cache_status" => %{"type" => "string", "enum" => ["miss", "local", "remote"]},
              "reason" => %{"type" => "string", "enum" => ["hit", "changed", "upstream", "cold"]}
            },
            "required" => ["run_id", "scheme", "ran_at", "git_branch", "git_commit_sha", "cache_status", "reason"],
            "additionalProperties" => false
          }
        },
        "pagination_metadata" => Tuist.MCP.Components.Tools.ModuleCacheTools.cursor_pagination_metadata_schema()
      },
      "required" => ["builds", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Builds.Analytics
  alias Tuist.MCP.Components.Tools.ModuleCacheTools
  alias Tuist.MCP.Formatter

  @impl EMCP.Tool
  def description,
    do:
      "Walk one module's build history newest first, one row per build it took part in, each saying whether the module cache hit and why it missed. Cursor paginated: pass after with a page's end_cursor to walk further back, or before with its start_cursor to walk forward again. Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    with {:ok, name} <- ModuleCacheTools.module_name(args),
         :ok <- validate_cursors(args),
         {:ok, opts} <- ModuleCacheTools.analytics_opts(project, args) do
      page =
        opts
        |> Keyword.put(:name, name)
        |> Keyword.put(:limit, ModuleCacheTools.limit(args, 25))
        |> put_optional(args)
        |> Analytics.module_build_history()

      {:ok,
       %{
         builds: Enum.map(page.rows, &build/1),
         pagination_metadata: ModuleCacheTools.cursor_pagination_metadata(page)
       }}
    end
  end

  defp build(row) do
    %{
      run_id: row.id,
      scheme: row.scheme,
      ran_at: Formatter.iso8601(row.ran_at, naive: :utc),
      git_branch: row.branch,
      git_commit_sha: row.commit_sha,
      cache_status: row.hit,
      reason: row.reason
    }
  end

  @optional_filters [commit_sha: "commit_sha", reason: "reason", order: "order", after: "after", before: "before"]

  defp put_optional(opts, args) do
    Enum.reduce(@optional_filters, opts, fn {key, arg}, acc ->
      case Map.get(args, arg) do
        value when is_binary(value) and value != "" -> Keyword.put(acc, key, value)
        _ -> acc
      end
    end)
  end

  defp validate_cursors(%{"after" => after_cursor, "before" => before_cursor})
       when is_binary(after_cursor) and after_cursor != "" and is_binary(before_cursor) and before_cursor != "",
       do: {:error, "Use only one of after or before."}

  defp validate_cursors(_args), do: :ok
end

defmodule Tuist.MCP.Components.Tools.GetXcodeModuleCacheTimeseries do
  @moduledoc """
  Daily module cache series for a project, or for one module when name is given: invalidations against reuses, why the misses happened, how many modules the project built, and how many modules depended on the named one. Only available for projects with build_system=xcode.
  """

  use Tuist.MCP.Tool,
    name: "get_xcode_module_cache_timeseries",
    title: "Get Xcode Module Cache Timeseries",
    read_only_hint: true,
    authorize: [action: :read, category: :run],
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Tuist.MCP.Components.Tools.ModuleCacheTools.project_schema_properties(), "name", %{
          "type" => "string",
          "description" => "Restrict the cache and miss reason series to one module. Covers every module when omitted."
        }),
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "dates" => %{"type" => "array", "items" => %{"type" => "string"}},
        "invalidations" => %{"type" => "array", "items" => %{"type" => "integer"}},
        "reuses" => %{"type" => "array", "items" => %{"type" => "integer"}},
        "hit_rates" => %{"type" => "array", "items" => %{"type" => "number"}},
        "miss_reasons" => %{
          "type" => "object",
          "properties" => %{
            "changed" => %{"type" => "array", "items" => %{"type" => "integer"}},
            "upstream" => %{"type" => "array", "items" => %{"type" => "integer"}},
            "cold" => %{"type" => "array", "items" => %{"type" => "integer"}}
          },
          "required" => ["changed", "upstream", "cold"],
          "additionalProperties" => false
        },
        "module_counts" => %{
          "type" => "array",
          "items" => %{"type" => "integer"},
          "description" => "Distinct modules the project built each day. Never scoped to name."
        },
        "dependents_counts" => %{
          "type" => ["array", "null"],
          "items" => %{"type" => "integer"},
          "description" => "How many modules transitively depended on name each day. Null when name is omitted."
        }
      },
      "required" => [
        "dates",
        "invalidations",
        "reuses",
        "hit_rates",
        "miss_reasons",
        "module_counts",
        "dependents_counts"
      ],
      "additionalProperties" => false
    }

  alias Tuist.Builds.Analytics
  alias Tuist.MCP.Components.Tools.ModuleCacheTools

  @impl EMCP.Tool
  def description,
    do:
      "Daily module cache series for a project, or for one module when name is given: invalidations against reuses, why the misses happened, how many modules the project built, and how many modules depended on the named one. Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    case ModuleCacheTools.analytics_opts(project, args) do
      {:ok, opts} -> {:ok, timeseries(opts, name(args))}
      {:error, message} -> {:error, message}
    end
  end

  defp timeseries(opts, name) do
    scoped = if name, do: Keyword.put(opts, :name, name), else: opts
    cache = Analytics.module_invalidation_timeseries(scoped)
    miss_reasons = Analytics.module_miss_reasons_timeseries(scoped)

    %{
      dates: cache.dates,
      invalidations: cache.invalidations,
      reuses: cache.reuses,
      hit_rates: hit_rates(cache),
      miss_reasons: %{
        changed: miss_reasons.changed,
        upstream: miss_reasons.upstream,
        cold: miss_reasons.cold
      },
      module_counts: Analytics.modules_timeseries(opts).counts,
      dependents_counts: dependents_counts(scoped, name)
    }
  end

  defp name(args) do
    case Map.get(args, "name") do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp dependents_counts(_scoped, nil), do: nil
  defp dependents_counts(scoped, _name), do: Analytics.module_dependents_timeseries(scoped).counts

  # A day with no build has no rate, so it plots as zero, matching the dashboard.
  defp hit_rates(%{invalidations: invalidations, reuses: reuses}) do
    Enum.zip_with(invalidations, reuses, fn misses, hits ->
      case misses + hits do
        0 -> 0.0
        total -> Float.round(hits / total * 100, 1)
      end
    end)
  end
end
