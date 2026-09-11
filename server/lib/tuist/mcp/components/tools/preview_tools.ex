defmodule Tuist.MCP.Components.Tools.PreviewSerializer do
  @moduledoc """
  Shared output schema and serialization for the preview tools.

  The shape mirrors `TuistWeb.API.PreviewsController`'s `map_preview/5` so the
  HTTP resource and the tools describe a preview identically. The one
  deliberate divergence is `url`: the controller overwrites it with the first
  build's download URL on `show` to keep older client versions working, while the
  tools always report the dashboard URL and leave the download URLs on
  `builds[].url`, where an agent can tell the two apart.
  """

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.Environment
  alias Tuist.MCP.Formatter
  alias Tuist.Storage

  @download_url_expires_in 3600

  def download_url_expires_in, do: @download_url_expires_in

  def supported_platform_values do
    Preview
    |> Ecto.Enum.mappings(:supported_platforms)
    |> Keyword.keys()
  end

  @doc """
  Casts client-supplied platform names to the schema's atoms.

  Unknown values are rejected rather than converted, so a caller can neither
  grow the atom table nor turn an invalid filter into an unfiltered read.
  """
  def cast_supported_platforms(nil), do: {:ok, nil}

  def cast_supported_platforms(values) when is_list(values) do
    names = Enum.map(values, &to_string/1)
    supported_platforms = supported_platform_values()

    if Enum.all?(names, fn name -> Enum.any?(supported_platforms, fn platform -> to_string(platform) == name end) end) do
      {:ok, Enum.filter(supported_platforms, &(to_string(&1) in names))}
    else
      {:error, "supported_platforms contains an unsupported platform."}
    end
  end

  def cast_supported_platforms(value), do: cast_supported_platforms([value])

  def schema(opts \\ []) do
    type = if Keyword.get(opts, :nullable, false), do: ["object", "null"], else: "object"

    %{
      "type" => type,
      "properties" => %{
        "id" => %{"type" => "string"},
        "url" => %{"type" => "string"},
        "device_url" => %{"type" => "string"},
        "qr_code_url" => %{"type" => "string"},
        "icon_url" => %{"type" => "string"},
        "version" => %{"type" => ["string", "null"]},
        "bundle_identifier" => %{"type" => ["string", "null"]},
        "display_name" => %{"type" => ["string", "null"]},
        "git_commit_sha" => %{"type" => ["string", "null"]},
        "git_branch" => %{"type" => ["string", "null"]},
        "track" => %{"type" => ["string", "null"]},
        "supported_platforms" => %{"type" => "array", "items" => %{"type" => "string"}},
        "inserted_at" => %{"type" => "string"},
        "created_from_ci" => %{"type" => "boolean"},
        "created_by" => %{
          "type" => ["object", "null"],
          "properties" => %{
            "id" => %{"type" => "integer"},
            "handle" => %{"type" => "string"}
          },
          "required" => ["id", "handle"],
          "additionalProperties" => false
        },
        "builds" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "url" => %{"type" => "string"},
              "type" => %{"type" => "string"},
              "supported_platforms" => %{"type" => "array", "items" => %{"type" => "string"}},
              "inserted_at" => %{"type" => "string"},
              "binary_id" => %{"type" => ["string", "null"]},
              "build_version" => %{"type" => ["string", "null"]}
            },
            "required" => [
              "id",
              "url",
              "type",
              "supported_platforms",
              "inserted_at",
              "binary_id",
              "build_version"
            ],
            "additionalProperties" => false
          }
        }
      },
      "required" => [
        "id",
        "url",
        "device_url",
        "qr_code_url",
        "icon_url",
        "version",
        "bundle_identifier",
        "display_name",
        "git_commit_sha",
        "git_branch",
        "track",
        "supported_platforms",
        "inserted_at",
        "created_from_ci",
        "created_by",
        "builds"
      ],
      "additionalProperties" => false
    }
  end

  def serialize(preview, project) do
    account = project.account
    account_handle = account.name
    project_handle = project.name
    supported_platforms = preview.supported_platforms || []

    %{
      id: preview.id,
      url: preview_url(account_handle, project_handle, preview.id),
      device_url: device_url(preview, account_handle, project_handle, supported_platforms),
      qr_code_url: preview_url(account_handle, project_handle, preview.id, "/qr-code.png"),
      icon_url: preview_url(account_handle, project_handle, preview.id, "/icon.png"),
      version: preview.version,
      bundle_identifier: preview.bundle_identifier,
      display_name: preview.display_name,
      git_commit_sha: preview.git_commit_sha,
      git_branch: preview.git_branch,
      track: preview.track,
      supported_platforms: Enum.map(supported_platforms, &to_string/1),
      inserted_at: Formatter.iso8601(preview.inserted_at),
      created_by: created_by(preview.created_by_account),
      created_from_ci: created_from_ci?(preview.created_by_account),
      builds: builds(preview, account_handle, project_handle, account)
    }
  end

  defp builds(preview, account_handle, project_handle, account) do
    preview.app_builds
    |> List.wrap()
    |> Enum.map(fn app_build ->
      key =
        AppBuilds.storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          app_build: app_build
        })

      %{
        id: app_build.id,
        url: Storage.generate_download_url(key, account, expires_in: @download_url_expires_in),
        type: to_string(app_build.type),
        supported_platforms: Enum.map(app_build.supported_platforms || [], &to_string/1),
        inserted_at: Formatter.iso8601(app_build.inserted_at),
        binary_id: app_build.binary_id,
        build_version: app_build.build_version
      }
    end)
    |> Enum.sort_by(& &1.inserted_at, :desc)
  end

  defp created_by(nil), do: nil
  defp created_by(account), do: %{id: account.id, handle: account.name}

  defp created_from_ci?(nil), do: true
  defp created_from_ci?(account), do: is_nil(account.user_id)

  defp device_url(preview, account_handle, project_handle, [:android]) do
    preview_url(account_handle, project_handle, preview.id, "/app.apk")
  end

  defp device_url(preview, account_handle, project_handle, _supported_platforms) do
    manifest_url = preview_url(account_handle, project_handle, preview.id, "/manifest.plist")
    "itms-services://?action=download-manifest&url=#{manifest_url}"
  end

  defp preview_url(account_handle, project_handle, preview_id, suffix \\ "") do
    Environment.app_url(path: "/#{account_handle}/#{project_handle}/previews/#{preview_id}#{suffix}")
  end
end

defmodule Tuist.MCP.Components.Tools.ListPreviews do
  @moduledoc """
  List previews (shareable app builds) for a project.
  """

  use Tuist.MCP.Tool,
    name: "list_previews",
    title: "List Previews",
    read_only_hint: true,
    authorize: [action: :read, category: :preview],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "display_name" => %{
          "type" => "string",
          "description" => "Filter by the preview's display name."
        },
        "specifier" => %{
          "type" => "string",
          "description" => ~s{Filter by a git commit SHA, a branch name, or "latest" for the project's default branch.}
        },
        "supported_platforms" => %{
          "type" => "array",
          "items" => %{
            "type" => "string",
            "enum" => Enum.map(Tuist.MCP.Components.Tools.PreviewSerializer.supported_platform_values(), &to_string/1)
          },
          "description" => "Return previews supporting any of these platforms."
        },
        "distinct_field" => %{
          "type" => "string",
          "enum" => ["bundle_identifier"],
          "description" =>
            "Return only the latest preview per value of this field, so a project with several apps yields one preview each."
        },
        "page" => %{
          "type" => "integer",
          "description" => "Page number (default: 1)."
        },
        "page_size" => %{
          "type" => "integer",
          "description" => "Results per page (default: 20, max: 100)."
        }
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "previews" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.PreviewSerializer.schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["previews", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.AppBuilds
  alias Tuist.MCP.Components.Tools.PreviewSerializer
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List previews (shareable app builds) for a project. Each preview includes temporary download URLs for its builds, valid for #{div(PreviewSerializer.download_url_expires_in(), 60)} minutes. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    with {:ok, supported_platforms} <- PreviewSerializer.cast_supported_platforms(Map.get(args, "supported_platforms")) do
      {previews, meta} =
        AppBuilds.list_previews(
          %{
            filters: build_filters(project, args),
            order_by: [:inserted_at],
            order_directions: [:desc],
            page: MCPTool.page(args),
            page_size: MCPTool.page_size(args)
          },
          distinct: distinct(args),
          supported_platforms: supported_platforms,
          preload: [:app_builds, :created_by_account]
        )

      {:ok,
       %{
         previews: Enum.map(previews, &PreviewSerializer.serialize(&1, project)),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end

  defp distinct(args) do
    case Map.get(args, "distinct_field") do
      "bundle_identifier" -> [:bundle_identifier]
      _ -> []
    end
  end

  # Mirrors `TuistWeb.API.PreviewsController.get_filters/2`: a preview without a
  # bundle identifier cannot be installed, so it never belongs in a listing.
  defp build_filters(project, args) do
    filters = [
      %{field: :project_id, op: :==, value: project.id},
      %{field: :bundle_identifier, op: :not_empty, value: true}
    ]

    filters = specifier_filters(project, Map.get(args, "specifier")) ++ filters

    case Map.get(args, "display_name") do
      nil -> filters
      display_name -> [%{field: :display_name, op: :==, value: display_name} | filters]
    end
  end

  defp specifier_filters(_project, nil), do: []

  defp specifier_filters(project, "latest") do
    [%{field: :git_branch, op: :==, value: project.default_branch}]
  end

  defp specifier_filters(_project, specifier) do
    if Regex.match?(~r/^[a-fA-F0-9]{40}$/, specifier) do
      [%{field: :git_commit_sha, op: :==, value: specifier}]
    else
      [%{field: :git_branch, op: :==, value: specifier}]
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetPreview do
  @moduledoc """
  Get a single preview, including download URLs for each of its builds.
  """

  use Tuist.MCP.Tool,
    name: "get_preview",
    title: "Get Preview",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "preview_id" => %{
          "type" => "string",
          "description" => "The ID of the preview, or a Tuist dashboard URL."
        }
      },
      "required" => ["preview_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.PreviewSerializer.schema()

  alias Tuist.AppBuilds
  alias Tuist.MCP.Components.Tools.PreviewSerializer
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific preview, including temporary download URLs for its builds, valid for #{div(PreviewSerializer.download_url_expires_in(), 60)} minutes. The preview_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/previews/{id}."

  def execute(conn, %{"preview_id" => preview_id}) do
    preview_id = MCPTool.resource_id(preview_id)

    with {:ok, preview, project} <-
           MCPTool.load_and_authorize(
             AppBuilds.preview_by_id(preview_id, preload: [:app_builds, :created_by_account]),
             conn.assigns,
             :read,
             :preview,
             "Preview not found: #{preview_id}"
           ) do
      {:ok, PreviewSerializer.serialize(preview, project)}
    end
  end

  def execute(_conn, _args), do: {:error, "Provide preview_id."}
end

defmodule Tuist.MCP.Components.Tools.GetLatestPreview do
  @moduledoc """
  Get the latest preview on the same track as a running binary.
  """

  use Tuist.MCP.Tool,
    name: "get_latest_preview",
    title: "Get Latest Preview",
    read_only_hint: true,
    authorize: [action: :read, category: :preview],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "binary_id" => %{
          "type" => "string",
          "description" => "A unique identifier for the running binary."
        },
        "build_version" => %{
          "type" => "string",
          "description" => "The build version of the running app."
        }
      },
      "required" => ["account_handle", "project_handle", "binary_id", "build_version"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "preview" => Tuist.MCP.Components.Tools.PreviewSerializer.schema(nullable: true)
      },
      "required" => ["preview"],
      "additionalProperties" => false
    }

  alias Tuist.AppBuilds
  alias Tuist.MCP.Components.Tools.PreviewSerializer

  @impl EMCP.Tool
  def description,
    do:
      "Given the binary ID and build version of a running app, get the latest preview on the same track (same bundle identifier and git branch). Returns null when no matching build is known. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"binary_id" => binary_id, "build_version" => build_version}, project) do
    case AppBuilds.latest_preview_for_binary_id_and_build_version(binary_id, build_version, project,
           preload: [:app_builds, :created_by_account]
         ) do
      {:ok, preview} -> {:ok, %{preview: PreviewSerializer.serialize(preview, project)}}
      {:error, :not_found} -> {:ok, %{preview: nil}}
    end
  end

  def execute(_conn, _args, _project), do: {:error, "Provide binary_id and build_version."}
end
