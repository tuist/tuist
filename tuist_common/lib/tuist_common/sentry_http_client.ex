defmodule TuistCommon.SentryHTTPClient do
  @moduledoc """
  Sentry HTTP client that uses Finch.

  When `config :tuist_common, :sentry_pulse_dsn` holds a DSN, every envelope
  Sentry posts to its own DSN (Atlas) is also posted to Pulse, so the two
  backends can be compared. Atlas stays primary: the copy is a fire-and-forget
  task on its own connection pool, so a slow, failing or unreachable Pulse never
  delays, drops or fails the Atlas request, whose result is what Sentry sees.
  At most 50 copies run at once; further copies are dropped. The copy is not
  retried, but Sentry's retries of a failed Atlas request each send one, which
  Pulse merges because they carry the same event.
  """

  @behaviour Sentry.HTTPClient

  @finch_name TuistCommon.SentryFinch
  @pulse_finch_name TuistCommon.SentryPulseFinch
  @pulse_tasks TuistCommon.SentryPulseTasks
  @pulse_max_in_flight 50

  @impl true
  def child_spec do
    # The copy's pool and tasks get their own subtree that is not restarted:
    # however often it fails, it can never take the Atlas pool down with it.
    # Without it, copies are skipped.
    pulse =
      Supervisor.child_spec(
        %{
          id: :pulse,
          start:
            {Supervisor, :start_link,
             [
               [
                 {Finch,
                  name: @pulse_finch_name,
                  pools: %{default: [conn_opts: [transport_opts: [timeout: 2_000]]]}},
                 {Task.Supervisor, name: @pulse_tasks, max_children: @pulse_max_in_flight}
               ],
               [strategy: :one_for_one]
             ]},
          type: :supervisor
        },
        restart: :temporary
      )

    %{
      id: __MODULE__,
      start:
        {Supervisor, :start_link, [[{Finch, name: @finch_name}, pulse], [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @impl true
  def post(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    result =
      case Finch.request(request, @finch_name) do
        {:ok, %Finch.Response{status: status, headers: response_headers, body: response_body}} ->
          {:ok, status, response_headers, response_body}

        {:error, error} ->
          {:error, error}
      end

    copy_to_pulse(headers, body)
    result
  end

  # After the Atlas request, so nothing here can keep it from being sent.
  defp copy_to_pulse(headers, body) do
    if dsn = Application.get_env(:tuist_common, :sentry_pulse_dsn) do
      # {:error, :max_children} when Pulse is backed up: the copy is dropped.
      Task.Supervisor.start_child(@pulse_tasks, fn -> post_to_pulse(dsn, headers, body) end)
    end
  catch
    # The copy's subtree is gone or busy.
    :exit, _reason -> :ok
  end

  # Never raises: a crashing task logs a crash report, which Sentry's logger
  # handler would report, and copy to Pulse, again.
  defp post_to_pulse(dsn, headers, body) do
    {url, auth} = pulse_endpoint(dsn)

    headers =
      Enum.map(headers, fn {name, value} ->
        if String.downcase(name) == "x-sentry-auth",
          do: {name, replace_auth(value, auth)},
          else: {name, value}
      end)

    :post
    |> Finch.build(url, headers, body)
    |> Finch.request(@pulse_finch_name,
      pool_timeout: 1_000,
      receive_timeout: 5_000,
      request_timeout: 10_000
    )
  catch
    _kind, _reason -> :error
  end

  # Builds the envelope URL the same way Sentry does from its own DSN:
  # `http://<key>:<secret>@<host>/<path>/<project>` posts to
  # `http://<host>/<path>/api/<project>/envelope/`. The secret is optional, as
  # in the server's public endpoint, whose DSN key is a percent-encoded
  # account token (`https://<token>@<host>/api/accounts/<handle>/pulse/sentry/<service>/1`).
  defp pulse_endpoint(dsn) do
    %URI{userinfo: userinfo, path: path} = uri = URI.parse(dsn)
    {base, [project]} = path |> String.split("/") |> Enum.split(-1)
    envelope_path = Enum.join(base ++ ["api", project, "envelope", ""], "/")

    auth =
      case String.split(userinfo, ":", parts: 2) do
        [key, secret] -> [sentry_key: key, sentry_secret: secret]
        [key] when key != "" -> [sentry_key: key]
      end

    {URI.to_string(%{uri | userinfo: nil, path: envelope_path}), auth}
  end

  # Keeps Sentry's version, client and timestamp fields and swaps Atlas's key
  # and secret for Pulse's.
  defp replace_auth("Sentry " <> fields, auth) do
    kept =
      fields
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&String.starts_with?(&1, ["sentry_key=", "sentry_secret="]))

    "Sentry " <>
      Enum.join(kept ++ Enum.map(auth, fn {name, value} -> "#{name}=#{value}" end), ", ")
  end
end
