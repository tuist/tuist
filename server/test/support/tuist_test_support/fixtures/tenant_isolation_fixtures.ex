defmodule TuistTestSupport.Fixtures.TenantIsolationFixtures do
  @moduledoc false

  alias Tuist.Accounts
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  # Use only in sandboxed tests or a disposable local test database. The prefix
  # makes repeated sessions independent; identical project handles exercise the
  # account boundary rather than relying on globally distinct project names.
  def tenants_fixture(prefix, opts \\ []) do
    Map.new([:alpha, :beta], fn label ->
      name = "#{prefix}-#{label}"
      password = Keyword.get(opts, :password, AccountsFixtures.valid_user_password())

      users =
        Map.new([:admin, :user, :viewer], fn role ->
          user = AccountsFixtures.user_fixture(email: "#{name}-#{role}@example.invalid", password: password)
          {role, user}
        end)

      organization = AccountsFixtures.organization_fixture(name: name, creator: users.admin)
      :ok = Accounts.add_user_to_organization(users.user, organization, role: :user)
      :ok = Accounts.add_user_to_organization(users.viewer, organization, role: :viewer)
      project = ProjectsFixtures.project_fixture(account: organization.account, name: "ios-client", visibility: :private)
      sibling = ProjectsFixtures.project_fixture(account: organization.account, name: "sibling", visibility: :private)

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          uploaded_by_account: users.admin.account,
          name: "#{label}-app",
          install_size: if(label == :alpha, do: 1234, else: 9876),
          artifacts: [%{artifact_type: :file, path: "#{label}.txt", size: 17, shasum: "#{label}-checksum"}]
        )

      preview =
        AppBuildsFixtures.preview_fixture(project: project, display_name: "#{label}-preview", visibility: :private)

      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: users.admin.account.id,
          scheme: "#{label}-scheme",
          test_modules: [
            %{
              name: "#{label}Tests",
              status: "success",
              duration: 700,
              test_cases: [%{name: "#{label}Case", status: "success", duration: 300}]
            }
          ]
        )

      Test.Buffer.flush()

      {label,
       Map.merge(users, %{
         organization: organization,
         project: project,
         sibling: sibling,
         bundle: bundle,
         preview: preview,
         test_run: test_run
       })}
    end)
  end
end
