defmodule Tuist.Sandboxes.Schemas do
  @moduledoc "Shared HTTP and MCP contracts for the public sandbox surface (`Tuist.Sandboxes.Query`)."
  alias OpenApiSpex.Schema
  alias Tuist.Sandboxes.Sandbox

  @statuses ["active", "idle", "starting", "resuming", "paused", "archived", "failed"]
  @sorts ["created", "last_active", "identifier"]

  def statuses, do: @statuses
  def sorts, do: @sorts

  def sandbox do
    %Schema{
      title: "Sandbox",
      description: "A Firecracker sandbox VM.",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: "uuid"},
        state: %Schema{type: :string, enum: Enum.map(Sandbox.states(), &Atom.to_string/1)},
        status: %Schema{
          type: :string,
          description:
            "The status the dashboard shows: `active` while a worker or command runs, `idle` when running without one, `starting` while it boots, `failed` for the `error` state, otherwise the state (`resuming`, `paused`, `archived`). More values may be added."
        },
        template: %Schema{type: :string},
        template_tag: %Schema{type: :string, nullable: true},
        vcpus: %Schema{type: :integer},
        memory_mb: %Schema{type: :integer},
        workspace_gb: %Schema{type: :integer},
        node_name: %Schema{type: :string, nullable: true},
        hostname: %Schema{type: :string, nullable: true},
        agent_environment_id: %Schema{type: :integer, nullable: true},
        amp_orb_id: %Schema{type: :string, nullable: true},
        anthropic_session_id: %Schema{type: :string, nullable: true},
        residency_work_id: %Schema{type: :string, nullable: true},
        last_active_at: %Schema{type: :string, format: "date-time", nullable: true},
        paused_at: %Schema{type: :string, format: "date-time", nullable: true},
        archived_at: %Schema{
          type: :string,
          format: "date-time",
          nullable: true,
          description: "When the paused sandbox's disks were moved to object storage. Set while `state` is `archived`."
        },
        archive_bytes: %Schema{type: :integer, nullable: true, description: "Size of the stored archive in bytes."},
        error_message: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: "date-time"},
        updated_at: %Schema{type: :string, format: "date-time"}
      },
      required: [:id, :state, :template, :vcpus, :memory_mb, :workspace_gb, :inserted_at, :updated_at]
    }
  end

  def pagination do
    object("SandboxPagination", %{
      current_page: integer(),
      page_size: integer(),
      total_count: integer(),
      total_pages: integer(),
      has_next_page: %Schema{type: :boolean},
      has_previous_page: %Schema{type: :boolean}
    })
  end

  def response(:list), do: object("Sandboxes", %{sandboxes: array(sandbox()), pagination_metadata: pagination()})
  def response(:delete), do: object("SandboxDeleted", %{id: %Schema{type: :string, format: "uuid"}, deleted: boolean()})

  def response(:analytics) do
    resources = fn title -> object(title, %{vcpus: integer(), memory_gb: number(), disk_gb: number()}) end

    object("SandboxAnalytics", %{
      period: object("SandboxAnalyticsPeriod", %{start: timestamp(), end: timestamp()}),
      bucket: %Schema{
        type: :string,
        description: "`hour` for ranges of up to 36 hours, otherwise `day`: the span of each point."
      },
      vcpu_hours: %Schema{
        type: :number,
        description: "vCPU-hours sandboxes ran in the range: each running hour of a sandbox counts its vCPUs."
      },
      created:
        object("SandboxAnalyticsCount", %{
          count: integer(),
          trend: trend(),
          points: array(object("SandboxAnalyticsCountPoint", %{at: timestamp(), value: integer()}))
        }),
      session_duration: duration("SandboxAnalyticsSessionDuration", "Run sessions that ended in the range."),
      setup: duration("SandboxAnalyticsSetup", "How long Amp Orbs' `.agents/setup` ran."),
      time_to_start: duration("SandboxAnalyticsTimeToStart", "How long sandboxes took to boot (create or restore)."),
      concurrency:
        object("SandboxAnalyticsConcurrency", %{
          limits: resources.("SandboxResourceLimits"),
          in_use: resources.("SandboxResourcesInUse"),
          points:
            array(
              object("SandboxAnalyticsConcurrencyPoint", %{
                at: timestamp(),
                vcpus: integer(),
                memory_gb: number(),
                disk_gb: number()
              })
            )
        })
    })
  end

  def inputs(action) do
    base = %{account_handle: %Schema{type: :string, minLength: 1}}

    fields =
      case action do
        :list ->
          %{
            page: %Schema{type: :integer, minimum: 1, maximum: 100_000},
            page_size: %Schema{type: :integer, minimum: 1, maximum: 100},
            search: %Schema{
              type: :string,
              minLength: 1,
              maxLength: 200,
              description: "Text the sandbox ID, Amp Orb ID or Anthropic session ID contains."
            },
            status: %Schema{type: :string, enum: @statuses},
            vcpus: %Schema{type: :integer, minimum: 1},
            sort_by: %Schema{type: :string, enum: @sorts},
            sort_order: %Schema{type: :string, enum: ["asc", "desc"]}
          }

        :analytics ->
          %{start: timestamp(), end: timestamp()}

        _ ->
          %{sandbox_id: %Schema{type: :string, format: "uuid"}}
      end

    required = if action in [:list, :analytics], do: [:account_handle], else: [:account_handle, :sandbox_id]
    %{object(nil, Map.merge(base, fields)) | required: required}
  end

  def parameters(action) do
    schema = inputs(action)

    schema.properties
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, type} ->
      location = if key in [:account_handle, :sandbox_id], do: :path, else: :query
      {key, [in: location, type: type, required: key in schema.required]}
    end)
  end

  defdelegate json_schema(schema), to: Tuist.Runners.CacheVolumes.Schemas

  defp duration(title, description) do
    ms = %Schema{type: :integer, nullable: true}

    %{
      object(title, %{
        count: integer(),
        avg_ms: integer(),
        p50_ms: integer(),
        p90_ms: integer(),
        p99_ms: integer(),
        trend_avg: trend(),
        trend_p50: trend(),
        trend_p90: trend(),
        trend_p99: trend(),
        points: array(object(title <> "Point", %{at: timestamp(), avg_ms: ms, p50_ms: ms, p90_ms: ms, p99_ms: ms}))
      })
      | description: description <> " Points without any have null figures."
    }
  end

  defp trend,
    do: %Schema{
      type: :number,
      description: "Percent change against the range of the same length before it; 0 when either is 0."
    }

  defp object(title, fields),
    do: %Schema{
      title: title,
      type: :object,
      properties: fields,
      required: Enum.sort(Map.keys(fields)),
      additionalProperties: false
    }

  defp array(items), do: %Schema{type: :array, items: items}
  defp integer, do: %Schema{type: :integer}
  defp number, do: %Schema{type: :number}
  defp boolean, do: %Schema{type: :boolean}
  defp timestamp, do: %Schema{type: :string, format: "date-time"}
end
