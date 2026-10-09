defmodule TuistWeb.PublicOverviewCache do
  @moduledoc false
  use Supervisor

  import Cachex.Spec, only: [hook: 1]

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Accounts
  alias Tuist.KeyValueStore
  alias Tuist.KeyValueStore.LoadLimiter
  alias TuistWeb.Authorization
  alias TuistWeb.Gettext, as: WebGettext

  require LiveView
  require Logger

  @loaders __MODULE__.Loaders
  @values __MODULE__.Values
  @max_value_bytes 128 * 1_024
  @connected_timeout to_timeout(second: 30)
  @cache_opts [cache: @values, persist_across_deployments: true, ttl: to_timeout(minute: 10)]

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    children = [
      {Cachex, [@values, [hooks: [hook(module: Cachex.Limit.Evented, args: {256, []})]]]},
      {LoadLimiter,
       Keyword.merge([name: @loaders, queue_timeout: to_timeout(second: 30), on_error: &report_error/1], opts)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def public_root?(%{visibility: :public} = project, uri) do
    uri = URI.parse(uri)

    uri.path in ["/#{project.account.name}/#{project.name}", "/#{project.account.name}/#{project.name}/"] and
      default_params?(URI.decode_query(uri.query || "")) and anonymously_readable_account?(project.account)
  end

  def public_root?(_project, _uri), do: false

  def default_params?(params) do
    Enum.all?(params, fn {key, _value} ->
      String.starts_with?(key, "utm_") or key in ["fbclid", "gclid", "ref"]
    end)
  end

  def assign_async(socket, keys, loader) do
    if socket.assigns[:cached_public_overview] do
      project = socket.assigns.selected_project
      locale = Gettext.get_locale(WebGettext)

      if LiveView.connected?(socket) do
        user = socket.assigns[:current_user]
        deadline = System.monotonic_time(:millisecond) + @connected_timeout
        connected_loader = fn -> fetch_connected(project, user, keys, loader, locale, deadline, 100) end
        LiveView.assign_async(socket, keys, connected_loader)
      else
        pending = socket.private[:public_overview_loaders] || []
        cached_loader = fn -> fetch(project, keys, loader, locale) end
        socket = LiveView.put_private(socket, :public_overview_loaders, [{List.wrap(keys), cached_loader} | pending])
        Enum.reduce(List.wrap(keys), socket, &Component.assign(&2, &1, AsyncResult.loading()))
      end
    else
      LiveView.assign_async(socket, keys, loader)
    end
  end

  def resolve_pending(socket) do
    pending = socket.private[:public_overview_loaders] || []

    pending
    |> Enum.reverse()
    |> Task.async_stream(fn {keys, loader} -> {keys, loader.()} end,
      max_concurrency: max(length(pending), 1),
      timeout: :infinity
    )
    |> Enum.reduce(socket, fn {:ok, {keys, result}}, socket ->
      Enum.reduce(keys, socket, fn key, socket ->
        result =
          case result do
            {:ok, values} -> AsyncResult.ok(Map.fetch!(values, key))
            {:error, reason} -> AsyncResult.failed(AsyncResult.loading(), {:error, reason})
          end

        Component.assign(socket, key, result)
      end)
    end)
    |> LiveView.put_private(:public_overview_loaders, [])
  end

  def load(socket, key, loader) do
    if socket.assigns[:cached_public_overview] do
      case fetch(
             socket.assigns.selected_project,
             key,
             fn -> {:ok, %{key => loader.()}} end,
             Gettext.get_locale(WebGettext)
           ) do
        {:ok, values} -> {:ok, Map.fetch!(values, key)}
        {:error, _reason} = error -> error
      end
    else
      {:ok, loader.()}
    end
  end

  defp fetch(project, keys, loader, locale, timeout \\ :infinity) do
    identity =
      {:v2, project.id, project.build_system, project.account.name, project.name, locale, Enum.sort(List.wrap(keys))}

    key = "public-overview:" <> Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(identity)), case: :lower)

    case get_cached(key) do
      values when is_map(values) ->
        {:ok, values}

      _ ->
        case LoadLimiter.run(@loaders, key, fn -> read_or_load(key, loader, locale) end, timeout) do
          {:ok, result} -> result
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp read_or_load(key, loader, locale) do
    # Another worker or pod may have filled the shared cache while queued.
    case get_cached(key) do
      values when is_map(values) ->
        {:ok, values}

      _ ->
        case Gettext.with_locale(WebGettext, locale, loader) do
          {:ok, values} = result when is_map(values) ->
            if :erlang.external_size(values) <= @max_value_bytes do
              store(key, values)
            else
              Logger.warning("Public overview value exceeds #{@max_value_bytes} bytes and will not be cached")
            end

            result

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp get_cached(key) do
    KeyValueStore.get(key, @cache_opts)
  rescue
    exception ->
      Logger.warning("Public overview cache read failed: #{Exception.message(exception)}")
      nil
  catch
    :exit, reason ->
      Logger.warning("Public overview cache read exited: #{inspect(reason)}")
      nil
  end

  defp store(key, values) do
    case KeyValueStore.put(key, values, @cache_opts) do
      {:error, reason} -> Logger.warning("Public overview cache write failed: #{inspect(reason)}")
      _ -> :ok
    end
  rescue
    exception -> Logger.warning("Public overview cache write failed: #{Exception.message(exception)}")
  catch
    :exit, reason -> Logger.warning("Public overview cache write exited: #{inspect(reason)}")
  end

  defp fetch_connected(project, user, keys, loader, locale, deadline, backoff) do
    remaining = deadline - System.monotonic_time(:millisecond)
    result = if remaining > 0, do: fetch(project, keys, loader, locale, remaining), else: {:error, :timeout}

    if result in [{:error, :overloaded}, {:error, :timeout}] and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(min(backoff, max(deadline - System.monotonic_time(:millisecond), 0)))

      current =
        Authorization.require_user_can_read_project(%{
          user: user,
          account_handle: project.account.name,
          project_handle: project.name
        })

      if same_project?(current, project) and public_root?(current, "/#{current.account.name}/#{current.name}") do
        fetch_connected(project, user, keys, loader, locale, deadline, min(backoff * 2, 1_000))
      else
        {:error, :forbidden}
      end
    else
      result
    end
  end

  defp same_project?(left, right) do
    {left.id, left.build_system, left.name, left.account.name} ==
      {right.id, right.build_system, right.name, right.account.name}
  end

  defp anonymously_readable_account?(%{visibility: :public}), do: true
  defp anonymously_readable_account?(%{organization_id: nil}), do: true

  defp anonymously_readable_account?(%{organization_id: organization_id}) do
    case Accounts.get_organization_by_id(organization_id, preload: []) do
      {:ok, organization} -> not organization.sso_enforced or is_nil(organization.sso_provider)
      {:error, _reason} -> false
    end
  end

  defp report_error({:exception, exception, stacktrace}), do: Sentry.capture_exception(exception, stacktrace: stacktrace)
  defp report_error(_reason), do: :ok
end
