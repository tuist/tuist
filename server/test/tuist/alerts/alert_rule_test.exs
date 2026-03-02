defmodule Tuist.Alerts.AlertRuleTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Alerts.AlertRule
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without project_id" do
      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "is invalid without category" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).category
    end

    test "is invalid without metric" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).metric
    end

    test "is invalid without deviation_percentage" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).deviation_percentage
    end

    test "is invalid without rolling_window_size" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).rolling_window_size
    end

    test "is invalid without slack_channel_id" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).slack_channel_id
    end

    test "is invalid without slack_channel_name" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).slack_channel_name
    end

    test "is invalid with deviation_percentage <= 0" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "must be greater than 0" in errors_on(changeset).deviation_percentage
    end

    test "is invalid with rolling_window_size <= 0" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 0,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "must be greater than 0" in errors_on(changeset).rolling_window_size
    end

    test "accepts all valid categories" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for category <- [:build_run_duration, :test_run_duration, :cache_hit_rate] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: category,
            metric: :p90,
            deviation_percentage: 20.0,
            rolling_window_size: 100,
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid?, "Expected category #{category} to be valid"
      end
    end

    test "accepts all valid metrics" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for metric <- [:p50, :p90, :p99, :average] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: :build_run_duration,
            metric: metric,
            deviation_percentage: 20.0,
            rolling_window_size: 100,
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid?, "Expected metric #{metric} to be valid"
      end
    end

    test "validates foreign key constraint on project_id" do
      # Given
      non_existent_project_id = 999_999

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: non_existent_project_id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).project_id
    end

    test "is invalid when bundle_size category has a non-bundle-size metric" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for metric <- [:p50, :p90, :p99, :average] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: :bundle_size,
            metric: metric,
            deviation_percentage: 20.0,
            git_branch: "main",
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid? == false,
               "Expected metric #{metric} to be invalid for bundle_size category"

        assert "is invalid for bundle_size category" in errors_on(changeset).metric
      end
    end

    test "is valid when bundle_size category has install_size or download_size metric" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for metric <- [:install_size, :download_size] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: :bundle_size,
            metric: metric,
            deviation_percentage: 20.0,
            git_branch: "main",
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid?, "Expected metric #{metric} to be valid for bundle_size category"
      end
    end

    test "is invalid when non-bundle-size category has a bundle-size metric" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for category <- [:build_run_duration, :test_run_duration, :cache_hit_rate],
          metric <- [:install_size, :download_size] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: category,
            metric: metric,
            deviation_percentage: 20.0,
            rolling_window_size: 100,
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid? == false,
               "Expected metric #{metric} to be invalid for #{category} category"

        assert "is invalid for #{category} category" in errors_on(changeset).metric
      end
    end

    test "accepts scheme for build_run_duration category" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          scheme: "MyApp",
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :scheme) == "MyApp"
    end

    test "accepts bundle_name for bundle_size category" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :bundle_size,
          metric: :install_size,
          deviation_percentage: 20.0,
          git_branch: "main",
          bundle_name: "MyApp",
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :bundle_name) == "MyApp"
    end

    test "defaults name to Untitled" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid?
      {:ok, alert_rule} = Repo.insert(changeset)
      assert alert_rule.name == "Untitled"
    end

    test "defaults environment to :any" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid?
      {:ok, alert_rule} = Repo.insert(changeset)
      assert alert_rule.environment == :any
    end

    test "accepts all valid environment values as atoms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for env <- [:any, :ci, :local] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: :build_run_duration,
            metric: :p90,
            deviation_percentage: 20.0,
            rolling_window_size: 100,
            environment: env,
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid?, "Expected environment #{env} to be valid"
        assert Ecto.Changeset.get_field(changeset, :environment) == env
      end
    end

    test "accepts environment as a string (cast from form)" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for {str, atom} <- [{"any", :any}, {"ci", :ci}, {"local", :local}] do
        # When
        changeset =
          AlertRule.changeset(%AlertRule{}, %{
            project_id: project.id,
            name: "Test Alert",
            category: :build_run_duration,
            metric: :p90,
            deviation_percentage: 20.0,
            rolling_window_size: 100,
            environment: str,
            slack_channel_id: "C123456",
            slack_channel_name: "test-channel"
          })

        # Then
        assert changeset.valid?, "Expected string environment \"#{str}\" to be cast successfully"
        assert Ecto.Changeset.get_field(changeset, :environment) == atom
      end
    end

    test "is invalid with an unknown environment value" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "Test Alert",
          category: :build_run_duration,
          metric: :p90,
          deviation_percentage: 20.0,
          rolling_window_size: 100,
          environment: "unknown",
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel"
        })

      # Then
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).environment
    end
  end
end
