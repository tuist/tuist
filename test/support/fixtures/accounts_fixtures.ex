defmodule Tuist.AccountsFixtures do
  @moduledoc false

  alias Tuist.Accounts
  alias Tuist.TestUtilities

  def user_fixture(opts \\ []) do
    email = Keyword.get(opts, :email, unique_user_email())
    password = Keyword.get(opts, :password, valid_user_password())
    confirmed_at = Keyword.get(opts, :confirmed_at, DateTime.utc_now())
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    preload = Keyword.get(opts, :preload, [])
    customer_id = Keyword.get(opts, :customer_id, "#{TestUtilities.unique_integer()}")
    setup_billing = Keyword.get(opts, :setup_billing, false)

    current_month_remote_cache_hits_count =
      Keyword.get(opts, :current_month_remote_cache_hits_count, 0)

    {:ok, user} =
      Accounts.create_user(email,
        password: password,
        confirmed_at: confirmed_at,
        created_at: created_at,
        customer_id: customer_id,
        setup_billing: setup_billing,
        current_month_remote_cache_hits_count: current_month_remote_cache_hits_count
      )

    user |> Tuist.Repo.preload(preload)
  end

  def organization_fixture(opts \\ []) do
    name = Keyword.get(opts, :name, "#{TestUtilities.unique_integer()}")
    creator = Keyword.get_lazy(opts, :creator, fn -> user_fixture() end)
    sso_provider = Keyword.get(opts, :sso_provider)
    sso_organization_id = Keyword.get(opts, :sso_organization_id)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    customer_id = Keyword.get(opts, :customer_id, "#{TestUtilities.unique_integer()}")
    preload = Keyword.get(opts, :preload, [:account])
    setup_billing = Keyword.get(opts, :setup_billing, false)

    current_month_remote_cache_hits_count =
      Keyword.get(opts, :current_month_remote_cache_hits_count, 0)

    Accounts.create_organization(%{name: name, creator: creator},
      sso_provider: sso_provider,
      sso_organization_id: sso_organization_id,
      created_at: created_at,
      customer_id: customer_id,
      setup_billing: setup_billing,
      current_month_remote_cache_hits_count: current_month_remote_cache_hits_count
    )
    |> Tuist.Repo.preload(preload)
  end

  def unique_user_email, do: "#{TestUtilities.unique_integer()}@tuist.io"
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

  def account_token_fixture(opts \\ []) do
    account =
      Keyword.get_lazy(opts, :account, fn -> user_fixture(preload: [:account]).account end)

    scopes = Keyword.get(opts, :scopes, [])

    {account_token, _} = Accounts.create_account_token(%{account: account, scopes: scopes})

    account_token
  end
end
