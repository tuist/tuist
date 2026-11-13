defmodule Tuist.Docs.ReleaseStatusTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Docs.ReleaseStatus
  alias Tuist.Environment

  @now ~U[2026-12-28 06:00:00Z]
  @yaml "on:\n  schedule:\n    - cron: '0 6 * * 1'\n"
  @run %{
    "status" => "completed",
    "conclusion" => "success",
    "html_url" => "https://github.com/tuist/tuist/actions/runs/123"
  }

  setup do
    cache = String.to_atom("release-status-#{UUIDv7.generate()}")
    start_supervised!({Cachex, name: cache})
    stub(Environment, :github_token_update_package_releases, fn -> nil end)
    %{opts: [cache: cache, now: @now]}
  end

  for component <- [:cli, :server, :kura] do
    prefix = if component == :cli, do: "", else: "#{component}@"

    test "selects semantic channels for #{component}, not publication order", %{opts: opts} do
      component = unquote(component)
      prefix = unquote(prefix)

      releases =
        Enum.map(
          ["2.9.99", "2.10.0", "2.11.0-canary.9", "2.11.0-canary.10", "2.11.0-rc.9", "2.11.0-rc.10"],
          &release(prefix <> &1)
        ) ++
          [
            release(prefix <> "9.0.0", %{"draft" => true}),
            release(prefix <> "8.0.0", %{"prerelease" => true}),
            release(prefix <> "9.0.0-canary.99", %{"prerelease" => false}),
            release("app@99.0.0"),
            release("99.0.0-beta.1")
          ]

      mock_github(releases)
      result = ReleaseStatus.get(component, opts)

      assert result.state == :fresh
      assert result.checked_at == @now
      assert result.stable.version == "2.10.0"
      assert result.canary.version == "2.11.0-canary.10"
      assert result.rc.version == "2.11.0-rc.10"
      assert result.rc.published_at == ~U[2026-12-20 12:00:00Z]
      assert result.rc.url == "https://github.com/tuist/tuist/releases/tag/#{prefix}2.11.0-rc.10"
      assert result.promotion == %{status: "completed", conclusion: "success", url: @run["html_url"]}
      assert result.workflow_url == "https://github.com/tuist/tuist/actions/workflows/#{component}-promote.yml"
    end
  end

  test "hides promoted RCs and patch RCs on the stable minor", %{opts: opts} do
    mock_github(Enum.map(["2.10.3", "2.10.0-rc.10", "2.10.4-rc.1", "2.9.0-rc.99"], &release/1))

    assert ReleaseStatus.get(:cli, opts).rc == nil
  end

  test "a new major RC remains pending even with a lower minor", %{opts: opts} do
    mock_github(Enum.map(["2.99.3", "3.0.0-rc.1"], &release/1))

    assert ReleaseStatus.get(:cli, opts).rc.version == "3.0.0-rc.1"
  end

  test "history uses publication dates, retains promoted RCs and older-line patches, and excludes canaries", %{opts: opts} do
    releases = [
      release("2.10.0", %{"published_at" => "2026-12-15T12:00:00Z"}),
      release("2.9.1", %{"published_at" => "2026-12-27T12:00:00Z"}),
      release("2.10.0-rc.1", %{"published_at" => "2026-12-14T06:00:00Z"}),
      release("2.9.0", %{"published_at" => "2026-12-14T05:59:59Z"}),
      release("2.11.0-rc.1", %{"published_at" => "2026-12-28T06:00:01Z"}),
      release("2.11.0-canary.1"),
      release("server@2.10.0"),
      release("9.0.0", %{"draft" => true}),
      release("8.0.0", %{"prerelease" => true}),
      release("7.0.0", %{"published_at" => nil})
    ]

    mock_github(releases)
    history = ReleaseStatus.get(:cli, opts).history

    assert Enum.map(history.recent, &{&1.version, &1.kind}) == [
             {"2.10.0-rc.1", :rc},
             {"2.10.0", :stable},
             {"2.9.1", :patch}
           ]

    assert hd(history.recent).published_at == ~U[2026-12-14 06:00:00Z]
    assert List.last(history.recent).url == "https://github.com/tuist/tuist/releases/tag/2.9.1"
    assert Enum.map(history.earlier, & &1.version) == ["2.9.0"]
    refute history.limited?
  end

  test "history paginates past canary noise without following remote link URLs", %{opts: opts} do
    next = %{"link" => ["<https://other.test/releases>; rel=\"next\""]}

    mock_github([release("2.10.0")],
      history_pages: [
        %{status: 200, body: [release("2.11.0-canary.1")], headers: next},
        %{status: 200, body: [release("2.10.0"), release("2.9.1")]}
      ]
    )

    assert %{recent: [%{version: "2.10.0"}, %{version: "2.9.1"}], limited?: false} =
             ReleaseStatus.get(:cli, opts).history
  end

  test "history pagination is bounded and explicitly incomplete", %{opts: opts} do
    page = %{
      status: 200,
      body: [release("2.10.0")],
      headers: %{"link" => ["<https://api.github.com/next>; rel=\"next\""]}
    }

    mock_github([release("2.10.0")], history_pages: List.duplicate(page, 10))

    assert %{recent: [%{version: "2.10.0"}], limited?: true} = ReleaseStatus.get(:cli, opts).history
  end

  test "history failures preserve verified channels and mark partial history honestly", %{opts: opts} do
    mock_github([release("2.10.0")], history_pages: [%{status: 503}])
    assert %{state: :fresh, stable: %{version: "2.10.0"}, history: nil} = ReleaseStatus.get(:cli, opts)

    mock_github([release("2.10.0")],
      history_pages: [
        %{
          status: 200,
          body: [release("2.9.1")],
          headers: %{"link" => ["<https://api.github.com/next>; rel=\"next\""]}
        },
        %{status: 503}
      ]
    )

    assert %{state: :fresh, history: %{recent: [%{version: "2.9.1"}], limited?: true}} =
             ReleaseStatus.get(:cli, Keyword.put(opts, :now, DateTime.add(@now, 600)))
  end

  test "schedule excludes the current boundary and crosses the year in UTC", %{opts: opts} do
    mock_github([release("1.0.0")])

    assert ReleaseStatus.get(:cli, opts).schedule == [
             ~U[2027-01-04 06:00:00Z],
             ~U[2027-01-11 06:00:00Z],
             ~U[2027-01-18 06:00:00Z],
             ~U[2027-01-25 06:00:00Z]
           ]

    before = Keyword.put(opts, :now, ~U[2026-12-28 05:59:59Z])
    assert hd(ReleaseStatus.get(:cli, before).schedule) == @now
  end

  test "schedule comes from YAML and merges overlapping cron windows", %{opts: opts} do
    yaml = "on:\n  schedule:\n    - cron: '15 9 * * 2'\n    - cron: '15 9 * * 2'\n    - cron: '30 10 * * 3'\n"
    mock_github([release("1.0.0")], yaml: yaml)

    assert ReleaseStatus.get(:cli, opts).schedule == [
             ~U[2026-12-29 09:15:00Z],
             ~U[2026-12-30 10:30:00Z],
             ~U[2027-01-05 09:15:00Z],
             ~U[2027-01-06 10:30:00Z]
           ]
  end

  for yaml <- [
        "on: [workflow_dispatch]",
        "on: {schedule: [{cron: 'invalid'}]}",
        "[broken",
        "on: {schedule: [{cron: '@reboot'}]}"
      ] do
    test "does not invent windows for unknown schedule #{inspect(yaml)}", %{opts: opts} do
      mock_github([release("1.0.0")], yaml: unquote(yaml))

      assert %{state: :fresh, schedule: []} = ReleaseStatus.get(:cli, opts)
    end
  end

  test "latest run includes manual recovery and permits an in-progress conclusion", %{opts: opts} do
    run = Map.merge(@run, %{"status" => "in_progress", "conclusion" => nil, "event" => "workflow_dispatch"})
    mock_github([release("1.0.0")], runs: [run])

    assert %{status: "in_progress", conclusion: nil} = ReleaseStatus.get(:cli, opts).promotion
  end

  test "retains successful data during failure without renewing its timestamp", %{opts: opts} do
    mock_github([release("1.0.0")])
    original = ReleaseStatus.get(:cli, opts)
    expect(Req, :get, fn _, _ -> {:error, :timeout} end)
    assert ReleaseStatus.get(:cli, Keyword.put(opts, :now, DateTime.add(@now, 599))) == original

    later = Keyword.put(opts, :now, DateTime.add(@now, 600))
    stale = ReleaseStatus.get(:cli, later)
    assert stale.state == :stale
    assert stale.stable == original.stable
    assert stale.checked_at == @now

    expect(Req, :get, fn _, _ -> {:ok, %{status: 503}} end)
    assert ReleaseStatus.get(:cli, later) == stale

    assert ReleaseStatus.get(:cli, Keyword.put(opts, :now, DateTime.add(@now, 86_400))).state == :unavailable
  end

  test "cold failures are briefly cached and recover on a later attempt", %{opts: opts} do
    expect(Req, :get, fn _, _ -> {:ok, %{status: 403}} end)
    unavailable = ReleaseStatus.get(:cli, opts)
    assert unavailable.state == :unavailable
    assert unavailable.checked_at == nil
    assert unavailable.stable == nil
    assert unavailable.schedule == []
    assert ReleaseStatus.get(:cli, opts) == unavailable

    mock_github([release("1.0.0")])
    assert ReleaseStatus.get(:cli, Keyword.put(opts, :now, DateTime.add(@now, 31))).state == :fresh
  end

  test "shares a complete tag inventory across components", %{opts: opts} do
    mock_github(Enum.map(["1.0.0", "server@2.0.0", "kura@3.0.0"], &release/1))
    assert ReleaseStatus.get(:cli, opts).state == :fresh

    expect(Req, :get, 6, fn url, _ ->
      cond do
        String.contains?(url, "/releases/tags/") ->
          {:ok, %{status: 200, body: url |> String.split("/tags/") |> List.last() |> URI.decode() |> release()}}

        String.contains?(url, "/contents/") ->
          {:ok, %{status: 200, body: @yaml}}

        String.contains?(url, "/runs?") ->
          {:ok, %{status: 200, body: %{"workflow_runs" => []}}}
      end
    end)

    assert ReleaseStatus.get(:server, opts).stable.version == "2.0.0"
    assert ReleaseStatus.get(:kura, opts).stable.version == "3.0.0"
  end

  test "checks public release metadata instead of treating a tag as a release", %{opts: opts} do
    mock_github([release("2.9.99"), release("2.10.0")])

    expect(Req, :get, fn url, request_opts ->
      assert String.ends_with?(url, "/git/matching-refs/tags/")
      assert request_opts[:retry] == false
      assert request_opts[:redirect] == false
      assert request_opts[:receive_timeout] == 3_000

      {:ok, %{status: 200, body: refs(["2.9.99", "2.10.0", "3.0.0"])}}
    end)

    expect(Req, :get, fn url, _ ->
      assert String.ends_with?(url, "/releases/tags/3.0.0")
      {:ok, %{status: 404}}
    end)

    result = ReleaseStatus.get(:cli, opts)
    assert result.stable.version == "2.10.0"
  end

  test "coalesces concurrent cold fills using the real isolated cache", %{opts: opts} do
    expect(Req, :get, 5, fn url, request_opts ->
      cond do
        String.contains?(url, "/git/matching-refs/") ->
          {:ok, %{status: 200, body: refs(["1.0.0"])}}

        String.contains?(url, "/releases/tags/") ->
          {:ok, %{status: 200, body: release("1.0.0")}}

        String.contains?(url, "/releases?") ->
          {:ok, %{status: 200, body: [release("1.0.0")]}}

        String.contains?(url, "/contents/") ->
          assert request_opts[:decode_body] == false
          {:ok, %{status: 200, body: @yaml}}

        String.contains?(url, "/runs?") ->
          {:ok, %{status: 200, body: %{"workflow_runs" => [@run]}}}
      end
    end)

    results =
      1..10
      |> Task.async_stream(fn _ -> ReleaseStatus.get(:cli, opts) end, max_concurrency: 10)
      |> Enum.to_list()

    assert length(results) == 10
    assert Enum.all?(results, &match?({:ok, %{state: :fresh, stable: %{version: "1.0.0"}}}, &1))
  end

  test "never follows an unexpected paginated inventory or claims it is complete", %{opts: opts} do
    expect(Req, :get, fn _url, _ ->
      {:ok, %{status: 200, body: refs(["1.0.0"]), headers: %{"link" => ["<https://other.test/>; rel=\"next\""]}}}
    end)

    assert %{state: :unavailable, stable: nil} = ReleaseStatus.get(:cli, opts)
  end

  test "candidate limit is explicit rather than silently choosing an older release", %{opts: opts} do
    mock_github([release("1.0.0")])
    expect(Req, :get, fn _, _ -> {:ok, %{status: 200, body: refs(Enum.map(1..6, &"1.0.#{&1}"))}} end)

    expect(Req, :get, 5, fn url, _ ->
      assert String.contains?(url, "/releases/tags/")
      {:ok, %{status: 404}}
    end)

    assert %{state: :unavailable, stable: nil} = ReleaseStatus.get(:cli, opts)
  end

  test "rate limits on a candidate never fall back to a bogus lower version", %{opts: opts} do
    mock_github([release("1.0.0"), release("2.0.0")])
    expect(Req, :get, fn _, _ -> {:ok, %{status: 200, body: refs(["1.0.0", "2.0.0"])}} end)

    expect(Req, :get, fn url, _ ->
      assert String.ends_with?(url, "/releases/tags/2.0.0")
      {:ok, %{status: 403}}
    end)

    assert %{state: :unavailable, stable: nil} = ReleaseStatus.get(:cli, opts)
  end

  test "restricted day fields follow POSIX OR semantics", %{opts: opts} do
    mock_github([release("1.0.0")], yaml: "on: {schedule: [{cron: '0 6 1 * 1'}]}")

    assert ReleaseStatus.get(:cli, opts).schedule == [
             ~U[2027-01-01 06:00:00Z],
             ~U[2027-01-04 06:00:00Z],
             ~U[2027-01-11 06:00:00Z],
             ~U[2027-01-18 06:00:00Z]
           ]
  end

  test "missing stable release and malformed upstream data are unavailable", %{opts: opts} do
    mock_github([release("1.0.0-canary.1")])
    assert ReleaseStatus.get(:cli, opts).state == :unavailable

    stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: %{}}} end)
    assert ReleaseStatus.get(:cli, Keyword.put(opts, :now, DateTime.add(@now, 31))).state == :unavailable
  end

  defp mock_github(releases, opts \\ []) do
    stub(Req, :get, fn url, _ ->
      cond do
        String.contains?(url, "/git/matching-refs/tags/") ->
          {:ok, %{status: 200, body: refs(Enum.map(releases, & &1["tag_name"]))}}

        String.contains?(url, "/releases/tags/") ->
          tag = url |> String.split("/tags/") |> List.last() |> URI.decode()
          {:ok, %{status: 200, body: Enum.find(releases, &(&1["tag_name"] == tag))}}

        String.contains?(url, "/releases?") ->
          page =
            url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()

          pages = Keyword.get(opts, :history_pages, [%{status: 200, body: releases}])
          {:ok, Enum.fetch!(pages, page - 1)}

        String.contains?(url, "/contents/") ->
          {:ok, %{status: 200, body: Keyword.get(opts, :yaml, @yaml)}}

        String.contains?(url, "/runs?") ->
          {:ok, %{status: 200, body: %{"workflow_runs" => Keyword.get(opts, :runs, [@run])}}}
      end
    end)
  end

  defp refs(tags), do: Enum.map(tags, &%{"ref" => "refs/tags/#{&1}"})

  defp release(tag, overrides \\ %{}) do
    Map.merge(
      %{
        "tag_name" => tag,
        "draft" => false,
        "prerelease" => String.contains?(tag, "-"),
        "published_at" => "2026-12-20T12:00:00Z",
        "html_url" => "https://github.com/tuist/tuist/releases/tag/#{tag}"
      },
      overrides
    )
  end
end
