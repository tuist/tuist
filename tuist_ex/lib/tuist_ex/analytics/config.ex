defmodule TuistEx.Analytics.Config do
  @moduledoc false

  # Resolves the server origin and the project handle (`"account/project"`)
  # for an analytics submission. Precedence mirrors TuistEx.Auth's URL rules:
  # env override → runtime option → mix project config → default.

  @default_url "https://tuist.dev"

  def resolve(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)

    with {:ok, url} <- resolve_url(options, environment),
         {:ok, project_handle} <- resolve_project_handle(options, environment) do
      {:ok, %{url: url, project_handle: project_handle}}
    end
  end

  defp resolve_url(options, environment) do
    project_url = Keyword.get(project_tuist_config(options), :url)
    url = environment.("TUIST_URL") || Keyword.get(options, :url) || project_url || @default_url

    if valid_url?(url) do
      {:ok, String.trim_trailing(url, "/")}
    else
      {:error, "Invalid Tuist server URL: #{inspect(url)}"}
    end
  end

  # Match the same strictness as TuistEx.Auth.server_url/2: reject userinfo,
  # query strings, and fragments so we don't concatenate a path onto them and
  # route the request to nowhere.
  defp valid_url?(url) do
    uri = URI.parse(url)

    uri.scheme in ["http", "https"] and
      is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment)
  end

  defp resolve_project_handle(options, environment) do
    project_handle =
      environment.("TUIST_PROJECT") ||
        Keyword.get(options, :project) ||
        Keyword.get(project_tuist_config(options), :project)

    case project_handle do
      handle when is_binary(handle) ->
        case String.split(handle, "/") do
          [account, project] when account != "" and project != "" ->
            {:ok, %{account: account, project: project}}

          _ ->
            {:error,
             "Invalid Tuist project handle #{inspect(handle)}: expected \"account/project\""}
        end

      _ ->
        {:error,
         "Missing Tuist project handle. Set TUIST_PROJECT or add tuist: [project: \"account/project\"] to your Mix project."}
    end
  end

  @doc """
  The `:tuist` options of the Mix project, or an empty list without any.
  `options[:project_config]` takes their place when given: in an umbrella,
  tests run inside each child app, whose project does not have the root's.
  """
  def project_tuist_config(options \\ []) do
    Keyword.get_lazy(options, :project_config, fn ->
      case Mix.Project.config()[:tuist] do
        value when is_list(value) -> value
        _ -> []
      end
    end)
  end
end
