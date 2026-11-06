defmodule Tuist.Docs.ReleaseStatus do
  @moduledoc """
  Disposable public GitHub release snapshots. Successful observations are fresh
  for ten minutes and retained for at most a day during outages. Failed fills
  are coalesced and cached for thirty seconds; replicas may independently fill.

  The unpaginated Git matching-refs inventory is shared across components.
  Tags are semantic candidates only: each selected channel must be verified
  against a public GitHub release, with at most five checks per channel.
  History shares at most ten release pages across components, retaining only
  public stable, patch and RC metadata. It is explicitly a bounded snapshot,
  not an exhaustive archive (GitHub orders pages by creation, not publication).
  """

  alias Oban.Cron.Expression
  alias Tuist.Environment
  alias Tuist.KeyValueStore

  @api "https://api.github.com/repos/tuist/tuist"
  @fresh_seconds 600
  @retention_seconds 86_400
  @max_candidates 5
  @max_history_pages 10

  @doc """
  Returns release channels, the latest promotion attempt (including manual
  recovery), and four strictly future UTC workflow windows. Options `:cache`
  and `:now` allow isolated caches and deterministic clock-based consumers.
  Unknown or malformed workflow schedules produce an empty calendar.
  """
  def get(component, opts \\ []) when component in [:cli, :server, :kura] do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    cache_opts = Keyword.take(opts, [:cache])
    key = [__MODULE__, component]
    previous = KeyValueStore.get(key, cache_opts)

    result =
      if fresh?(previous, now) do
        {:ok, previous}
      else
        fill(key, now, cache_opts, fn -> fetch(component, now, cache_opts) end)
      end

    case result do
      {:ok, snapshot} -> present(snapshot, :fresh, now)
      _ -> fallback(previous, component, now)
    end
  end

  defp fresh?(%{checked_at: checked_at}, now), do: DateTime.diff(now, checked_at) in 0..(@fresh_seconds - 1)
  defp fresh?(_, _), do: false

  defp fill(key, now, opts, fetch) do
    # A time-bucketed attempt key also makes failure expiry deterministic for
    # callers with an injected clock, without extending successful freshness.
    attempt_key = key ++ [:attempt, div(DateTime.to_unix(now), 30)]

    KeyValueStore.get_or_update(attempt_key, Keyword.put(opts, :ttl, 30_000), fn ->
      case fetch.() do
        {:ok, snapshot} = result ->
          KeyValueStore.put(key, snapshot, Keyword.put(opts, :ttl, @retention_seconds * 1000))
          result

        error ->
          error
      end
    end)
  end

  defp fetch(component, now, opts) do
    workflow = "#{component}-promote.yml"

    with {:ok, tags} <- tags(now, opts),
         {:ok, channels} <- channels(tags, component),
         {:ok, %{status: 200, body: yaml}} when is_binary(yaml) <-
           request("#{@api}/contents/.github/workflows/#{workflow}?ref=main", "application/vnd.github.raw+json"),
         {:ok, %{status: 200, body: %{"workflow_runs" => runs}}} when is_list(runs) <-
           request("#{@api}/actions/workflows/#{workflow}/runs?per_page=1&branch=main"),
         {:ok, promotion} <- promotion(runs) do
      {:ok,
       Map.merge(channels, %{
         checked_at: now,
         crons: parse_schedule(yaml),
         promotion: promotion,
         history: history(component, now, opts),
         workflow_url: workflow_url(component)
       })}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp tags(now, opts) do
    key = [__MODULE__, :tags]

    case KeyValueStore.get(key, opts) do
      %{tags: tags} = snapshot ->
        if fresh?(snapshot, now), do: {:ok, tags}, else: fetch_tags(key, now, opts)

      _ ->
        fetch_tags(key, now, opts)
    end
  end

  defp fetch_tags(key, now, opts) do
    case fill(key, now, opts, fn ->
           with {:ok, %{status: 200, body: refs} = response} when is_list(refs) <-
                  request("#{@api}/git/matching-refs/tags/"),
                false <- next_page?(response),
                true <- Enum.all?(refs, &match?(%{"ref" => "refs/tags/" <> _}, &1)) do
             tags = Enum.map(refs, &String.replace_prefix(&1["ref"], "refs/tags/", ""))
             {:ok, %{checked_at: now, tags: tags}}
           else
             _ -> {:error, :incomplete_inventory}
           end
         end) do
      {:ok, %{tags: tags}} -> {:ok, tags}
      error -> error
    end
  end

  defp next_page?(response) do
    response
    |> Map.get(:headers, %{})
    |> Enum.any?(fn {key, values} ->
      String.downcase(key) == "link" and Enum.any?(List.wrap(values), &String.contains?(&1, "rel=\"next\""))
    end)
  end

  defp history(component, now, opts) do
    key = [__MODULE__, :history]
    previous = KeyValueStore.get(key, opts)

    result =
      if fresh?(previous, now) do
        {:ok, previous}
      else
        fill(key, now, opts, fn ->
          case fetch_history(1, []) do
            {:ok, history} -> {:ok, Map.put(history, :checked_at, now)}
            error -> error
          end
        end)
      end

    case result do
      {:ok, history} ->
        %{
          releases: history.releases |> Enum.filter(&(&1.component == component)) |> Enum.uniq_by(& &1.version),
          limited?: history.limited?
        }

      _ ->
        nil
    end
  end

  defp fetch_history(page, releases) do
    case request("#{@api}/releases?per_page=100&page=#{page}") do
      {:ok, %{status: 200, body: entries} = response} when is_list(entries) ->
        releases = releases ++ Enum.flat_map(entries, &historical_release/1)

        if next_page?(response) && page < @max_history_pages do
          fetch_history(page + 1, releases)
        else
          {:ok, %{releases: releases, limited?: next_page?(response)}}
        end

      _ when page > 1 ->
        {:ok, %{releases: releases, limited?: true}}

      _ ->
        {:error, :history_unavailable}
    end
  end

  defp historical_release(entry) do
    for component <- [:cli, :server, :kura],
        release <- parse_release(entry, component),
        release.channel != :canary do
      # A patch version alone does not establish which branch it was backported from.
      kind = if release.channel == :stable && release.version.patch > 0, do: :patch, else: release.channel
      Map.merge(public_release(release), %{component: component, kind: kind})
    end
  end

  defp channels(tags, component) do
    candidates =
      tags
      |> Enum.flat_map(&parse_tag(&1, component))
      |> Enum.sort_by(& &1.version, {:desc, Version})

    with {:ok, stable} when not is_nil(stable) <- find_release(candidates, :stable, component),
         pending =
           Enum.filter(candidates, fn candidate ->
             {candidate.version.major, candidate.version.minor} > {stable.version.major, stable.version.minor}
           end),
         {:ok, rc} <- find_release(pending, :rc, component),
         {:ok, canary} <- find_release(candidates, :canary, component) do
      # An RC for a line that has already shipped is historical, not pending.
      {:ok, %{stable: public_release(stable), rc: public_release(rc), canary: public_release(canary)}}
    else
      _ -> {:error, :incomplete_channels}
    end
  end

  defp parse_tag(tag, component) do
    prefix = if component == :cli, do: "", else: "#{component}@"

    with true <- String.starts_with?(tag, prefix),
         {:ok, version} <- Version.parse(String.replace_prefix(tag, prefix, "")),
         channel when not is_nil(channel) <- channel(version, version.pre != []) do
      [%{version: version, tag: tag, channel: channel}]
    else
      _ -> []
    end
  end

  defp find_release(candidates, channel, component) do
    candidates
    |> Enum.filter(&(&1.channel == channel))
    |> verify_candidates(component, @max_candidates)
  end

  defp verify_candidates([], _component, _remaining), do: {:ok, nil}
  defp verify_candidates(_candidates, _component, 0), do: {:error, :candidate_limit}

  defp verify_candidates([candidate | rest], component, remaining) do
    tag = URI.encode(candidate.tag, &URI.char_unreserved?/1)

    case request("#{@api}/releases/tags/#{tag}") do
      {:ok, %{status: 404}} ->
        verify_candidates(rest, component, remaining - 1)

      {:ok, %{status: 200, body: release}} ->
        case parse_release(release, component) do
          [%{version: version, channel: channel} = release]
          when version == candidate.version and channel == candidate.channel ->
            {:ok, release}

          _ ->
            verify_candidates(rest, component, remaining - 1)
        end

      _ ->
        {:error, :unavailable}
    end
  end

  defp parse_release(
         %{
           "draft" => false,
           "prerelease" => prerelease,
           "tag_name" => tag,
           "published_at" => published_at,
           "html_url" => url
         },
         component
       )
       when is_binary(tag) and is_binary(published_at) and is_binary(url) do
    with [%{version: version}] <- parse_tag(tag, component),
         channel when not is_nil(channel) <- channel(version, prerelease),
         {:ok, published_at, _} <- DateTime.from_iso8601(published_at) do
      [%{version: version, channel: channel, url: url, published_at: published_at}]
    else
      _ -> []
    end
  end

  defp parse_release(_, _), do: []

  defp channel(%Version{pre: []}, false), do: :stable
  defp channel(%Version{pre: ["rc", number]}, true) when is_integer(number), do: :rc
  defp channel(%Version{pre: ["canary", number]}, true) when is_integer(number), do: :canary
  defp channel(_, _), do: nil

  defp public_release(nil), do: nil

  defp public_release(release) do
    %{version: to_string(release.version), url: release.url, published_at: release.published_at}
  end

  defp promotion([]), do: {:ok, nil}

  defp promotion([%{"status" => status, "conclusion" => conclusion, "html_url" => url} | _])
       when is_binary(status) and is_binary(url) and (is_nil(conclusion) or is_binary(conclusion)) do
    {:ok, %{status: status, conclusion: conclusion, url: url}}
  end

  defp promotion(_), do: {:error, :invalid_run}

  defp parse_schedule(yaml) do
    with {:ok, document} when is_map(document) <- YamlElixir.read_from_string(yaml),
         %{"schedule" => schedules} when is_list(schedules) <- document["on"] do
      Enum.reduce_while(schedules, [], fn
        %{"cron" => cron}, acc when is_binary(cron) ->
          # GitHub schedules use five fields, not Oban's @reboot shortcuts.
          case {String.split(cron), Expression.parse(cron)} do
            {[_, _, day, _, weekday], {:ok, expression}} ->
              # POSIX cron uses OR when both day fields are restricted, whereas
              # Oban's matcher uses AND. Expand that case into two expressions.
              expressions =
                if not String.starts_with?(day, "*") and not String.starts_with?(weekday, "*") do
                  [
                    %{expression | weekdays: MapSet.new(0..6)},
                    %{expression | days: MapSet.new(1..31)}
                  ]
                else
                  [expression]
                end

              {:cont, expressions ++ acc}

            _ ->
              {:halt, []}
          end

        _, _ ->
          {:halt, []}
      end)
    else
      _ -> []
    end
  end

  defp schedule([], _now), do: []

  defp schedule(crons, now) do
    # Enumerate only the configured hours/minutes, with a bounded date horizon
    # so impossible dates cannot loop forever. Eight weeks covers four weekly
    # windows; less frequent workflows may honestly return fewer than four.
    date = DateTime.to_date(now)

    date
    |> Date.range(Date.add(date, 56))
    |> Stream.flat_map(fn date ->
      crons
      |> Enum.flat_map(fn cron ->
        for hour <- cron.hours,
            minute <- cron.minutes,
            datetime = DateTime.new!(date, Time.new!(hour, minute, 0)),
            Expression.now?(cron, datetime),
            DateTime.after?(datetime, now),
            do: datetime
      end)
      |> Enum.uniq()
      |> Enum.sort(DateTime)
    end)
    |> Enum.take(4)
  end

  defp present(snapshot, state, now) do
    snapshot
    |> Map.delete(:crons)
    |> Map.merge(%{state: state, schedule: schedule(snapshot.crons, now), history: present_history(snapshot, now)})
  end

  defp present_history(%{history: %{releases: releases, limited?: limited?}}, now) do
    cutoff = DateTime.add(now, -14, :day)

    {earlier, recent} =
      releases
      |> Enum.reject(&DateTime.after?(&1.published_at, now))
      |> Enum.sort_by(& &1.published_at, DateTime)
      |> Enum.split_with(&DateTime.before?(&1.published_at, cutoff))

    %{recent: recent, earlier: Enum.take(earlier, -20), limited?: limited? || length(earlier) > 20}
  end

  defp present_history(_, _now), do: nil

  defp fallback(%{checked_at: checked_at} = snapshot, component, now) do
    if DateTime.diff(now, checked_at) in 0..(@retention_seconds - 1),
      do: present(snapshot, :stale, now),
      else: fallback(nil, component, now)
  end

  defp fallback(_, component, _now) do
    %{
      state: :unavailable,
      checked_at: nil,
      stable: nil,
      rc: nil,
      canary: nil,
      promotion: nil,
      schedule: [],
      workflow_url: workflow_url(component)
    }
  end

  defp workflow_url(component), do: "https://github.com/tuist/tuist/actions/workflows/#{component}-promote.yml"

  defp request(url, accept \\ "application/vnd.github+json") do
    headers = [{"accept", accept}, {"user-agent", "tuist-server"}]
    token = Environment.github_token_update_package_releases()
    headers = if is_binary(token) and token != "", do: [{"authorization", "Bearer #{token}"} | headers], else: headers

    case Req.get(url,
           headers: headers,
           finch: Tuist.Finch,
           decode_body: accept != "application/vnd.github.raw+json",
           retry: false,
           redirect: false,
           pool_timeout: 2_000,
           receive_timeout: 3_000
         ) do
      {:ok, %{status: status} = response} when status in [200, 404] -> {:ok, response}
      _ -> {:error, :github_unavailable}
    end
  end
end
