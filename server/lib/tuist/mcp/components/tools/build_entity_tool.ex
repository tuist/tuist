defmodule Tuist.MCP.Components.Tools.BuildEntityTool do
  @moduledoc false

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Params
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.BuildEntities.Resources
  alias Tuist.MCP.Tool

  defmacro __using__(opts) do
    tool_opts = resource(opts)
    input_schema = input(tool_opts)
    output_schema = output(tool_opts)

    quote do
      use Tuist.MCP.Tool,
        name: unquote(Keyword.fetch!(tool_opts, :name)),
        title: unquote(Keyword.fetch!(tool_opts, :title)),
        read_only_hint: true,
        authorize: [action: :read, category: :build],
        schema: unquote(Macro.escape(input_schema)),
        output_schema: unquote(Macro.escape(output_schema))

      alias Tuist.MCP.Components.Tools.BuildEntityTool

      @impl EMCP.Tool
      def description, do: unquote(Keyword.fetch!(tool_opts, :description))

      def execute(_conn, args, project) do
        BuildEntityTool.run(project, args, unquote(tool_opts))
      end
    end
  end

  def resource(opts) do
    resource = Resources.fetch!(Keyword.fetch!(opts, :resource))
    system = resource.system
    kind = resource.kind
    singular = to_string(resource.singular)
    plural = to_string(resource.plural)
    history_key = to_string(resource.history_key)
    label = resource.label
    singular_label = String.replace(resource.label_singular, ~r/^an? /, "")
    action = Keyword.fetch!(opts, :action)

    history_suffix = if kind == "cache_action", do: "events", else: history_key

    {name, title} =
      case action do
        :index -> {"list_#{system}_#{plural}", "List #{label}"}
        :show -> {"get_#{system}_#{singular}", "Get #{singular_label}"}
        :history -> {"list_#{system}_#{singular}_#{history_suffix}", "List #{label} History"}
      end

    note =
      case {system, kind} do
        {:bazel, "cache_action"} ->
          " Cache actions identify exact cache keys/digests, not logical actions across changing inputs. Cache events do not report branch or CI/local provenance."

        {_, "cache_action"} ->
          " Cache actions identify exact cache keys/digests, not logical actions across changing inputs."

        {:mix, "module"} ->
          " Durations measure the containing file compilation, not independently measured module work."

        _ ->
          ""
      end

    [
      action: action,
      system: system,
      kind: kind,
      singular: singular,
      plural: plural,
      history_key: history_key,
      id_param: singular <> "_id",
      name: name,
      title: title,
      description: "#{title} across builds in a project, using stable IDs independent of a run." <> note
    ]
  end

  def input(opts) do
    properties = %{
      "account_handle" => %{"type" => "string", "description" => "The account handle."},
      "project_handle" => %{"type" => "string", "description" => "The project handle."},
      "start_at" => %{"type" => "string", "description" => "Inclusive ISO 8601 start within the last 90 days."},
      "end_at" => %{"type" => "string", "description" => "Exclusive ISO 8601 end, defaulting to now."},
      "environment" => %{"type" => "string", "enum" => ["any", "ci", "local"]},
      "branch" => %{"type" => "string", "description" => "Exact recorded branch."},
      "after" => %{"type" => "string", "maxLength" => 512, "description" => "Opaque cursor for the next history page."},
      "before" => %{
        "type" => "string",
        "maxLength" => 512,
        "description" => "Opaque cursor for the previous history page."
      },
      "page" => %{"type" => "integer", "minimum" => 1, "maximum" => 10_000},
      "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
    }

    properties =
      case opts[:action] do
        :show -> Map.drop(properties, ~w(after before page page_size))
        :index -> Map.drop(properties, ~w(after before))
        :history -> properties
      end

    {properties, required} =
      if opts[:action] == :index do
        {Map.put(properties, "q", %{"type" => "string", "description" => "Search names and identity."}),
         ["account_handle", "project_handle"]}
      else
        id_param = Keyword.fetch!(opts, :id_param)

        {Map.put(properties, id_param, %{
           "type" => "string",
           "description" => "Stable ID returned by the project list tool."
         }), ["account_handle", "project_handle", id_param]}
      end

    %{"type" => "object", "properties" => properties, "required" => required, "additionalProperties" => false}
  end

  def output(opts) do
    case opts[:action] do
      :index ->
        object(%{
          opts[:plural] => %{"type" => "array", "items" => entity()},
          "pagination_metadata" => Tool.pagination_metadata_schema()
        })

      :show ->
        object(%{
          opts[:singular] => entity(),
          "analytics" =>
            object(%{
              "total" => metrics(),
              "previous" => metrics(),
              "points" => %{
                "type" => "array",
                "items" => metrics_point()
              }
            })
        })

      :history ->
        object(%{
          opts[:history_key] => %{"type" => "array", "items" => observation()},
          "pagination_metadata" => history_pagination()
        })
    end
  end

  def run(project, args, opts) do
    with true <- project.build_system == opts[:system],
         {:ok, filters} <- Params.parse(args) do
      query(project.id, args, opts, filters)
    else
      false -> {:error, "This resource is not available for this project's build toolchain."}
      {:error, message} -> {:error, message}
    end
  rescue
    QueryLimitError -> {:error, "The query exceeded analytics limits. Please try again later."}
  end

  defp query(project_id, args, opts, filters) do
    if opts[:action] == :index do
      {entries, meta} = BuildEntities.list(project_id, opts[:system], opts[:kind], filters)
      {:ok, %{opts[:plural] => entries, "pagination_metadata" => meta}}
    else
      detail(project_id, args, opts, filters)
    end
  end

  defp detail(project_id, args, opts, filters) do
    id = Map.fetch!(args, opts[:id_param])

    case BuildEntities.get(project_id, opts[:system], opts[:kind], id) do
      {:ok, entity} ->
        case opts[:action] do
          :show ->
            analytics = BuildEntities.analytics(project_id, opts[:system], opts[:kind], id, filters)
            {:ok, %{opts[:singular] => entity, "analytics" => analytics}}

          :history ->
            {observations, meta} = BuildEntities.history(project_id, opts[:system], opts[:kind], id, filters)
            {:ok, %{opts[:history_key] => observations, "pagination_metadata" => meta}}
        end

      _ ->
        {:error, "Not found in this project."}
    end
  end

  defp entity do
    schema =
      object(%{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "identity" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}},
        "first_seen_at" => %{"type" => "string"},
        "last_seen_at" => %{"type" => "string"}
      })

    put_in(schema, ["properties", "observations"], %{"type" => "integer"})
  end

  defp observation do
    object(%{
      "id" => %{"type" => "string"},
      "parent_id" => %{"type" => "string"},
      "execution_id" => %{"type" => "string"},
      "status" => %{"type" => "string"},
      "cache_status" => %{"type" => "string"},
      "duration_ms" => %{"type" => ["number", "null"]},
      "git_branch" => %{"type" => "string"},
      "git_commit_sha" => %{"type" => "string"},
      "is_ci" => %{"type" => ["boolean", "null"]},
      "observed_at" => %{"type" => "string"}
    })
  end

  defp metrics do
    count = %{"type" => "integer"}
    measurement = %{"type" => ["number", "null"]}

    %{
      "observations" => count,
      "hits" => count,
      "misses" => count,
      "failures" => count,
      "hit_rate" => measurement,
      "avg_duration_ms" => measurement,
      "p50_duration_ms" => measurement,
      "p90_duration_ms" => measurement,
      "p99_duration_ms" => measurement
    }
    |> object()
    |> put_in(["properties", "duration_samples"], %{
      "type" => "integer",
      "minimum" => 0,
      "description" => "Number of observations with a recorded duration, including genuine zero durations."
    })
  end

  defp history_pagination do
    schema = Tool.pagination_metadata_schema()

    properties =
      schema["properties"]
      |> Map.put("current_page", %{"type" => ["integer", "null"]})
      |> Map.put("after", %{"type" => ["string", "null"]})
      |> Map.put("before", %{"type" => ["string", "null"]})

    Map.put(schema, "properties", properties)
  end

  defp metrics_point do
    schema = metrics()

    schema
    |> Map.update!("properties", &Map.put(&1, "date", %{"type" => "string"}))
    |> Map.update!("required", &["date" | &1])
  end

  defp object(properties) do
    %{"type" => "object", "properties" => properties, "required" => Map.keys(properties), "additionalProperties" => false}
  end
end
