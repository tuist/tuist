defmodule Tuist.QA.LaunchArgumentsSelectionTest do
  use TuistTestSupport.Cases.DataCase

  alias LangChain.Chains.LLMChain
  alias Tuist.Accounts.Account
  alias Tuist.QA
  alias Tuist.QA.LaunchArgumentsGroup
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "test/1 with launch arguments" do
    setup do
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # Create launch argument groups
      {:ok, login_group} =
        Repo.insert(
          LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, %{
            project_id: project.id,
            name: "login-credentials",
            description: "Skip login with prefilled credentials",
            value: "--email hello@tuist.dev --password 123456"
          })
        )

      {:ok, debug_group} =
        Repo.insert(
          LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, %{
            project_id: project.id,
            name: "debug-mode",
            description: "Enable debug logging",
            value: "--debug --verbose"
          })
        )

      preview = AppBuildsFixtures.preview_fixture(project: project, account: account)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      {:ok, project: project, app_build: app_build, login_group: login_group, debug_group: debug_group}
    end

    test "includes launch arguments when prompt matches group", %{app_build: app_build} do
      Mimic.expect(Tuist.Environment, :anthropic_api_key, fn -> "test-key" end)
      Mimic.expect(Tuist.Environment, :openai_api_key, fn -> nil end)
      Mimic.expect(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.io" end)
      Mimic.expect(Tuist.Environment, :namespace_enabled?, fn -> false end)

      # Mock LangChain to return expected launch arguments
      Mimic.expect(LLMChain, :new!, fn _opts -> %LLMChain{} end)
      Mimic.expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      Mimic.expect(LLMChain, :run, fn _chain ->
        {:ok, %{last_message: %{content: "--email hello@tuist.dev --password 123456"}}}
      end)

      # Mock the runner agent
      Mimic.expect(Runner.QA.Agent, :test, fn attrs, _opts ->
        assert attrs.launch_arguments == "--email hello@tuist.dev --password 123456"
        :ok
      end)

      # Mock storage URL generation
      Mimic.expect(Tuist.Storage, :generate_download_url, fn _key -> "https://example.com/download" end)

      params = %{
        app_build: app_build,
        prompt: "Test the app, skip login"
      }

      assert {:ok, _} = QA.test(params)
    end

    test "uses fallback matching when LLM fails", %{app_build: app_build} do
      Mimic.expect(Tuist.Environment, :anthropic_api_key, fn -> "test-key" end)
      Mimic.expect(Tuist.Environment, :openai_api_key, fn -> nil end)
      Mimic.expect(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.io" end)
      Mimic.expect(Tuist.Environment, :namespace_enabled?, fn -> false end)

      # Mock LangChain to fail
      Mimic.expect(LLMChain, :new!, fn _opts -> %LLMChain{} end)
      Mimic.expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      Mimic.expect(LLMChain, :run, fn _chain ->
        {:error, "LLM error"}
      end)

      # Mock the runner agent - should use fallback matching
      Mimic.expect(Runner.QA.Agent, :test, fn attrs, _opts ->
        # Fallback should match "debug" in the prompt to debug-mode group
        assert attrs.launch_arguments == "--debug --verbose"
        :ok
      end)

      # Mock storage URL generation
      Mimic.expect(Tuist.Storage, :generate_download_url, fn _key -> "https://example.com/download" end)

      params = %{
        app_build: app_build,
        prompt: "Run tests in debug mode"
      }

      assert {:ok, _} = QA.test(params)
    end

    test "sends empty string when no groups match", %{app_build: app_build} do
      Mimic.expect(Tuist.Environment, :anthropic_api_key, fn -> "test-key" end)
      Mimic.expect(Tuist.Environment, :openai_api_key, fn -> nil end)
      Mimic.expect(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.io" end)
      Mimic.expect(Tuist.Environment, :namespace_enabled?, fn -> false end)

      # Mock LangChain to return empty
      Mimic.expect(LLMChain, :new!, fn _opts -> %LLMChain{} end)
      Mimic.expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      Mimic.expect(LLMChain, :run, fn _chain ->
        {:ok, %{last_message: %{content: ""}}}
      end)

      # Mock the runner agent
      Mimic.expect(Runner.QA.Agent, :test, fn attrs, _opts ->
        assert attrs.launch_arguments == ""
        :ok
      end)

      # Mock storage URL generation
      Mimic.expect(Tuist.Storage, :generate_download_url, fn _key -> "https://example.com/download" end)

      params = %{
        app_build: app_build,
        prompt: "Test navigation"
      }

      assert {:ok, _} = QA.test(params)
    end
  end
end
