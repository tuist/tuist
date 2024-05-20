defmodule TuistCloud.AccountsFixtures do
  @moduledoc false

  alias TuistCloud.Accounts
  alias TuistCloud.TestUtilities

  def user_fixture(opts \\ []) do
    email = Keyword.get(opts, :email, unique_user_email())
    password = Keyword.get(opts, :password, valid_user_password())
    confirmed_at = Keyword.get(opts, :confirmed_at, DateTime.utc_now())

    user = Accounts.create_user(email, password: password, confirmed_at: confirmed_at)

    user
  end

  def organization_fixture(opts \\ []) do
    name = Keyword.get(opts, :name, "#{TestUtilities.unique_integer()}")
    creator = Keyword.get_lazy(opts, :creator, fn -> user_fixture() end)
    sso_provider = Keyword.get(opts, :sso_provider)
    sso_organization_id = Keyword.get(opts, :sso_organization_id)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())

    Accounts.create_organization(%{name: name, creator: creator},
      sso_provider: sso_provider,
      sso_organization_id: sso_organization_id,
      created_at: created_at
    )
  end

  def unique_user_email, do: "#{TestUtilities.unique_integer()}@cloud.tuist.io"
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
end
