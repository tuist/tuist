defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating Open Graph meta tag assigns for LiveView pages.
  """

  alias Tuist.Accounts.Account
  alias Tuist.OpenGraphImageTemplates
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @image_token_salt "open_graph_image"
  @image_token_max_age 34_560_000
  @image_token_period 604_800
  @max_image_path_bytes 2_000

  @doc """
  Returns OpenGraph assigns for dashboard pages.

  Returns assigns for `head_image` and `head_twitter_card`. The images are
  generic and don't contain any project-specific information, so they are
  shown for all projects regardless of visibility.

  ## Parameters

    * `image_name` - The name of the image file (without extension or path prefix)

  ## Examples

      og_image_assigns("overview")
      og_image_assigns("build-runs")

  """
  def og_image_assigns(image_name) do
    [
      head_image: Tuist.Environment.app_url(path: "/images/open-graph/dashboard/#{image_name}.jpg"),
      head_twitter_card: "summary_large_image"
    ]
  end

  @doc """
  Returns content-addressed Open Graph assigns for a public project page.

  Private projects keep using a generic checked-in image so project names,
  logos, and metrics never become available through a public image URL.
  """
  def project_image_assigns(%Project{visibility: :public} = project, opts) do
    with slug when is_binary(slug) <- project_slug(project),
         {:ok, path} <- project_image_path(slug, opts) do
      [
        head_image: Tuist.Environment.app_url(path: path),
        head_twitter_card: "summary_large_image"
      ]
    else
      _ -> og_image_assigns(Keyword.get(opts, :fallback, "overview"))
    end
  end

  def project_image_assigns(%Project{}, opts) do
    og_image_assigns(Keyword.get(opts, :fallback, "overview"))
  end

  defp project_image_path(slug, opts) do
    variables =
      [
        project: slug,
        title: normalized_text(Keyword.get(opts, :title), 160),
        subtitle: normalized_text(Keyword.get(opts, :subtitle), 200),
        badge: normalized_text(Keyword.get(opts, :badge), 60),
        locale: Gettext.get_locale(TuistWeb.Gettext)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    path = image_path(:project, variables)

    if byte_size(path) <= @max_image_path_bytes, do: {:ok, path}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp normalized_text(value, max_length) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> String.slice(value, 0, max_length)
    end
  end

  defp normalized_text(value, max_length) when not is_nil(value) do
    value |> to_string() |> normalized_text(max_length)
  end

  defp normalized_text(nil, _max_length), do: nil

  defp project_slug(%Project{account: %Account{name: account_name}, name: project_name}) do
    "#{account_name}/#{project_name}"
  end

  defp project_slug(%Project{id: project_id}) when not is_nil(project_id) do
    Projects.get_project_slug_from_id(project_id)
  end

  defp project_slug(%Project{}), do: nil

  @doc """
  Builds a deterministic, signed, content-addressed Open Graph image path.

  ## Examples

      image_path(:marketing, title: "About Tuist", icon: "about")
      image_path(:docs, title: "Install Tuist", category: "Guides")

  """
  def image_path(template, variables) do
    params =
      Enum.reduce(variables, %{"template" => to_string(template)}, fn
        {_key, nil}, params ->
          params

        {key, value}, params ->
          Map.put(params, to_string(key), to_string(value))
      end)

    case OpenGraphImageTemplates.spec(params) do
      {:ok, spec} ->
        token =
          Phoenix.Token.sign(
            TuistWeb.Endpoint,
            @image_token_salt,
            Enum.sort(spec.params),
            signed_at: token_period_start()
          )

        path = "/open-graph-images/#{spec.key}.jpg?#{URI.encode_query(token: token)}"

        if byte_size(path) <= @max_image_path_bytes do
          path
        else
          raise ArgumentError, "Open Graph image path exceeds #{@max_image_path_bytes} bytes"
        end

      :error ->
        raise ArgumentError, "invalid Open Graph image template variables"
    end
  end

  def verify_image_token(token) when is_binary(token) do
    case Phoenix.Token.verify(
           TuistWeb.Endpoint,
           @image_token_salt,
           token,
           max_age: @image_token_max_age
         ) do
      {:ok, params} when is_list(params) -> {:ok, Map.new(params)}
      _ -> :error
    end
  end

  def verify_image_token(_token), do: :error

  defp token_period_start do
    timestamp = System.system_time(:second)
    div(timestamp, @image_token_period) * @image_token_period
  end
end
