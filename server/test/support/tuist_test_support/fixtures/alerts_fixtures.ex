defmodule TuistTestSupport.Fixtures.AlertsFixtures do
  @moduledoc false

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def alert_fixture(opts \\ []) do
    alert_rule =
      Keyword.get_lazy(opts, :alert_rule, fn ->
        alert_rule_fixture()
      end)

    %Alert{}
    |> Alert.changeset(%{
      alert_rule_id: Keyword.get(opts, :alert_rule_id, alert_rule.id),
      current_value: Keyword.get(opts, :current_value, 1200.0),
      previous_value: Keyword.get(opts, :previous_value, 1000.0),
      inserted_at: Keyword.get(opts, :inserted_at)
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end

  def alert_rule_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    category = Keyword.get(opts, :category, :build_run_duration)

    base_attrs = %{
      project_id: Keyword.get(opts, :project_id, project.id),
      name: Keyword.get(opts, :name, "Test Alert #{unique_id}"),
      category: category,
      deviation_percentage: Keyword.get(opts, :deviation_percentage, 20.0),
      environment: Keyword.get(opts, :environment, "any"),
      slack_channel_id: Keyword.get(opts, :slack_channel_id, "C#{unique_id}"),
      slack_channel_name: Keyword.get(opts, :slack_channel_name, "test-channel-#{unique_id}")
    }

    category_attrs =
      if category == :bundle_size do
        attrs = %{
          metric: Keyword.get(opts, :metric, :install_size),
          git_branch: Keyword.get(opts, :git_branch, "main")
        }

        case Keyword.get(opts, :bundle_name) do
          nil -> attrs
          bundle_name -> Map.put(attrs, :bundle_name, bundle_name)
        end
      else
        attrs = %{
          metric: Keyword.get(opts, :metric, :p90),
          rolling_window_size: Keyword.get(opts, :rolling_window_size, 100)
        }

        case Keyword.get(opts, :scheme) do
          nil -> attrs
          scheme -> Map.put(attrs, :scheme, scheme)
        end
      end

    %AlertRule{}
    |> AlertRule.changeset(Map.merge(base_attrs, category_attrs))
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
