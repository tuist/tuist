defmodule TuistWeb.Plugs.ReportPublishingPlug do
  @moduledoc """
  Authorizes structured report creation, never archive uploads, reads, or cache
  operations. Network publishers remain unauthenticated and cannot select IDs,
  attach existing artifacts, schedule processors, or invoke privileged automation.
  """
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Plug.Conn.Utils
  alias Tuist.Environment
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.LoaderPlug
  alias TuistWeb.RateLimit

  @limits [
    tasks: 20_000,
    machine_metrics: 5_000,
    configuration_operations: 5_000,
    artifact_transforms: 5_000,
    files: 20_000,
    targets: 5_000,
    issues: 10_000,
    cacheable_tasks: 20_000,
    cas_outputs: 20_000,
    diagnostics: 10_000,
    steps: 20_000,
    test_cases: 20_000,
    test_modules: 5_000
  ]
  @protected_fields ~w(generation_id build_run_id gradle_build_id shard_plan_id shard_index
                       coverage xcode_coverage xcode_coverage_storage_key git_history stress_new_tests)a

  @test_fields ~w(id duration status is_ci model_identifier scheme ran_at macos_version xcode_version
                   git_branch git_commit_sha git_ref ci_provider ci_run_id ci_project_handle ci_host
                   build_system test_modules execution_mode only_test_identifiers skip_test_identifiers)a

  def init(opts), do: opts

  def call(conn, {:preflight, kind}) do
    if Authentication.authenticated?(conn) do
      conn
    else
      conn = call(conn, kind)
      if conn.halted, do: conn, else: put_private(conn, :network_publication_authorized, true)
    end
  end

  def call(%{private: %{network_publication_authorized: true}} = conn, kind) do
    if allowed_report?(conn, kind),
      do: conn,
      else: reject(conn, :bad_request, "Unsupported network-trusted report fields.")
  end

  def call(conn, kind) do
    loaded_conn =
      if Authentication.authenticated?(conn) do
        LoaderPlug.call(conn, [])
      else
        # Revocation must not wait for the authenticated project lookup cache.
        conn |> assign(:caching, false) |> LoaderPlug.call([])
      end

    authorize_publication(loaded_conn, kind)
  rescue
    error in NotFoundError ->
      if Authentication.authenticated?(conn), do: reraise(error, __STACKTRACE__), else: deny_publication(conn)
  end

  def parameters(conn, body) do
    if network_publisher?(conn), do: Map.put(body, :id, UUIDv7.generate()), else: body
  end

  def network_publisher?(conn), do: conn.private[:network_publication_authorized] == true

  def enabled?(project) do
    Environment.network_trusted_build_publishing_enabled?() and project.network_trusted_builds
  end

  defp authorize_publication(%{assigns: %{selected_project: project}} = conn, kind) do
    cond do
      Authentication.authenticated?(conn) ->
        AuthorizationPlug.authorize_project(conn, if(kind == :test, do: :test, else: :build), action: :create)

      not eligible_project?(project, kind, conn.body_params) ->
        deny_publication(conn)

      not json_report?(conn) ->
        reject(conn, :unsupported_media_type, "Network-trusted reports require application/json.")

      not bounded_report?(conn.body_params, kind) ->
        reject(conn, 413, "The report exceeds network-trusted publishing limits.")

      not allowed_report?(conn, kind) or protected_report?(conn.body_params) ->
        reject(
          conn,
          :bad_request,
          "Network-trusted publishing accepts completed structured reports without artifact, shard, history, or existing-report references."
        )

      true ->
        limit(conn, project.id)
    end
  end

  defp eligible_project?(project, kind, body), do: enabled?(project) and compatible?(project, kind, body)

  defp compatible?(project, :test, body) do
    system = value(body, :build_system) || "xcode"
    system in [project.build_system, Atom.to_string(project.build_system)]
  end

  defp compatible?(project, kind, _body), do: project.build_system == kind

  defp json_report?(conn) do
    case get_req_header(conn, "content-type") do
      [value] -> match?({:ok, "application", "json", _}, Utils.media_type(value))
      _ -> false
    end
  end

  defp protected_report?(body) do
    value(body, :status) in ["processing", :processing, "failed_processing", :failed_processing] or
      value(body, :xcode_cache_upload_enabled) == true or
      value(body, :only_test_identifiers) not in [nil, []] or value(body, :skip_test_identifiers) not in [nil, []] or
      Enum.any?(@protected_fields, &(value(body, &1) not in [nil, "", [], %{}]))
  end

  defp bounded_report?(body, kind) when is_map(body) do
    Enum.all?(@limits, fn {key, maximum} ->
      items = value(body, key) || []
      is_list(items) and length(items) <= maximum
    end) and structure_budget(body, if(kind == :test, do: 100_000, else: 1_000_000), 0) >= 0
  end

  defp bounded_report?(_, _), do: false

  # Use the reporting contract as a recursive allowlist, not its permissive
  # additional-properties default. Typed metadata maps remain opaque strings.
  defp allowed_report?(conn, kind) do
    schema =
      conn.private.phoenix_controller.open_api_operation(conn.private.phoenix_action).requestBody.content[
        "application/json"
      ].schema

    top_level_allowed? =
      kind != :test or
        Enum.all?(Map.keys(conn.body_params), fn key ->
          Enum.any?(@test_fields, &(key == &1 or key == Atom.to_string(&1)))
        end)

    top_level_allowed? and allowed_value?(conn.body_params, schema)
  end

  defp allowed_value?(value, schema) when is_atom(schema), do: allowed_value?(value, schema.schema())

  defp allowed_value?(value, %Schema{type: :array, items: items}) when is_list(value),
    do: Enum.all?(value, &allowed_value?(&1, items))

  defp allowed_value?(value, %Schema{type: :object, properties: properties, additionalProperties: additional})
       when is_map(value) do
    Enum.all?(value, fn {key, child} ->
      case Enum.find(properties || %{}, fn {known, _schema} -> key == known or key == Atom.to_string(known) end) do
        {_key, schema} -> allowed_value?(child, schema)
        nil -> match?(%Schema{}, additional) and allowed_value?(child, additional)
      end
    end)
  end

  defp allowed_value?(%DateTime{}, %Schema{type: :string, format: :"date-time"}), do: true
  defp allowed_value?(%NaiveDateTime{}, %Schema{type: :string, format: :"date-time"}), do: true
  defp allowed_value?(%Date{}, %Schema{type: :string, format: :date}), do: true
  # A schema evolution must not silently make arbitrary nested keys writable.
  defp allowed_value?(value, _schema) when is_map(value) or is_list(value), do: false
  defp allowed_value?(_value, %Schema{}), do: true
  defp allowed_value?(_value, _schema), do: false

  # A small JSON body can still produce many child rows or deeply nested work.
  defp structure_budget(_value, _budget, depth) when depth > 32, do: -1
  defp structure_budget(_value, budget, _depth) when budget < 0, do: -1
  defp structure_budget(%_{} = value, budget, depth), do: structure_budget(Map.from_struct(value), budget, depth)

  defp structure_budget(value, budget, depth) when is_map(value) do
    Enum.reduce_while(value, budget - map_size(value), fn {_key, child}, remaining ->
      remaining = structure_budget(child, remaining, depth + 1)
      if remaining < 0, do: {:halt, -1}, else: {:cont, remaining}
    end)
  end

  defp structure_budget(value, budget, depth) when is_list(value) do
    Enum.reduce_while(value, budget - length(value), fn child, remaining ->
      remaining = structure_budget(child, remaining, depth + 1)
      if remaining < 0, do: {:halt, -1}, else: {:cont, remaining}
    end)
  end

  defp structure_budget(_value, budget, _depth), do: budget

  defp value(body, key), do: Map.get(body, key, Map.get(body, Atom.to_string(key)))

  defp limit(conn, project_id) do
    with :ok <- quota("network-builds:minute:#{project_id}", 60, to_timeout(minute: 1)),
         :ok <- quota("network-builds:day:#{project_id}", 10_000, to_timeout(day: 1)) do
      conn
    else
      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> reject(:too_many_requests, "Network-trusted publishing quota exceeded.")

      {:error, :unavailable} ->
        reject(conn, :service_unavailable, "Publishing quota service is unavailable.")
    end
  end

  defp quota(key, limit, window) do
    case RateLimit.hit(key, limit: limit, window: window, fallback: false) do
      {:allow, _} -> :ok
      {:deny, remaining_ms} -> {:deny, max(1, div(remaining_ms + 999, 1000))}
      {:error, :unavailable} = error -> error
    end
  end

  defp deny_publication(conn), do: reject(conn, :forbidden, "This project does not accept network-trusted publishing.")
  defp reject(conn, status, message), do: conn |> put_status(status) |> json(%{message: message}) |> halt()
end
