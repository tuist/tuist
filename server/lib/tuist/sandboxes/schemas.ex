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
      description: "A persistent Linux or macOS sandbox VM.",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: "uuid"},
        state: %Schema{type: :string, enum: Enum.map(Sandbox.states(), &Atom.to_string/1)},
        status: %Schema{
          type: :string,
          description:
            "The status the dashboard shows: `active` while a worker or command runs, `idle` when running without one, `starting` while it boots, `failed` for the `error` state, otherwise the state (`resuming`, `paused`, `archived`). More values may be added."
        },
        platform: %Schema{type: :string, enum: ["linux", "darwin"], default: "linux"},
        resident: %Schema{type: :boolean, description: "Whether a macOS sandbox retains its process and capacity."},
        template: %Schema{type: :string},
        template_tag: %Schema{type: :string, nullable: true},
        vcpus: %Schema{
          type: :integer,
          description:
            "The vCPUs the VM has. A Linux sandbox has 16 and bursts into them when its node has idle cores; it is guaranteed `guaranteed_vcpus` and billed for the largest of that, the CPU it uses and a quarter vCPU per GiB of its memory. A macOS sandbox holds every vCPU."
        },
        memory_mb: %Schema{type: :integer, description: "The memory the sandbox is guaranteed, in MB."},
        memory_limit_mb: %Schema{
          type: :integer,
          nullable: true,
          description:
            "The memory in MB a Linux sandbox may burst to past `memory_mb` while its node has some free; null when it uses at most `memory_mb`."
        },
        workspace_gb: %Schema{type: :integer},
        guaranteed_vcpus: %Schema{
          type: :number,
          description:
            "The vCPUs the sandbox is guaranteed while it runs: a quarter vCPU per GiB of memory, or what its creator picked if more, for a Linux sandbox; every vCPU for a macOS one."
        },
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
        lifetime_seconds: %Schema{
          type: :integer,
          nullable: true,
          description:
            "How long the sandbox may run after each create, resume or extension. Null for sandboxes an integration (an Amp Orb, a Claude session) owns, which never expire."
        },
        expires_at: %Schema{
          type: :string,
          format: "date-time",
          nullable: true,
          description:
            "When the sandbox's lifetime ends: its running commands are then cancelled and it is paused and archived, keeping its files; resuming it starts a new lifetime. Extend it before a command that may outlast it."
        },
        error_message: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: "date-time"},
        updated_at: %Schema{type: :string, format: "date-time"}
      },
      required: [:id, :state, :template, :vcpus, :memory_mb, :workspace_gb, :inserted_at, :updated_at]
    }
  end

  @doc "The shape a sandbox or agent environment is created with; every field is optional."
  def shape do
    %{
      platform: %Schema{
        type: :string,
        enum: ["linux", "darwin"],
        description: "Omitted: `darwin` when `xcode_version` is set, otherwise `linux`."
      },
      template: %Schema{type: :string, pattern: "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", description: "Sandbox template name."},
      xcode_version: %Schema{
        type: :string,
        nullable: true,
        description:
          "macOS only: the exact Xcode version the sandbox boots, such as `26.1.1`, one of those the server's macOS sandboxes serve. Pass the Xcode the repository builds with: another one, even another patch release, misses its caches and ready snapshot. Implies `platform: darwin`. Omitted, macOS sandboxes boot the default Xcode. A sandbox keeps its Xcode for life."
      },
      vcpus: %Schema{
        type: :integer,
        enum: [2, 4, 8],
        description:
          "With `memory_mb`, the shape. Linux: 2x4096, 4x8192 or 8x16384; the shape picks the memory, and every Linux sandbox boots with 16 vCPUs it bursts into. macOS: 8x8192, 8x16384 or 8x24576."
      },
      memory_mb: %Schema{type: :integer, enum: [4096, 8192, 16_384, 24_576]},
      workspace_gb: %Schema{type: :integer, minimum: 1, maximum: 100}
    }
  end

  @doc "What a sandbox is created with: its shape, its lifetime and, on Linux, the CPU it is guaranteed."
  def create do
    choices = Enum.map(Sandbox.guaranteed_cpu_choices(), &Sandbox.vcpus/1)

    shape()
    |> Map.put(:lifetime_seconds, lifetime())
    |> Map.put(:guaranteed_vcpus, %Schema{
      type: :number,
      minimum: List.first(choices),
      maximum: List.last(choices),
      description:
        "Linux only: the vCPUs the sandbox is guaranteed while it runs, whatever the rest of its node does: #{Enum.join(choices, ", ")}. It is guaranteed a quarter vCPU per GiB of memory without one, and the larger of the two with one. It bursts into idle cores past its guarantee up to its 16 vCPUs, and is billed for at least its guarantee. A sandbox keeps its guarantee for life."
    })
    |> Map.put(:memory_limit_mb, memory_limit())
  end

  defp memory_limit do
    %Schema{
      type: :integer,
      enum: Sandbox.memory_limits(),
      description:
        "Linux only, opt-in: the memory in MB the sandbox may burst to, larger than `memory_mb`, which stays its guaranteed request. It uses memory past its request while its node has some free, gives it back when its processes free it, and is billed for the larger of its request and what it uses. While the node is short of memory, an idle sandbox above its request may be paused; one running a command never is. Omitted, the sandbox uses at most `memory_mb`. A sandbox keeps its limit for life."
    }
  end

  @doc "A sandbox lifetime in seconds, for create and extend."
  def lifetime do
    %Schema{
      type: :integer,
      minimum: 300,
      maximum: Sandbox.max_lifetime_seconds(),
      description:
        "How long the sandbox may run, in seconds, from now and again after each resume: #{div(Sandbox.default_lifetime_seconds(), 3600)} hours by default, at most #{div(Sandbox.max_lifetime_seconds(), 3600)}. When it ends, running commands are cancelled and the sandbox is paused and archived, keeping its files, so a forgotten sandbox stops billing and frees its Mac."
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
  def response(:devices), do: object("SandboxDevices", %{devices: array(device())})
  def response(:boot_device), do: device()

  def response(:launch_app),
    do: object("SandboxAppLaunch", %{app_id: %Schema{type: :string}, device: %Schema{type: :string}})

  def response(:open_url), do: object("SandboxURLOpened", %{url: %Schema{type: :string}, device: %Schema{type: :string}})

  def response(:screenshot),
    do:
      object("SandboxScreenshot", %{
        target: %Schema{type: :string, enum: ["device", "screen"]},
        device: %Schema{type: :string, nullable: true, description: "The device captured; null for the screen."},
        mime_type: %Schema{type: :string},
        width: integer(),
        height: integer()
      })

  def response(:delete), do: object("SandboxDeleted", %{id: %Schema{type: :string, format: "uuid"}, deleted: boolean()})

  def response(:analytics) do
    resources = fn title -> object(title, %{vcpus: integer(), memory_gb: number()}) end

    object("SandboxAnalytics", %{
      period: object("SandboxAnalyticsPeriod", %{start: timestamp(), end: timestamp()}),
      bucket: %Schema{
        type: :string,
        description: "`hour` for ranges of up to 36 hours, otherwise `day`: the span of each point."
      },
      vcpu_hours: %Schema{
        type: :number,
        description:
          "vCPU-hours sandboxes were billed for in the range. A Linux sandbox counts the larger of the CPU it used and a quarter vCPU per GiB of its memory; a macOS sandbox counts its vCPUs for each running hour."
      },
      memory_gib_hours: %Schema{
        type: :number,
        description:
          "GiB-hours of memory sandboxes were billed for in the range: each running sandbox's memory for every hour it runs."
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
          # Guaranteed vCPUs, which the limit counts, rounded up.
          in_use: resources.("SandboxResourcesInUse"),
          points:
            array(
              object("SandboxAnalyticsConcurrencyPoint", %{
                at: timestamp(),
                vcpus: integer(),
                memory_gb: number()
              })
            )
        })
    })
  end

  def device,
    do:
      object("SandboxDevice", %{
        id: %Schema{type: :string, description: "An iOS simulator's UDID."},
        name: %Schema{type: :string},
        platform: %Schema{
          type: :string,
          nullable: true,
          description: "`ios`, `watchos`, `tvos`, `xros` and, later, `android`; an open string."
        },
        runtime: %Schema{type: :string, description: "Such as `iOS 27.2`."},
        state: %Schema{type: :string, description: "`Booted`, `Shutdown` or `Booting`; an open string."}
      })

  def inputs(action) do
    base = %{account_handle: %Schema{type: :string, minLength: 1}}
    %{object(nil, Map.merge(base, fields(action))) | required: required(action)}
  end

  defp fields(:list) do
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
  end

  defp fields(:analytics) do
    %{start: timestamp(), end: timestamp()}
  end

  defp fields(:create) do
    Map.put(create(), :repository, %Schema{
      type: :string,
      pattern: "^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$",
      description:
        "macOS only: the github.com repository (`owner/name`) the sandbox is for, connected to one of the account's projects. When a Linux Claude Code environment of the account has a macOS setup script, the sandbox boots from that repository's snapshot for its Xcode, with the default branch cloned to `$HOME/work/<name>`, the script run and the project built there, so the first `tuist sandbox sync` sends only what changed. Without a snapshot it boots bare and one is built for the next sandbox."
    })
  end

  defp fields(:extend) do
    %{
      sandbox_id: %Schema{type: :string, format: "uuid"},
      lifetime_seconds: %{
        lifetime()
        | description:
            "The new lifetime, in seconds from now, at most #{div(Sandbox.max_lifetime_seconds(), 3600)} hours. Omitted, the sandbox's current lifetime starts again."
      }
    }
  end

  defp fields(:boot_device) do
    %{sandbox_id: uuid(), device: device_input("The device to boot, by name (such as `iPhone 18 Pro`) or ID.")}
  end

  defp fields(:launch_app) do
    %{
      sandbox_id: uuid(),
      device: device_input("The device, by name or ID. Defaults to the booted one."),
      app_id: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 255,
        description:
          "The app's identifier: on iOS its bundle identifier. Optional with `app_path`, which names the .app it is read from."
      },
      app_path: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 1024,
        description:
          "An .app built in the sandbox, such as `build/dd/Build/Products/Debug-iphonesimulator/App.app` under the synced `root`, to install before launching. Absolute, or relative to the sandbox's workspace."
      }
    }
  end

  defp fields(:open_url) do
    %{
      sandbox_id: uuid(),
      url: %Schema{type: :string, minLength: 1, maxLength: 2048, description: "A web URL or the app's deep link."},
      device: device_input("The device, by name or ID. Defaults to the booted one.")
    }
  end

  defp fields(:screenshot) do
    %{
      sandbox_id: uuid(),
      target: %Schema{
        type: :string,
        enum: ["device", "screen"],
        description: "`device` (default) captures a booted device; `screen` the sandbox's whole screen."
      },
      device: device_input("With `target: device`, the device by name or ID. Defaults to the booted one.")
    }
  end

  defp fields(_action) do
    %{sandbox_id: uuid()}
  end

  defp required(action) when action in [:list, :analytics, :create], do: [:account_handle]
  defp required(:boot_device), do: [:account_handle, :sandbox_id, :device]
  defp required(:open_url), do: [:account_handle, :sandbox_id, :url]
  defp required(_action), do: [:account_handle, :sandbox_id]

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

  defp uuid, do: %Schema{type: :string, format: "uuid"}
  defp device_input(description), do: %Schema{type: :string, minLength: 1, maxLength: 200, description: description}
  defp array(items), do: %Schema{type: :array, items: items}
  defp integer, do: %Schema{type: :integer}
  defp number, do: %Schema{type: :number}
  defp boolean, do: %Schema{type: :boolean}
  defp timestamp, do: %Schema{type: :string, format: "date-time"}
end
