defmodule Tuist.Runners.CacheVolumes.QueryTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Query
  alias Tuist.Runners.CacheVolumes.Schemas, as: RunnerVolumes
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()
    other = AccountsFixtures.account_fixture()

    uses =
      for key <- ["alpha", "bravo", "charlie"] do
        job = %{
          account_id: account.id,
          workflow_job_id: System.unique_integer([:positive]),
          workflow_run_id: 321,
          run_attempt: 1,
          repository: "org/repo"
        }

        {:ok, use} =
          CacheVolumes.allocate_for_job(job, %{repository_id: 123, trusted: true, same_repository: true}, %{
            pod_name: key,
            pod_uid: key,
            node_name: "node",
            key: key,
            architecture: "amd64",
            uid: 1001
          })

        Repo.get!(Usage, use.id)
      end

    %{account: account, other: other, uses: uses}
  end

  test "sorts before paginating and counts the filtered inventory", %{account: account} do
    assert {:ok, %{volumes: [%{key: "bravo"} = volume], pagination_metadata: meta}} =
             Query.run(:list, account.id, %{"page" => 2, "page_size" => 1, "sort_by" => "volume"})

    assert meta == %{
             current_page: 2,
             page_size: 1,
             total_count: 3,
             total_pages: 3,
             has_next_page: true,
             has_previous_page: true
           }

    assert_schema(:show, volume)
    assert volume.used_bytes == 0
    assert volume.capacity_bytes == nil
    refute Map.has_key?(volume, :scope)
    refute Map.has_key?(volume, :pod_name)

    assert {:ok, %{volumes: [%{key: "charlie"}], pagination_metadata: %{total_count: 1}}} =
             Query.run(:list, account.id, %{"name" => "charlie", "repository" => "org/repo"})

    for args <- [
          %{"name" => "char"},
          %{"repository" => "org"},
          %{"name" => "charlie", "repository" => "other/repo"},
          %{"name" => "%"}
        ] do
      assert {:ok, %{volumes: [], pagination_metadata: %{total_count: 0}}} = Query.run(:list, account.id, args)
    end

    assert {:ok, %{volumes: volumes, pagination_metadata: %{total_count: 3}}} =
             Query.run(:list, account.id, %{"repository" => "org/repo"})

    assert length(volumes) == 3

    assert {:ok, %{volumes: [], pagination_metadata: %{has_next_page: false}}} =
             Query.run(:list, account.id, %{"page" => 4, "page_size" => 1})
  end

  test "rejects malformed pagination, sorts and volume identifiers", %{account: account} do
    for args <- [
          %{"page" => 0},
          %{"page_size" => 101},
          %{"name" => ""},
          %{"repository" => 42},
          %{"sort_by" => "scope"},
          %{"sort_order" => "up"}
        ] do
      assert {:error, :invalid_parameters} = Query.run(:list, account.id, args)
    end

    assert {:error, :invalid_parameters} = Query.run(:show, account.id, %{"volume_id" => "not-a-uuid"})
  end

  test "scopes reads, analytics and clearing to the authorized account", %{
    other: other,
    account: account,
    uses: [use | _]
  } do
    for action <- [:show, :jobs, :analytics, :clear] do
      assert {:error, :not_found} = Query.run(action, other.id, %{"volume_id" => use.volume_id})
    end

    assert {:ok, %{volumes: []}} = Query.run(:list, other.id, %{})
    before = CacheVolumes.get(account.id, use.volume_id)
    assert {:ok, %{cleared: true}} = Query.run(:clear, account.id, %{"volume_id" => use.volume_id})
    after_clear = CacheVolumes.get(account.id, use.volume_id)
    assert after_clear.generation == before.generation + 1
    assert after_clear.deleted_at
  end

  test "exposes saved lifecycle separately from hit outcomes and paginates history", %{account: account, uses: [use | _]} do
    mounted = ~U[2026-01-02 12:00:00.123456Z]
    use |> Ecto.Changeset.change(status: "published", warm: false, attached_at: mounted) |> Repo.update!()

    assert {:ok, %{jobs: [job], pagination_metadata: %{total_count: 1}}} =
             Query.run(:jobs, account.id, %{"volume_id" => use.volume_id, "page_size" => 1})

    assert job.cache_status == "saved"
    assert job.cache_status_description =~ "future job runs"
    assert job.cache_hit == false
    assert job.mounted_at == "2026-01-02T12:00:00Z"

    assert_schema(:jobs, %{
      jobs: [job],
      pagination_metadata: %{
        current_page: 1,
        page_size: 1,
        total_count: 1,
        total_pages: 1,
        has_next_page: false,
        has_previous_page: false
      }
    })

    assert job.capacity_bytes == nil
    refute Map.has_key?(job, :node_name)

    assert {:ok, %{jobs: []}} =
             Query.run(:jobs, account.id, %{"volume_id" => use.volume_id, "page_size" => 1, "page" => 2})
  end

  test "analytics compares known outcomes in equal periods and preserves empty buckets", %{
    account: account,
    uses: [first, second, third]
  } do
    for {use, warm, time} <- [
          {first, false, ~U[2026-01-01 12:00:00.000000Z]},
          {second, true, ~U[2026-01-02 12:00:00.000000Z]},
          {third, nil, ~U[2026-01-02 13:00:00.000000Z]}
        ] do
      Repo.update!(Ecto.Changeset.change(use, status: "attached", warm: warm, attached_at: time))
    end

    assert {:ok, data} =
             Query.run(:analytics, account.id, %{"start" => "2026-01-02T00:00:00Z", "end" => "2026-01-03T00:00:00Z"})

    assert_schema(:analytics, data)
    assert data.activity.job_runs == 2
    assert data.activity.hit_rate == 100.0
    assert data.previous_activity.hit_rate == 0.0
    assert data.trends.hit_rate_percentage_points == 100.0
    assert Enum.any?(data.activity.points, &(&1.job_runs == 0 and is_nil(&1.hit_rate)))
    assert Enum.all?(data.storage, &is_binary(&1.at))
  end

  test "measured volumes serialize integer bytes and whole-second timestamps", %{account: account, uses: [use | _]} do
    mounted = ~U[2026-01-02 12:00:00.123456Z]
    Repo.update!(Ecto.Changeset.change(use, size_bytes: 1024, capacity_bytes: 20_000_000_000, attached_at: mounted))
    Volume |> Repo.get!(use.volume_id) |> Ecto.Changeset.change(last_used_at: mounted) |> Repo.update!()

    assert {:ok, volume} = Query.run(:show, account.id, %{"volume_id" => use.volume_id})
    assert_schema(:show, volume)
    assert volume.used_bytes === 1024
    assert volume.capacity_bytes === 20_000_000_000
    assert volume.last_used_at == "2026-01-02T12:00:00Z"

    assert {:ok, list} = Query.run(:list, account.id, %{"name" => "alpha"})
    assert_schema(:list, list)
    assert list.volumes == [volume]
  end

  test "analytics serializes fractional and default periods at whole-second precision", %{account: account} do
    for params <- [%{}, %{"start" => "2026-01-02T00:00:00.123456Z", "end" => "2026-01-03T00:00:00.654321Z"}] do
      assert {:ok, data} = Query.run(:analytics, account.id, params)
      assert_schema(:analytics, data)

      timestamps =
        [data.period.start, data.period.end] ++ Enum.map(data.storage, & &1.at) ++ Enum.map(data.activity.points, & &1.at)

      assert Enum.all?(timestamps, &Regex.match?(~r/T\d{2}:\d{2}:\d{2}Z$/, &1))
    end
  end

  defp assert_schema(action, data) do
    schema = action |> RunnerVolumes.response() |> RunnerVolumes.json_schema() |> ExJsonSchema.Schema.resolve()
    assert :ok = ExJsonSchema.Validator.validate(schema, data |> JSON.encode!() |> JSON.decode!())
  end

  test "rejects reversed, excessive, malformed and future ranges", %{account: account} do
    for args <- [
          %{"start" => "2026-01-03T00:00:00Z", "end" => "2026-01-02T00:00:00Z"},
          %{"start" => "2025-01-01T00:00:00Z", "end" => "2026-01-02T00:00:00Z"},
          %{"start" => "yesterday"},
          %{"end" => "2999-01-01T00:00:00Z"}
        ] do
      assert {:error, :invalid_parameters} = Query.run(:analytics, account.id, args)
    end
  end
end
