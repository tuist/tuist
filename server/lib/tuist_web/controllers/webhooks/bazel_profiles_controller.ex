defmodule TuistWeb.Webhooks.BazelProfilesController do
  use TuistWeb, :controller

  alias Tuist.Bazel.Profile
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  def handle(conn, params) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      with %{
             "account_handle" => account,
             "project_handle" => name,
             "invocation_id" => invocation,
             "digest" => digest,
             "content_base64" => content
           } <- params,
           true <- valid_string?(account) and valid_string?(name) and valid_string?(invocation),
           true <- is_binary(digest) and byte_size(digest) == 64 and is_binary(content),
           %{build_system: :bazel} = project <-
             Projects.projects_by_full_handles(["#{account}/#{name}"])["#{account}/#{name}"],
           {:ok, compressed} <- Base.decode64(content),
           true <- Base.encode16(:crypto.hash(:sha256, compressed), case: :lower) == String.downcase(digest),
           :ok <- Profile.ingest(project, invocation, compressed) do
        conn |> put_status(:accepted) |> json(%{}) |> halt()
      else
        _ -> conn |> put_status(:bad_request) |> json(%{error: "Invalid Bazel trace profile"}) |> halt()
      end
    end
  end

  defp valid_string?(value), do: is_binary(value) and byte_size(value) in 1..255
end
