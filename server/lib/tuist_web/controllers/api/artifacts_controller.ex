defmodule TuistWeb.API.ArtifactsController do
  use TuistWeb, :controller

  alias Tuist.Artifacts
  alias Tuist.Artifacts.Package
  alias TuistWeb.Authentication

  plug TuistWeb.Plugs.LoaderPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :artifact

  def capabilities(conn, _params) do
    json(conn, %{schema: "once.publication_service.v1", destination: Artifacts.destination(conn.assigns.selected_project)})
  end

  def show(conn, %{"key" => key}) do
    case Artifacts.get(conn.assigns.selected_project, key) do
      {:ok, publication} -> json(conn, receipt(conn, publication))
      error -> failure(conn, error)
    end
  end

  def commit(conn, %{"key" => key}) do
    intent = conn.body_params
    subject = Authentication.authenticated_subject(conn)
    creator = if is_map(subject), do: get_in(subject, [Access.key(:account), Access.key(:id)])

    case Artifacts.commit(conn.assigns.selected_project, key, intent, creator) do
      {:ok, publication} -> json(conn, receipt(conn, publication))
      error -> failure(conn, error)
    end
  end

  def upload(conn, %{"key" => key, "digest" => digest}) do
    if Package.valid_digest?(key) and Package.valid_digest?(digest) do
      path = Briefly.create!()

      try do
        with {:ok, conn, actual} <- receive_file(conn, path),
             true <- actual == digest,
             :ok <- Artifacts.put_content(conn.assigns.selected_project, key, digest, path) do
          send_resp(conn, :no_content, "")
        else
          false -> failure(conn, {:error, :digest_mismatch})
          error -> failure(conn, error)
        end
      after
        File.rm(path)
      end
    else
      failure(conn, {:error, :invalid_digest})
    end
  end

  def download(conn, %{"key" => key, "digest" => digest}) do
    project = conn.assigns.selected_project

    with {:ok, publication} <- Artifacts.get(project, key),
         {:ok, url} <- Artifacts.content_url(project, publication, digest) do
      redirect(conn, external: url)
    else
      error -> failure(conn, error)
    end
  end

  defp receive_file(conn, path) do
    File.open!(path, [:write, :binary], fn file -> read_chunks(conn, file, :crypto.hash_init(:sha256), 0) end)
  end

  defp read_chunks(conn, file, hash, size) do
    case Plug.Conn.read_body(conn, length: 1_048_576, read_length: 65_536, read_timeout: 30_000) do
      {status, bytes, conn} when status in [:ok, :more] ->
        if size + byte_size(bytes) <= 21_474_836_480 do
          :ok = IO.binwrite(file, bytes)
          hash = :crypto.hash_update(hash, bytes)

          if status == :more do
            read_chunks(conn, file, hash, size + byte_size(bytes))
          else
            {:ok, conn, "sha256:" <> Base.encode16(:crypto.hash_final(hash), case: :lower)}
          end
        else
          {:error, :too_large}
        end

      {:error, _} ->
        {:error, :incomplete_upload}
    end
  end

  defp receipt(conn, publication) do
    project = conn.assigns.selected_project
    url = Tuist.Environment.app_url() <> "/#{project.account.name}/#{project.name}/previews"
    Artifacts.receipt(project, publication, url)
  end

  defp failure(conn, {:error, reason}) do
    status =
      case reason do
        :not_found -> :not_found
        :expired -> :gone
        :already_committed -> :conflict
        :too_large -> :request_entity_too_large
        :storage_unavailable -> :service_unavailable
        reason when is_atom(reason) -> :unprocessable_entity
        _ -> :service_unavailable
      end

    code = if is_atom(reason), do: to_string(reason), else: "storage_unavailable"
    conn |> put_status(status) |> json(%{error: code})
  end
end
