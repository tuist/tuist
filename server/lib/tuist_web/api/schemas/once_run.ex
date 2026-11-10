defmodule TuistWeb.API.Schemas.OnceRun do
  @moduledoc false

  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.PaginationMetadata

  def kind do
    %Schema{title: "OnceRunKind", type: :string, enum: ["build", "test", "generic"]}
  end

  def list do
    %Schema{
      title: "OnceRunList",
      type: :object,
      properties: %{runs: %Schema{type: :array, items: run()}, pagination_metadata: PaginationMetadata},
      required: [:runs, :pagination_metadata]
    }
  end

  def detail do
    run = run()

    %{
      run
      | title: "OnceRunDetail",
        properties:
          Map.merge(run.properties, %{
            once_version: nullable(:string),
            git_dirty: %Schema{type: :boolean},
            exit_status: %Schema{type: :integer, nullable: true},
            cancellation_reason: nullable(:string),
            actions: actions(),
            cache: detail_cache(),
            tests: tests()
          }),
        required: run.required ++ [:once_version, :git_dirty, :exit_status, :cancellation_reason, :actions, :tests]
    }
  end

  defp run do
    %Schema{
      title: "OnceRun",
      type: :object,
      properties: %{
        run_id: %Schema{type: :string, description: "The client-chosen run ID, unique within the project."},
        kind: kind(),
        command: %Schema{type: :string},
        status: %Schema{
          type: :string,
          enum: ["success", "failure", "in_progress"],
          description: "in_progress until the run is finalized; lost runs are failures."
        },
        duration_ms: %Schema{type: :integer},
        is_ci: %Schema{type: :boolean},
        git_rev: nullable(:string),
        git_branch: nullable(:string),
        host_class: nullable(:string),
        started_at: %Schema{type: :string, format: :"date-time", nullable: true},
        finished_at: %Schema{type: :string, format: :"date-time", nullable: true},
        cache: %Schema{
          title: "OnceRunCacheSummary",
          type: :object,
          properties: %{
            hit_rate: %Schema{
              type: :number,
              nullable: true,
              description: "Percentage of the run's actions served from the cache; null without actions."
            },
            download_bytes: %Schema{type: :integer},
            upload_bytes: %Schema{type: :integer}
          },
          required: [:hit_rate, :download_bytes, :upload_bytes]
        }
      },
      required: [
        :run_id,
        :kind,
        :command,
        :status,
        :duration_ms,
        :is_ci,
        :git_rev,
        :git_branch,
        :host_class,
        :started_at,
        :finished_at,
        :cache
      ]
    }
  end

  defp actions do
    %Schema{
      title: "OnceRunActions",
      type: :object,
      properties: %{
        total: %Schema{type: :integer},
        cached: %Schema{type: :integer},
        executed: %Schema{type: :integer},
        failed: %Schema{type: :integer}
      },
      required: [:total, :cached, :executed, :failed]
    }
  end

  defp detail_cache do
    %Schema{
      title: "OnceRunCache",
      type: :object,
      properties: %{
        hits: %Schema{type: :integer},
        misses: %Schema{type: :integer},
        total_lookups: %Schema{type: :integer},
        hit_rate: %Schema{type: :number, nullable: true, description: "Hits divided by lookups, as a percentage."},
        content_download_bytes: %Schema{type: :integer},
        content_upload_bytes: %Schema{type: :integer},
        content_saved_bytes: %Schema{type: :integer}
      },
      required: [
        :hits,
        :misses,
        :total_lookups,
        :hit_rate,
        :content_download_bytes,
        :content_upload_bytes,
        :content_saved_bytes
      ]
    }
  end

  defp tests do
    %Schema{
      title: "OnceRunTests",
      type: :object,
      nullable: true,
      description: "Test totals for test runs; null for other kinds.",
      properties: %{
        test_cases: %Schema{type: :integer},
        passed: %Schema{type: :integer},
        failed: %Schema{type: :integer},
        skipped: %Schema{type: :integer},
        test_suites: %Schema{type: :integer}
      },
      required: [:test_cases, :passed, :failed, :skipped, :test_suites]
    }
  end

  defp nullable(type), do: %Schema{type: type, nullable: true}
end
