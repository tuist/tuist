defmodule Tuist.MCP.Components.Tools.BuildEntityTool do
  @moduledoc false

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Params
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.BuildEntities.Resources
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Tool

  # The persistent kinds exposed over MCP. Cache actions stay available through
  # REST and the dashboard, and their run-level cache tools are unchanged.
  @kinds [:gradle_tasks, :xcode_modules, :once_actions, :mix_files, :mix_modules, :bazel_actions]

  @kind_descriptions """
  Kinds: `bazel_actions` (Bazel actions identified by target label, mnemonic and configured primary output; history lists BEP-reported executions, not cache traffic), `gradle_tasks` (Gradle tasks; history lists task executions), \
  `xcode_modules` (Xcode modules; history lists measured compilations and module cache events), \
  `once_actions` (Once actions identified by declared target, capability and action index; \
  history lists executions), `mix_files` (Mix compiled files; history lists compilations) and \
  `mix_modules` (Mix compiled modules; durations measure the containing file's compilation, \
  not independently measured module work). A kind is only available for projects using its \
  build toolchain.\
  """

  defmacro __using__(opts) do
    action = Keyword.fetch!(opts, :action)
    {name, title, summary} = definition(action)
    input_schema = input(action)
    output_schema = output(action)

    quote do
      use Tuist.MCP.Tool,
        name: unquote(name),
        title: unquote(title),
        read_only_hint: true,
        authorize: [action: :read, category: :build],
        schema: unquote(Macro.escape(input_schema)),
        output_schema: unquote(Macro.escape(output_schema))

      alias Tuist.MCP.Components.Tools.BuildEntityTool

      @impl EMCP.Tool
      def description, do: unquote(summary <> " " <> @kind_descriptions)

      def execute(_conn, args, project) do
        BuildEntityTool.run(project, args, unquote(action))
      end
    end
  end

  def kinds, do: @kinds

  def definition(:index),
    do:
      {"list_build_entities", "List Build Entities",
       "List the tasks, modules, actions or files of one kind seen across a project's builds, with stable IDs independent of any run."}

  def definition(:show),
    do:
      {"get_build_entity", "Get Build Entity",
       "Get one build entity by the stable ID a list call returned, with its native identity and analytics for the chosen period."}

  def definition(:history),
    do:
      {"list_build_entity_history", "List Build Entity History",
       "List the recorded executions, compilations or cache events of one build entity, newest first, using the stable ID a list call returned."}

  def input(action) do
    properties = %{
      "account_handle" => %{"type" => "string", "description" => "The account handle."},
      "project_handle" => %{"type" => "string", "description" => "The project handle."},
      "kind" => %{
        "type" => "string",
        "enum" => Enum.map(@kinds, &Atom.to_string/1),
        "description" => "The kind of build entity."
      },
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

    {properties, required} =
      case action do
        :index ->
          {properties
           |> Map.drop(~w(after before))
           |> Map.put("q", %{"type" => "string", "description" => "Search names and identity."}),
           ["account_handle", "project_handle", "kind"]}

        action ->
          properties = if action == :show, do: Map.drop(properties, ~w(after before page page_size)), else: properties

          {Map.put(properties, "id", %{"type" => "string", "description" => "Stable ID returned by list_build_entities."}),
           ["account_handle", "project_handle", "kind", "id"]}
      end

    %{"type" => "object", "properties" => properties, "required" => required, "additionalProperties" => false}
  end

  def output(action) do
    kind = %{"type" => "string", "enum" => Enum.map(@kinds, &Atom.to_string/1)}

    case action do
      :index ->
        object(%{
          "kind" => kind,
          "entities" => %{"type" => "array", "items" => entity()},
          "pagination_metadata" => Tool.pagination_metadata_schema()
        })

      :show ->
        object(%{
          "kind" => kind,
          "entity" => entity(),
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
          "kind" => kind,
          "history" => %{"type" => "array", "items" => observation()},
          "pagination_metadata" => history_pagination()
        })
    end
  end

  # Runs after `Tuist.MCP.Tool` has authorized the project, and checks the
  # rollout flag before any query.
  def run(project, args, action) do
    with :ok <- enabled(project),
         {:ok, key} <- kind(args),
         resource = Resources.fetch!(key),
         true <- project.build_system == resource.system,
         {:ok, filters} <- Params.parse(args) do
      query(project.id, args, action, resource, filters)
    else
      false -> {:error, "This kind is not available for this project's build toolchain."}
      {:error, message} -> {:error, message}
    end
  rescue
    QueryLimitError -> {:error, "The query exceeded analytics limits. Please try again later."}
  end

  defp enabled(project) do
    if FeatureFlags.build_entities_enabled?(project),
      do: :ok,
      else: {:error, "Build entities are not available for this project."}
  end

  defp kind(args) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == Map.get(args, "kind"))) do
      nil -> {:error, "Use one of the supported build entity kinds."}
      key -> {:ok, key}
    end
  end

  defp query(project_id, _args, :index, resource, filters) do
    {entries, meta} =
      BuildEntities.list(project_id, resource.system, resource.kind, Keyword.put(filters, :include_metrics, false))

    {:ok, %{"kind" => Atom.to_string(resource.key), "entities" => entries, "pagination_metadata" => meta}}
  end

  defp query(project_id, args, action, resource, filters) do
    id = Map.fetch!(args, "id")

    case BuildEntities.get(project_id, resource.system, resource.kind, id) do
      {:ok, entity} ->
        detail(project_id, id, action, resource, entity, filters)

      _ ->
        {:error, "Not found in this project."}
    end
  end

  defp detail(project_id, id, :show, resource, entity, filters) do
    analytics = BuildEntities.analytics(project_id, resource.system, resource.kind, id, filters)
    {:ok, %{"kind" => Atom.to_string(resource.key), "entity" => entity, "analytics" => analytics}}
  end

  defp detail(project_id, id, :history, resource, _entity, filters) do
    {observations, meta} = BuildEntities.history(project_id, resource.system, resource.kind, id, filters)
    {:ok, %{"kind" => Atom.to_string(resource.key), "history" => observations, "pagination_metadata" => meta}}
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
