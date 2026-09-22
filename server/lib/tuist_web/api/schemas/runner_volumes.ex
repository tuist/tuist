defmodule TuistWeb.API.Schemas.RunnerVolumes do
  @moduledoc "Shared HTTP and MCP contracts for the public volume surface."
  alias OpenApiSpex.Schema

  def volume do
    object("RunnerVolume", %{
      id: string(),
      key: string(),
      repository: string(),
      provider: string(),
      platform: string(),
      architecture: string(),
      last_used_at: timestamp(true),
      used_bytes: integer(true),
      capacity_bytes: integer(true),
      unmeasured_copies: integer(),
      unmeasured_capacity_copies: integer()
    })
  end

  def usage do
    object("RunnerVolumeJob", %{
      id: string(),
      workflow_job_id: integer(),
      workflow_run_id: integer(),
      job_name: string(true),
      workflow_name: string(true),
      cache_status: string(),
      cache_status_description: string(),
      cache_hit: %Schema{type: :boolean, nullable: true},
      used_bytes: integer(true),
      capacity_bytes: integer(true),
      mounted_at: timestamp(true)
    })
  end

  def pagination do
    object("RunnerVolumePagination", %{
      current_page: integer(),
      page_size: integer(),
      total_count: integer(),
      total_pages: integer(),
      has_next_page: %Schema{type: :boolean},
      has_previous_page: %Schema{type: :boolean}
    })
  end

  def response(:list), do: object("RunnerVolumeList", %{volumes: array(volume()), pagination_metadata: pagination()})
  def response(:show), do: volume()
  def response(:jobs), do: object("RunnerVolumeJobs", %{jobs: array(usage()), pagination_metadata: pagination()})

  def response(:job_volumes) do
    object("RunnerJobVolumes", %{volumes: array(object("RunnerJobVolume", %{volume: volume(), usage: usage()}))})
  end

  def response(:clear), do: object("RunnerVolumeCleared", %{id: string(), cleared: %Schema{type: :boolean}})

  def response(:analytics) do
    activity =
      object("RunnerVolumeActivity", %{
        job_runs: integer(),
        hit_rate: number(true),
        points:
          array(object("RunnerVolumeActivityPoint", %{at: timestamp(), job_runs: integer(), hit_rate: number(true)}))
      })

    trend = object("RunnerVolumeTrend", %{change: number(true), percent: number(true)})

    object("RunnerVolumeAnalytics", %{
      period: object("RunnerVolumePeriod", %{start: timestamp(), end: timestamp()}),
      storage:
        array(
          object("RunnerVolumeStoragePoint", %{
            at: timestamp(),
            volumes: integer(),
            used_bytes: integer(true),
            capacity_bytes: integer(true),
            unmeasured_copies: integer(),
            unmeasured_capacity_copies: integer()
          })
        ),
      activity: activity,
      previous_activity: activity,
      trends: object("RunnerVolumeTrends", %{volumes: trend, used_bytes: trend, hit_rate_percentage_points: number(true)})
    })
  end

  def inputs(action) do
    base = %{account_handle: %Schema{type: :string, minLength: 1}}

    fields =
      case action do
        :list ->
          Map.merge(page_inputs(), %{
            name: %Schema{type: :string, minLength: 1, maxLength: 200, description: "Exact volume name (cache key)."},
            repository: %Schema{
              type: :string,
              minLength: 1,
              maxLength: 200,
              description: "Exact repository name, including its owner or namespace."
            },
            sort_by: %Schema{type: :string, enum: ["volume", "repository", "used_space", "capacity", "last_used"]},
            sort_order: %Schema{type: :string, enum: ["asc", "desc"]}
          })

        :jobs ->
          Map.put(page_inputs(), :volume_id, uuid())

        :job_volumes ->
          %{workflow_job_id: %Schema{type: :integer, minimum: 1}}

        :analytics ->
          %{volume_id: uuid(), start: timestamp(), end: timestamp()}

        _ ->
          %{volume_id: uuid()}
      end

    required =
      case action do
        a when a in [:show, :jobs, :clear] -> [:account_handle, :volume_id]
        :job_volumes -> [:account_handle, :workflow_job_id]
        _ -> [:account_handle]
      end

    %{object(nil, Map.merge(base, fields)) | required: required}
  end

  def parameters(action) do
    schema = inputs(action)

    schema.properties
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, type} ->
      location =
        if key in [:account_handle, :workflow_job_id] or (key == :volume_id and action != :analytics),
          do: :path,
          else: :query

      {key, [in: location, type: type, required: key in schema.required]}
    end)
  end

  def json_schema(%Schema{} = schema) do
    type = Atom.to_string(schema.type)
    base = %{"type" => if(schema.nullable, do: [type, "null"], else: type)}

    base =
      if schema.properties,
        do:
          Map.merge(base, %{
            "properties" => Map.new(schema.properties, fn {key, value} -> {to_string(key), json_schema(value)} end),
            "required" => Enum.map(schema.required, &to_string/1),
            "additionalProperties" => false
          }),
        else: base

    base = if schema.items, do: Map.put(base, "items", json_schema(schema.items)), else: base

    Enum.reduce([:enum, :minimum, :maximum, :minLength, :maxLength, :format], base, fn key, acc ->
      if value = Map.get(schema, key), do: Map.put(acc, to_string(key), value), else: acc
    end)
  end

  defp page_inputs do
    %{
      page: %Schema{type: :integer, minimum: 1, maximum: 100_000},
      page_size: %Schema{type: :integer, minimum: 1, maximum: 100}
    }
  end

  defp object(title, fields),
    do: %Schema{
      title: title,
      type: :object,
      properties: fields,
      required: Enum.sort(Map.keys(fields)),
      additionalProperties: false
    }

  defp array(items), do: %Schema{type: :array, items: items}
  defp string(nullable \\ false), do: %Schema{type: :string, nullable: nullable}
  defp integer(nullable \\ false), do: %Schema{type: :integer, nullable: nullable}
  defp number(nullable), do: %Schema{type: :number, nullable: nullable}
  defp timestamp(nullable \\ false), do: %Schema{type: :string, format: "date-time", nullable: nullable}
  defp uuid, do: %Schema{type: :string, format: "uuid"}
end
