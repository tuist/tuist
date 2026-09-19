defmodule Atlas.Engineering.Pages do
  @moduledoc """
  Static site hosting under Engineering. Anyone in the organization can deploy
  a folder of static assets and Atlas serves it at `<slug>.atlas.tuist.dev`
  behind the same session cookie every authenticated Atlas user already has.

  A deploy is a two-step handshake so bytes never have to travel through the
  BEAM: the client asks for a set of presigned PUT URLs, uploads each object
  directly to object storage, then calls back to promote the deploy to `live`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Engineering.Pages.Deploy
  alias Atlas.Engineering.Pages.Page
  alias Atlas.Engineering.Pages.ReservedSlugs
  alias Atlas.ObjectStorage
  alias Atlas.Repo
  alias Atlas.Users.User

  @default_upload_ttl 900
  @max_files 500
  @max_total_bytes 100 * 1024 * 1024

  def reserved_slugs, do: ReservedSlugs.all()
  def max_files, do: @max_files
  def max_total_bytes, do: @max_total_bytes

  def list_pages do
    Page
    |> preload([:created_by_user, :current_deploy])
    |> order_by([page], asc: page.slug)
    |> Repo.all()
  end

  def list_pages_for_user(%User{id: user_id}) when is_binary(user_id) do
    Page
    |> where([page], page.created_by_user_id == ^user_id)
    |> preload([:created_by_user, :current_deploy])
    |> order_by([page], desc: page.updated_at)
    |> Repo.all()
  end

  def list_pages_for_user(_user), do: []

  def get_page(id) when is_binary(id) do
    Page
    |> preload([:created_by_user, :current_deploy])
    |> Repo.get(id)
  end

  def get_page(_id), do: nil

  def get_page_by_slug(slug) when is_binary(slug) do
    normalized = slug |> String.trim() |> String.downcase()

    Page
    |> where([page], page.slug == ^normalized)
    |> preload([:created_by_user, :current_deploy])
    |> Repo.one()
  end

  def get_page_by_slug(_slug), do: nil

  def get_deploy(id) when is_binary(id) do
    Deploy
    |> preload(page: [:current_deploy])
    |> Repo.get(id)
  end

  def get_deploy(_id), do: nil

  def create_page(attrs, %User{} = user) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("created_by_user_id", user.id)

    %Page{}
    |> Page.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, page} ->
        record_event("page.created", page, user)
        {:ok, page}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_page(_attrs, _user), do: {:error, :unauthorized}

  def delete_page(%Page{} = page, %User{} = user) do
    with :ok <- delete_stored_objects(page),
         {:ok, page} <- Repo.delete(page) do
      record_event("page.deleted", page, user)
      {:ok, page}
    end
  end

  def delete_page(_page, _user), do: {:error, :unauthorized}

  @doc """
  Reserve a new pending deploy and mint a presigned `PUT` URL for every file
  the client declared. Returns `{deploy_id, uploads}` where `uploads` is a
  list of `%{path, upload_url, required_headers}` triples the client can
  drive with plain HTTP.
  """
  def start_deploy(page, files, user, opts \\ [])

  def start_deploy(%Page{} = page, files, %User{} = user, opts) when is_list(files) do
    with :ok <- validate_manifest(files) do
      manifest = normalize_manifest(files)

      total_bytes =
        manifest
        |> Enum.map(& &1["size"])
        |> Enum.sum()

      {:ok, deploy} =
        %Deploy{}
        |> Deploy.changeset(%{
          "state" => "pending",
          "file_count" => length(manifest),
          "total_bytes" => total_bytes,
          "manifest" => manifest,
          "page_id" => page.id,
          "uploaded_by_user_id" => user.id
        })
        |> Repo.insert()

      uploads =
        Enum.map(manifest, fn entry ->
          key = object_key(page, deploy, entry["path"])
          content_type = entry["content_type"] || content_type_from_path(entry["path"])

          {:ok, url} =
            ObjectStorage.presigned_put_url(key,
              expires_in: Keyword.get(opts, :expires_in, @default_upload_ttl),
              content_type: content_type
            )

          %{
            "path" => entry["path"],
            "upload_url" => url,
            "required_headers" => %{"content-type" => content_type},
            "storage_key" => key
          }
        end)

      record_event("page.deploy.started", page, user, %{"deploy_id" => deploy.id, "files" => length(manifest)})

      {:ok, %{deploy: deploy, uploads: uploads}}
    end
  end

  def start_deploy(_page, _files, _user, _opts), do: {:error, :invalid_arguments}

  @doc """
  Write bytes for one file of a pending deploy directly through Atlas. This is
  the server-side equivalent of `PUT`-ing to a presigned URL, used by the
  LiveView drag-and-drop path so the browser upload goes to Phoenix rather
  than round-tripping through Tigris.
  """
  def store_object(%Page{} = page, %Deploy{} = deploy, path, body, opts \\ []) when is_binary(body) do
    key = object_key(page, deploy, path)
    content_type = Keyword.get(opts, :content_type) || content_type_from_path(path)
    ObjectStorage.put_object(key, body, content_type: content_type)
  end

  @doc """
  Verify every declared object landed in storage, promote the deploy to
  `:live`, and swap the page's `current_deploy_id` atomically. Any previous
  live deploy is marked `:superseded`.
  """
  def finalize_deploy(%Deploy{state: :pending} = deploy, %User{} = user) do
    page = Repo.preload(deploy, :page).page

    with :ok <- verify_uploaded(page, deploy) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        {:ok, promoted} =
          deploy
          |> Deploy.changeset(%{"state" => "live", "finalized_at" => now})
          |> Repo.update()

        Deploy
        |> where([d], d.page_id == ^page.id and d.state == ^"live" and d.id != ^promoted.id)
        |> Repo.update_all(set: [state: "superseded", updated_at: now])

        {:ok, updated_page} =
          page
          |> Page.changeset(%{"current_deploy_id" => promoted.id})
          |> Repo.update()

        record_event("page.deploy.finalized", updated_page, user, %{"deploy_id" => promoted.id})

        %{page: updated_page, deploy: promoted}
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def finalize_deploy(%Deploy{state: state}, _user) when state != :pending, do: {:error, {:invalid_state, state}}
  def finalize_deploy(nil, _user), do: {:error, :not_found}
  def finalize_deploy(_deploy, _user), do: {:error, :unauthorized}

  @doc """
  Fetch the stored bytes for the request path under a page's current deploy,
  applying the `index.html` fallback used by every static-site convention:
  a trailing slash or a bare directory path resolves to `index.html`. Returns
  `{:ok, %{body, content_type}}` or `{:error, :not_found}`.
  """
  def fetch_object(%Page{current_deploy_id: nil}, _request_path), do: {:error, :not_found}

  def fetch_object(%Page{} = page, request_path) do
    deploy = Repo.get(Deploy, page.current_deploy_id)

    if is_nil(deploy) do
      {:error, :not_found}
    else
      candidates = resolution_candidates(request_path)

      Enum.reduce_while(candidates, {:error, :not_found}, fn path, _acc ->
        key = object_key(page, deploy, path)

        case ObjectStorage.get_object(key, []) do
          {:ok, %{body: body, content_type: content_type}} ->
            content_type = content_type || content_type_from_path(path)
            {:halt, {:ok, %{body: body, content_type: content_type, path: path}}}

          {:error, _reason} ->
            {:cont, {:error, :not_found}}
        end
      end)
    end
  end

  def fetch_object(_page, _path), do: {:error, :not_found}

  @doc """
  The URL a user visits to reach the page in production. `host_suffix` is the
  wildcard host root, e.g. `atlas.tuist.dev`.
  """
  def public_url(%Page{slug: slug}, host_suffix, scheme \\ "https") when is_binary(slug) do
    "#{scheme}://#{slug}.#{host_suffix}/"
  end

  def dashboard_path(%Page{id: id}), do: "/engineering/pages/#{id}"

  defp object_key(%Page{id: page_id}, %Deploy{id: deploy_id}, path) do
    normalized =
      path
      |> String.trim_leading("/")
      |> String.split("/")
      |> Enum.reject(&(&1 in ["", ".", ".."]))
      |> Enum.join("/")

    "pages/#{page_id}/#{deploy_id}/#{normalized}"
  end

  defp resolution_candidates(nil), do: resolution_candidates("/")

  defp resolution_candidates(path) do
    normalized = String.trim_leading(path || "", "/")

    cond do
      normalized == "" ->
        ["index.html"]

      String.ends_with?(normalized, "/") ->
        [normalized <> "index.html"]

      Path.extname(normalized) == "" ->
        [normalized, normalized <> "/index.html", normalized <> ".html"]

      true ->
        [normalized]
    end
  end

  defp validate_manifest([]), do: {:error, :empty_manifest}

  defp validate_manifest(files) when is_list(files) do
    cond do
      length(files) > @max_files ->
        {:error, {:too_many_files, @max_files}}

      Enum.any?(files, &invalid_manifest_entry?/1) ->
        {:error, :invalid_manifest}

      Enum.reduce(files, 0, fn entry, acc -> acc + Map.get(entry, "size", Map.get(entry, :size, 0)) end) >
          @max_total_bytes ->
        {:error, {:too_large, @max_total_bytes}}

      true ->
        :ok
    end
  end

  defp invalid_manifest_entry?(entry) when is_map(entry) do
    path = Map.get(entry, "path") || Map.get(entry, :path)
    size = Map.get(entry, "size") || Map.get(entry, :size) || 0

    not is_binary(path) or path == "" or String.contains?(path, "..") or
      not is_integer(size) or size < 0
  end

  defp invalid_manifest_entry?(_entry), do: true

  defp normalize_manifest(files) do
    Enum.map(files, fn entry ->
      path = Map.get(entry, "path") || Map.get(entry, :path)
      size = Map.get(entry, "size") || Map.get(entry, :size) || 0
      content_type = Map.get(entry, "content_type") || Map.get(entry, :content_type)

      %{
        "path" => normalize_path(path),
        "size" => size,
        "content_type" => content_type
      }
    end)
  end

  defp normalize_path(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/")
    |> Enum.reject(&(&1 in ["", ".", ".."]))
    |> Enum.join("/")
  end

  defp verify_uploaded(page, %Deploy{manifest: manifest} = deploy) do
    Enum.reduce_while(manifest, :ok, fn entry, _acc ->
      key = object_key(page, deploy, entry["path"])

      case ObjectStorage.head_object(key, []) do
        {:ok, _response} -> {:cont, :ok}
        {:error, _reason} -> {:halt, {:error, {:missing_object, entry["path"]}}}
      end
    end)
  end

  defp delete_stored_objects(%Page{} = page) do
    deploys = Repo.all(from d in Deploy, where: d.page_id == ^page.id)

    Enum.each(deploys, fn deploy ->
      Enum.each(deploy.manifest, fn entry ->
        path = entry["path"] || entry[:path]

        if is_binary(path) do
          key = object_key(page, deploy, path)
          _ = ObjectStorage.delete_object(key, [])
        end
      end)
    end)

    :ok
  end

  @content_types %{
    ".html" => "text/html; charset=utf-8",
    ".htm" => "text/html; charset=utf-8",
    ".css" => "text/css; charset=utf-8",
    ".js" => "application/javascript; charset=utf-8",
    ".mjs" => "application/javascript; charset=utf-8",
    ".json" => "application/json",
    ".map" => "application/json",
    ".svg" => "image/svg+xml",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".ico" => "image/x-icon",
    ".avif" => "image/avif",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf" => "font/ttf",
    ".otf" => "font/otf",
    ".txt" => "text/plain; charset=utf-8",
    ".md" => "text/markdown; charset=utf-8",
    ".xml" => "application/xml",
    ".pdf" => "application/pdf",
    ".wasm" => "application/wasm"
  }

  defp content_type_from_path(path) do
    ext = path |> Path.extname() |> String.downcase()
    Map.get(@content_types, ext, "application/octet-stream")
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      pair -> pair
    end)
  end

  defp record_event(action, %Page{} = page, %User{} = user, extra \\ %{}) do
    metadata =
      Map.merge(
        %{
          "slug" => page.slug,
          "path" => dashboard_path(page)
        },
        extra
      )

    Audit.record(action, %{
      actor: user,
      target_type: "page",
      target_id: page.id,
      target_label: page.title || page.slug,
      metadata: metadata
    })
  end
end
