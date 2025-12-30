defmodule TuistTestSupport.Fixtures.AccountsFixtures do
  @moduledoc false

  alias Tuist.Accounts

  def user_fixture(opts \\ []) do
    create_opts =
      [
        password: Keyword.get(opts, :password, valid_user_password()),
        confirmed_at: Keyword.get(opts, :confirmed_at, DateTime.utc_now()),
        created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
        customer_id: Keyword.get(opts, :customer_id, "#{TuistTestSupport.Utilities.unique_integer()}"),
        setup_billing: Keyword.get(opts, :setup_billing, false),
        current_month_remote_cache_hits_count: Keyword.get(opts, :current_month_remote_cache_hits_count, 0),
        current_month_remote_cache_hits_count_updated_at:
          Keyword.get(opts, :current_month_remote_cache_hits_count_updated_at)
      ]

    create_opts =
      if Keyword.has_key?(opts, :handle) do
        Keyword.put(create_opts, :handle, Keyword.get(opts, :handle))
      else
        create_opts
      end

    email = Keyword.get(opts, :email, unique_user_email())

    {:ok, user} =
      Accounts.create_user(email, create_opts)

    Tuist.Repo.preload(user, Keyword.get(opts, :preload, [:account]))
  end

  def organization_fixture(opts \\ []) do
    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer(6)}")
    creator = Keyword.get_lazy(opts, :creator, fn -> user_fixture() end)
    sso_provider = Keyword.get(opts, :sso_provider)
    sso_organization_id = Keyword.get(opts, :sso_organization_id)
    okta_client_id = Keyword.get(opts, :okta_client_id)
    okta_client_secret = Keyword.get(opts, :okta_client_secret)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())

    customer_id =
      Keyword.get(opts, :customer_id, "#{TuistTestSupport.Utilities.unique_integer()}")

    preload = Keyword.get(opts, :preload, [:account])
    setup_billing = Keyword.get(opts, :setup_billing, false)

    current_month_remote_cache_hits_count =
      Keyword.get(opts, :current_month_remote_cache_hits_count, 0)

    {:ok, organization} =
      Accounts.create_organization(%{name: name, creator: creator},
        sso_provider: sso_provider,
        sso_organization_id: sso_organization_id,
        okta_client_id: okta_client_id,
        okta_client_secret: okta_client_secret,
        created_at: created_at,
        customer_id: customer_id,
        setup_billing: setup_billing,
        current_month_remote_cache_hits_count: current_month_remote_cache_hits_count
      )

    Tuist.Repo.preload(organization, preload)
  end

  def unique_user_email, do: "#{TuistTestSupport.Utilities.unique_integer(6)}@tuist.io"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def extract_user_token(fun) do
    captured_email = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.html_body, "[TOKEN]")
    token
  end

  def account_fixture do
    user_fixture(preload: [:account]).account
  end

  def account_token_fixture(opts \\ []) do
    account =
      Keyword.get_lazy(opts, :account, fn -> user_fixture(preload: [:account]).account end)

    scopes = Keyword.get(opts, :scopes, ["project:cache:read"])
    name = Keyword.get(opts, :name, "token-#{TuistTestSupport.Utilities.unique_integer()}")
    all_projects = Keyword.get(opts, :all_projects, true)
    project_ids = Keyword.get(opts, :project_ids, [])

    {:ok, {account_token, _}} =
      Accounts.create_account_token(%{
        account: account,
        scopes: scopes,
        name: name,
        all_projects: all_projects,
        project_ids: project_ids
      })

    account_token
  end
end
