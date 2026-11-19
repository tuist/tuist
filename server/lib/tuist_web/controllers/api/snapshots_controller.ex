defmodule TuistWeb.API.SnapshotsController do
  @moduledoc """
  The client's side of `Tuist.Snapshots`: a client creates a build with the
  manifest of its images, uploads the images the server lacks to the
  presigned URLs it gets back, completes the build, and polls it for the
  verdict.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.FeatureFlags
  alias Tuist.Snapshots
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)
  plug(:require_snapshots)

  tags ["Snapshots"]

  @path_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]

  @build_parameters @path_parameters ++
                      [build_id: [in: :path, type: :string, required: true, description: "The id of the snapshot build."]]

  @sha %Schema{type: :string, pattern: "^[0-9a-f]{40}([0-9a-f]{24})?$", description: "A commit SHA."}

  @build %Schema{
    title: "SnapshotBuild",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "The id of the build."},
      url: %Schema{type: :string, description: "The build's review page on the dashboard."},
      state: %Schema{
        type: :string,
        enum: ~w(uploading processing processed failed),
        description: "Where the build is in its lifecycle."
      },
      status: %Schema{
        type: :string,
        enum: ~w(processing failed passed baseline approved rejected needs_review),
        description:
          "The verdict: `needs_review` when images changed or were removed against the baseline and nobody reviewed them yet, `rejected` when a reviewer rejected those changes."
      },
      baseline_build_id: %Schema{type: :string, nullable: true, description: "The build this one was compared with."},
      unchanged_count: %Schema{type: :integer},
      changed_count: %Schema{type: :integer},
      added_count: %Schema{type: :integer},
      removed_count: %Schema{type: :integer},
      renamed_count: %Schema{type: :integer, description: "Removed images whose content reappeared under another name."},
      skipped_count: %Schema{
        type: :integer,
        description: "Images a selective run didn't render, carried over from the baseline."
      }
    },
    required: [:id, :url, :state, :status]
  }

  @common_responses %{
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
    not_found: {"The project or build was not found", "application/json", Error}
  }

  operation(:create,
    summary: "Create a snapshot build.",
    description:
      "Creates a build of a snapshot set at a commit from the manifest of its images. The dashboard pools a commit's builds, every set, shard and rerun, and reviews them together. The response lists the content hashes the server doesn't store yet, each with a presigned URL to PUT the PNG to; complete the build once they are uploaded.",
    operation_id: "createSnapshotBuild",
    parameters: @path_parameters,
    request_body:
      {"The build", "application/json",
       %Schema{
         title: "CreateSnapshotBuildRequest",
         type: :object,
         properties: %{
           set: %Schema{
             type: :string,
             description: "The snapshot set, such as `android-phone`: builds are compared within a set."
           },
           git_commit_sha: @sha,
           git_branch: %Schema{type: :string},
           git_ref: %Schema{type: :string},
           git_remote_url_origin: %Schema{type: :string},
           merge_base_sha: @sha,
           pull_request_number: %Schema{type: :integer},
           pull_request_title: %Schema{type: :string, maxLength: 1024},
           is_ci: %Schema{type: :boolean},
           selective: %Schema{
             type: :boolean,
             description:
               "The run rendered only some images: baseline images it didn't upload are skipped, not removed. Prefer `all_image_names`, which still detects removals."
           },
           all_image_names: %Schema{
             type: :array,
             maxItems: Snapshots.max_images(),
             items: %Schema{type: :string},
             description:
               "The names of every image the suite renders, for a run that rendered only some: those it didn't upload are skipped, and baseline images missing from the list are removed."
           },
           build_system: %Schema{type: :string, enum: ~w(gradle xcode)},
           images: %Schema{
             type: :array,
             maxItems: Snapshots.max_images(),
             items: %Schema{
               title: "SnapshotImageManifestEntry",
               type: :object,
               properties: %{
                 name: %Schema{type: :string, description: "The image's path relative to the uploaded directory."},
                 content_hash: %Schema{type: :string, pattern: "^[0-9a-f]{64}$", description: "The SHA-256 of the PNG."},
                 width: %Schema{type: :integer},
                 height: %Schema{type: :integer},
                 test_identifier: %Schema{type: :string, description: "The test that recorded the image, when known."},
                 display_name: %Schema{
                   type: :string,
                   maxLength: 512,
                   description: "How the review page names the image. Defaults to `name`."
                 },
                 group: %Schema{type: :string, maxLength: 255, description: "Images of a group are reviewed together."},
                 tags: %Schema{
                   type: :object,
                   additionalProperties: %Schema{type: :string, maxLength: 255},
                   maxProperties: 50,
                   description: "Labels such as `theme: dark` or `device: pixel_7`."
                 },
                 diff_threshold: %Schema{
                   type: :number,
                   minimum: 0,
                   maximum: 1,
                   description:
                     "The share of pixels that may differ from the baseline before the image counts as changed. Defaults to 0."
                 }
               },
               required: [:name, :content_hash]
             }
           }
         },
         required: [:set, :git_commit_sha, :images]
       }},
    responses:
      Map.merge(@common_responses, %{
        ok:
          {"The build and the images to upload", "application/json",
           %Schema{
             title: "CreateSnapshotBuildResponse",
             type: :object,
             properties: %{
               build: @build,
               uploads: %Schema{
                 type: :array,
                 items: %Schema{
                   type: :object,
                   properties: %{content_hash: %Schema{type: :string}, url: %Schema{type: :string}},
                   required: [:content_hash, :url]
                 }
               }
             },
             required: [:build, :uploads]
           }},
        bad_request: {"The manifest is invalid", "application/json", Error}
      })
  )

  def create(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    attrs = %{
      set_name: body.set,
      git_commit_sha: Map.get(body, :git_commit_sha),
      git_branch: Map.get(body, :git_branch),
      git_ref: Map.get(body, :git_ref),
      git_remote_url_origin: Map.get(body, :git_remote_url_origin),
      merge_base_sha: Map.get(body, :merge_base_sha),
      pull_request_number: Map.get(body, :pull_request_number),
      pull_request_title: Map.get(body, :pull_request_title),
      is_ci: Map.get(body, :is_ci, false),
      build_system: Map.get(body, :build_system),
      selective: Map.get(body, :selective, false),
      all_image_names: Map.get(body, :all_image_names)
    }

    images =
      Enum.map(
        body.images,
        &Map.take(&1, [
          :name,
          :content_hash,
          :width,
          :height,
          :test_identifier,
          :display_name,
          :group,
          :tags,
          :diff_threshold
        ])
      )

    case Snapshots.create_build(project, attrs, images) do
      {:ok, build, missing} ->
        json(conn, %{
          build: build_json(project, build),
          uploads: Enum.map(missing, &%{content_hash: &1, url: Snapshots.upload_url(project, &1)})
        })

      {:error, %Ecto.Changeset{}} ->
        conn |> put_status(:bad_request) |> json(%{message: "The snapshot set name is invalid."})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{message: error_message(reason)})
    end
  end

  operation(:complete,
    summary: "Complete a snapshot build.",
    description:
      "Tells the server the images are uploaded, which queues the comparison with the baseline. Answers 400 with the hashes still missing otherwise. Completing a build again changes nothing.",
    operation_id: "completeSnapshotBuild",
    parameters: @build_parameters,
    responses:
      Map.merge(@common_responses, %{
        ok: {"The build", "application/json", @build},
        bad_request: {"Images are missing", "application/json", Error}
      })
  )

  def complete(%{assigns: %{selected_project: project}} = conn, %{build_id: build_id}) do
    with {:ok, build} <- Snapshots.get_build(project, build_id),
         {:ok, build} <- Snapshots.complete_build(project, build) do
      json(conn, build_json(project, build))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "The snapshot build was not found."})

      {:error, {:missing_images, missing}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "#{length(missing)} images were not uploaded: #{Enum.join(Enum.take(missing, 5), ", ")}"})
    end
  end

  operation(:show,
    summary: "Get a snapshot build.",
    description: "The build's state and verdict, which clients poll after completing it.",
    operation_id: "getSnapshotBuild",
    parameters: @build_parameters,
    responses: Map.put(@common_responses, :ok, {"The build", "application/json", @build})
  )

  def show(%{assigns: %{selected_project: project}} = conn, %{build_id: build_id}) do
    case Snapshots.get_build(project, build_id) do
      {:ok, build} -> json(conn, build_json(project, build))
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "The snapshot build was not found."})
    end
  end

  operation(:baseline,
    summary: "Get the baseline of a snapshot set for a checkout.",
    description:
      "The build a build of the set uploaded from this checkout would be compared with, and its images, each with a presigned URL to download the PNG from. Clients use it to verify images locally against the baseline instead of keeping reference images in the repository. `build` is null and `images` empty while the set has no baseline.",
    operation_id: "getSnapshotBaseline",
    parameters:
      @path_parameters ++
        [
          set: [in: :query, type: :string, required: true, description: "The snapshot set."],
          git_commit_sha: [in: :query, type: @sha, required: true, description: "The checkout's commit."],
          merge_base_sha: [
            in: :query,
            type: @sha,
            description: "The commit's merge base with the base branch, when the checkout knows it."
          ],
          git_remote_url_origin: [
            in: :query,
            type: :string,
            description: "The checkout's origin URL, to look the merge base up in the commit graph clients upload."
          ]
        ],
    responses:
      Map.put(
        @common_responses,
        :ok,
        {"The baseline and its images", "application/json",
         %Schema{
           title: "SnapshotBaseline",
           type: :object,
           properties: %{
             build: %{@build | title: "SnapshotBaselineBuild", nullable: true},
             images: %Schema{
               type: :array,
               items: %Schema{
                 title: "SnapshotBaselineImage",
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string, description: "The image's path relative to the uploaded directory."},
                   content_hash: %Schema{type: :string, description: "The SHA-256 of the PNG."},
                   url: %Schema{type: :string, description: "A presigned URL to download the PNG from."}
                 },
                 required: [:name, :content_hash, :url]
               }
             }
           },
           required: [:build, :images]
         }}
      )
  )

  def baseline(%{assigns: %{selected_project: project}} = conn, params) do
    case Snapshots.checkout_baseline(project, params) do
      nil ->
        json(conn, %{build: nil, images: []})

      build ->
        images = Snapshots.build_images(build)
        urls = images |> Enum.map(& &1.content_hash) |> Enum.uniq() |> Map.new(&{&1, Snapshots.download_url(project, &1)})

        json(conn, %{
          build: build_json(project, build),
          images: Enum.map(images, &%{name: &1.name, content_hash: &1.content_hash, url: urls[&1.content_hash]})
        })
    end
  end

  defp build_json(project, build) do
    %{
      id: build.id,
      url: url(~p"/#{project.account.name}/#{project.name}/snapshots/#{build.id}"),
      state: build.state,
      status: Snapshots.status(build, project),
      baseline_build_id: build.baseline_build_id,
      unchanged_count: build.unchanged_count,
      changed_count: build.changed_count,
      added_count: build.added_count,
      removed_count: build.removed_count,
      renamed_count: build.renamed_count,
      skipped_count: build.skipped_count
    }
  end

  defp error_message(:too_many_images), do: "A build can hold at most #{Snapshots.max_images()} images."
  defp error_message(:duplicate_image_names), do: "Image names must be unique within a build."
  defp error_message(:invalid_content_hash), do: "Content hashes must be lowercase hex SHA-256 digests."
  defp error_message(:invalid_image_name), do: "Image names must be relative paths without `..`."

  defp error_message(:invalid_image_metadata),
    do:
      "Image metadata is invalid: tags are at most 50 strings of up to 255 characters, and `diff_threshold` is between 0 and 1."

  defp require_snapshots(%{assigns: %{selected_project: project}} = conn, _opts) do
    if FeatureFlags.snapshots_enabled?(project.account) do
      conn
    else
      conn |> put_status(:not_found) |> json(%{message: "Snapshots are not enabled for this account."}) |> halt()
    end
  end
end
