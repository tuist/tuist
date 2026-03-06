defmodule Cache.KeyValue.PromExPlugin do
  @moduledoc """
  PromEx plugin for KeyValue endpoints.

  Exposes counters and distributions for GET/PUT operations, SQLite health metrics,
  and eviction telemetry.
  """
  use PromEx.Plugin

  alias Cache.Repo

  @entry_buckets [1, 2, 4, 8, 16, 32, 64, 128]
  @duration_buckets [10, 50, 100, 250, 500, 1000, 2500, 5000]

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_kv_event_metrics, [
      # GETs
      counter([:cache, :kv, :get, :total],
        event_name: [:cache, :kv, :get, :request],
        description: "Total KeyValue GET requests."
      ),
      counter([:cache, :kv, :get, :hit, :total],
        event_name: [:cache, :kv, :get, :hit],
        measurement: :count,
        description: "KeyValue GET hits."
      ),
      counter([:cache, :kv, :get, :miss, :total],
        event_name: [:cache, :kv, :get, :miss],
        description: "KeyValue GET misses."
      ),
      sum([:cache, :kv, :get, :bytes],
        event_name: [:cache, :kv, :get, :hit],
        measurement: :bytes,
        description: "Total bytes returned by KeyValue GET."
      ),
      distribution([:cache, :kv, :get, :payload_size, :bytes],
        event_name: [:cache, :kv, :get, :hit],
        measurement: :bytes,
        unit: :byte,
        description: "Distribution of KeyValue GET payload sizes.",
        reporter_options: [buckets: exponential!(256, 2, 18)]
      ),

      # PUTs
      counter([:cache, :kv, :put, :total],
        event_name: [:cache, :kv, :put, :request],
        description: "Total KeyValue PUT requests."
      ),
      counter([:cache, :kv, :put, :success, :total],
        event_name: [:cache, :kv, :put, :success],
        description: "Successful KeyValue PUT operations."
      ),
      counter([:cache, :kv, :put, :errors, :total],
        event_name: [:cache, :kv, :put, :error],
        description: "KeyValue PUT errors.",
        tags: [:reason],
        tag_values: fn md -> %{reason: to_string(Map.get(md, :reason, :unknown))} end
      ),
      sum([:cache, :kv, :put, :entries],
        event_name: [:cache, :kv, :put, :success],
        measurement: :entries_count,
        description: "Total entries stored via KeyValue PUT."
      ),
      distribution([:cache, :kv, :put, :entries, :distribution],
        event_name: [:cache, :kv, :put, :success],
        measurement: :entries_count,
        description: "Distribution of number of entries per KeyValue PUT.",
        reporter_options: [buckets: @entry_buckets]
      ),

      # Eviction
      counter([:cache, :kv, :eviction, :entries, :total],
        event_name: [:cache, :kv, :eviction, :complete],
        measurement: :entries_deleted,
        description: "Total KeyValue entries evicted."
      ),
      distribution([:cache, :kv, :eviction, :duration, :seconds],
        event_name: [:cache, :kv, :eviction, :complete],
        measurement: :duration_ms,
        unit: {:native, :millisecond},
        description: "KeyValue eviction operation duration.",
        tags: [:trigger, :status],
        tag_values: fn metadata ->
          %{
            trigger: to_string(Map.get(metadata, :trigger, :unknown)),
            status: to_string(Map.get(metadata, :status, :unknown))
          }
        end,
        reporter_options: [buckets: @duration_buckets]
      )
    ])
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 60_000)

    Polling.build(
      :cache_kv_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_sqlite_metrics, []},
      [
        last_value([:cache, :kv, :db, :file_size, :bytes],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :db_file_size,
          description: "KeyValue SQLite database file size."
        ),
        last_value([:cache, :kv, :wal, :file_size, :bytes],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :wal_file_size,
          description: "KeyValue SQLite WAL file size."
        ),
        last_value([:cache, :kv, :sqlite, :page_count],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :page_count,
          description: "KeyValue SQLite total page count."
        ),
        last_value([:cache, :kv, :sqlite, :freelist_pages],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :freelist_pages,
          description: "KeyValue SQLite freelist page count."
        ),
        last_value([:cache, :kv, :sqlite, :page_size, :bytes],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :page_size,
          description: "KeyValue SQLite page size."
        ),
        last_value([:cache, :kv, :sqlite, :in_use, :bytes],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :in_use_bytes,
          description: "KeyValue SQLite in-use bytes (page_count - freelist_count) * page_size."
        ),
        last_value([:cache, :kv, :sqlite, :reclaimable, :bytes],
          event_name: [:cache, :prom_ex, :kv, :sqlite],
          measurement: :reclaimable_bytes,
          description: "KeyValue SQLite reclaimable bytes (freelist_count * page_size)."
        )
      ]
    )
  end

  def execute_sqlite_metrics do
    db_path = Application.get_env(:cache, Repo)[:database] || "repo.sqlite"
    wal_path = "#{db_path}-wal"

    db_file_size = file_size(db_path)
    wal_file_size = file_size(wal_path)

    case fetch_pragma_metrics() do
      {:ok, pragma_metrics} ->
        page_count = pragma_metrics.page_count
        freelist_pages = pragma_metrics.freelist_pages
        page_size = pragma_metrics.page_size

        in_use_bytes = max(page_count - freelist_pages, 0) * page_size
        reclaimable_bytes = freelist_pages * page_size

        :telemetry.execute(
          [:cache, :prom_ex, :kv, :sqlite],
          %{
            db_file_size: db_file_size,
            wal_file_size: wal_file_size,
            page_count: page_count,
            freelist_pages: freelist_pages,
            page_size: page_size,
            in_use_bytes: in_use_bytes,
            reclaimable_bytes: reclaimable_bytes
          },
          %{}
        )

      :error ->
        :ok
    end
  end

  defp fetch_pragma_metrics do
    with {:ok, page_count} <- fetch_pragma_value("PRAGMA page_count"),
         {:ok, freelist_pages} <- fetch_pragma_value("PRAGMA freelist_count"),
         {:ok, page_size} <- fetch_pragma_value("PRAGMA page_size") do
      {:ok, %{page_count: page_count, freelist_pages: freelist_pages, page_size: page_size}}
    end
  rescue
    _ -> :error
  end

  defp fetch_pragma_value(query) do
    case Repo.query(query) do
      {:ok, %{rows: [[value]]}} -> {:ok, value}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end
end
