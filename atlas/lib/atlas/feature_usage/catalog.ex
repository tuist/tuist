defmodule Atlas.FeatureUsage.Catalog do
  @moduledoc """
  The catalog of Tuist product features whose usage we track per account.

  Each feature has a `slug`, a display `label`, and one or more `sources` in the
  Tuist analytics databases. Usage across a feature's sources is summed (and the
  most recent "last used" is kept), so a single feature can span more than one
  table — e.g. "Build insights" combines Apple/Xcode (`build_runs`) and
  Android/Gradle (`gradle_builds`).

  A feature also has a `kind`, defaulting to `:events`:

    * `:events` — usage is a stream of events in ClickHouse, counted over the
      24h / 7d windows.
    * `:configuration` — usage is a *state* in Postgres rather than a stream:
      the account either has the feature set up in its projects or it does not.
      "Automations" is one: an account can run automations for months without
      any of them firing, so counting firings would report it as unused. For
      these, `events_last_7d` holds the number of enabled rows (which is what
      makes the feature "active"), `events_last_24h` the total number of rows
      including disabled ones, and `last_used_at` the last time one changed.

  Each source declares:

    * `:store` — `:clickhouse` (the default), `:postgres`, or `:loki`.

    * `:table` — the ClickHouse table.
    * `:time_expr` — the event-timestamp column used both to bucket usage into
      the 24h / 7d windows and to bound the scan (for `:configuration` sources,
      the column holding when the row last changed). Prefer the table's sort-key
      time column so the scan stays scoped to the account's rows: `command_events`
      is sorted by `(project_id, name, ran_at)`, so it must bound on `ran_at`
      (not `created_at`), otherwise ClickHouse scans every project's rows and
      trips the ops endpoint's limit for high-volume accounts.
    * `:attribution` — `:account_id` when the table carries the Postgres account
      id directly, or `:project_ids` when usage is attributed through the
      account's projects (resolved via the Postgres proxy first).
    * `:account_column` — the column holding the account id (for `:account_id`).
    * `:predicate` — an optional extra `WHERE` fragment narrowing rows to the
      feature (e.g. cache hits present); for `:configuration` sources it is what
      makes a row count as in use (e.g. the automation being enabled).
    * `:total_predicate` — an optional predicate for the total configuration
      count when it differs from the in-use predicate.

  Loki sources are account-handle scoped log queries. They are used where the
  authoritative product signal is operational telemetry rather than a database
  row, such as Model Context Protocol requests.

  Add a feature by appending an entry here; the collector and the read/alert
  surfaces pick it up automatically. `registry_download_events` is intentionally
  excluded because it carries no account or project column.
  """

  @features [
    %{
      slug: "cache",
      label: "Cache",
      sources: [
        %{
          table: "command_events",
          time_expr: "ran_at",
          attribution: :project_ids,
          predicate: "length(remote_cache_target_hits) > 0"
        },
        %{table: "module_cache_outputs", time_expr: "inserted_at", attribution: :project_ids, predicate: nil}
      ]
    },
    %{
      slug: "selective_testing",
      label: "Selective testing",
      sources: [
        %{
          table: "command_events",
          time_expr: "ran_at",
          attribution: :project_ids,
          predicate: "length(test_targets) > 0"
        }
      ]
    },
    %{
      slug: "previews",
      label: "Previews",
      sources: [
        %{
          table: "command_events",
          time_expr: "ran_at",
          attribution: :project_ids,
          predicate: "preview_id IS NOT NULL"
        }
      ]
    },
    %{
      slug: "generate",
      label: "Project generation",
      sources: [
        %{
          table: "command_events",
          time_expr: "ran_at",
          attribution: :project_ids,
          predicate: "name = 'generate'"
        }
      ]
    },
    %{
      slug: "sharding",
      label: "Test sharding",
      sources: [
        %{table: "shard_plans", time_expr: "inserted_at", attribution: :project_ids, predicate: nil}
      ]
    },
    %{
      slug: "test_analytics",
      label: "Test insights",
      sources: [
        %{
          table: "test_runs",
          time_expr: "ran_at",
          attribution: :account_id,
          account_column: "account_id",
          predicate: nil
        }
      ]
    },
    %{
      slug: "builds",
      label: "Build insights",
      sources: [
        %{
          table: "build_runs",
          time_expr: "inserted_at",
          attribution: :account_id,
          account_column: "account_id",
          predicate: nil
        },
        %{
          table: "gradle_builds",
          time_expr: "inserted_at",
          attribution: :account_id,
          account_column: "account_id",
          predicate: nil
        }
      ]
    },
    %{
      slug: "bundles",
      label: "Bundle insights",
      sources: [
        %{
          table: "bundles",
          time_expr: "inserted_at",
          attribution: :account_id,
          account_column: "uploaded_by_account_id",
          predicate: nil
        }
      ]
    },
    %{
      slug: "runners",
      label: "CI runners",
      sources: [
        %{
          table: "runner_jobs",
          time_expr: "enqueued_at",
          attribution: :account_id,
          account_column: "account_id",
          predicate: nil
        }
      ]
    },
    %{
      slug: "automations",
      label: "Automations",
      kind: :configuration,
      sources: [
        %{
          store: :postgres,
          table: "automation_alerts",
          time_expr: "updated_at",
          attribution: :project_ids,
          predicate: "enabled"
        }
      ]
    },
    %{
      slug: "single_sign_on",
      label: "Single sign-on",
      kind: :configuration,
      scope: :account,
      sources: [
        %{
          store: :postgres,
          table: "organizations o INNER JOIN accounts a ON a.organization_id = o.id",
          time_expr: "o.updated_at",
          attribution: :account_id,
          account_column: "a.id",
          predicate: "o.sso_provider IS NOT NULL",
          total_predicate: "o.sso_provider IS NOT NULL"
        }
      ]
    },
    %{
      slug: "model_context_protocol",
      label: "Model Context Protocol server",
      sources: [
        %{store: :loki, attribution: :account_handle}
      ]
    }
  ]

  # Continuous-integration providers are detected from build and test telemetry.
  # They are rendered as an integration badge strip, rather than stat widgets,
  # so an account using more than one provider remains easy to scan.
  @continuous_integration_providers (for provider <- [
                                           %{
                                             slug: "continuous_integration_github",
                                             label: "GitHub",
                                             provider: "github"
                                           },
                                           %{
                                             slug: "continuous_integration_gitlab",
                                             label: "GitLab",
                                             provider: "gitlab"
                                           },
                                           %{
                                             slug: "continuous_integration_bitrise",
                                             label: "Bitrise",
                                             provider: "bitrise"
                                           },
                                           %{
                                             slug: "continuous_integration_circleci",
                                             label: "CircleCI",
                                             provider: "circleci"
                                           },
                                           %{
                                             slug: "continuous_integration_buildkite",
                                             label: "Buildkite",
                                             provider: "buildkite"
                                           },
                                           %{
                                             slug: "continuous_integration_codemagic",
                                             label: "Codemagic",
                                             provider: "codemagic"
                                           }
                                         ] do
                                       %{
                                         slug: provider.slug,
                                         label: provider.label,
                                         sources: [
                                           %{
                                             table: "build_runs",
                                             time_expr: "inserted_at",
                                             attribution: :account_id,
                                             account_column: "account_id",
                                             predicate: "is_ci AND ci_provider = '#{provider.provider}'"
                                           },
                                           %{
                                             table: "test_runs",
                                             time_expr: "ran_at",
                                             attribution: :account_id,
                                             account_column: "account_id",
                                             predicate: "is_ci AND ci_provider = '#{provider.provider}'"
                                           }
                                         ]
                                       }
                                     end)

  # Build systems / platforms an account integrates Tuist with. These are
  # detected and stored through the same pipeline as features, but rendered as a
  # badge strip (used vs not) rather than stat widgets, and they do not raise
  # churn alerts. Add new systems (Bazel, SPM, ...) here once a signal exists.
  @build_systems [
    %{
      slug: "system_xcode",
      label: "Xcode",
      sources: [
        %{
          table: "command_events",
          time_expr: "ran_at",
          attribution: :project_ids,
          predicate: nil
        }
      ]
    },
    %{
      slug: "system_gradle",
      label: "Gradle",
      sources: [
        %{
          table: "gradle_builds",
          time_expr: "inserted_at",
          attribution: :account_id,
          account_column: "account_id",
          predicate: nil
        }
      ]
    }
  ]

  @doc "Feature definitions rendered as stat widgets, in display order."
  def all, do: @features

  @doc "Build-system / platform definitions rendered as a badge strip."
  def build_systems, do: @build_systems

  @doc "Continuous-integration provider definitions rendered as a badge strip."
  def continuous_integration_providers, do: @continuous_integration_providers

  @doc "Everything collected and stored per account."
  def tracked, do: @features ++ @build_systems ++ @continuous_integration_providers

  @doc "Feature slugs (widgets only)."
  def slugs, do: Enum.map(@features, & &1.slug)

  @doc "All stored slugs (features, build systems, and providers); the set a snapshot may use."
  def all_slugs, do: Enum.map(tracked(), & &1.slug)

  @doc "Fetch a feature or build-system definition by slug, or `nil`."
  def fetch(slug) when is_binary(slug), do: Enum.find(tracked(), &(&1.slug == slug))

  @doc """
  How a feature is measured: `:events` (a stream of ClickHouse events) or
  `:configuration` (a state in Postgres). See the moduledoc.
  """
  def kind(%{} = feature), do: Map.get(feature, :kind, :events)
  def kind(slug) when is_binary(slug), do: slug |> fetch() |> kind_of_definition()

  defp kind_of_definition(nil), do: :events
  defp kind_of_definition(feature), do: kind(feature)

  @doc "The resource scope a configuration feature applies to, when applicable."
  def scope(%{} = feature), do: Map.get(feature, :scope)
  def scope(slug) when is_binary(slug), do: slug |> fetch() |> scope_of_definition()

  defp scope_of_definition(nil), do: nil
  defp scope_of_definition(feature), do: scope(feature)

  @doc "Human-readable label for a slug, falling back to the slug itself."
  def label(slug) when is_binary(slug) do
    case fetch(slug) do
      %{label: label} -> label
      nil -> slug
    end
  end
end
