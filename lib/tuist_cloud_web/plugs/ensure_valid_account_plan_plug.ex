defmodule TuistCloudWeb.EnsureValidAccountPlanPlug do
  @moduledoc ~S"""
  A plug that ensures that the account associated to the requests has a valid plan.
  """
  use TuistCloudWeb, :controller

  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  alias TuistCloud.Accounts

  @upload_count_threshold 10_000

  def init(opts), do: opts

  def upload_count_threshold(), do: @upload_count_threshold

  def formatted_upload_count_threshold() do
    Number.Delimit.number_to_delimited(@upload_count_threshold,
      delimiter: ".",
      precision: 0
    )
  end

  def call(conn, _opts) do
    project = EnsureProjectPresencePlug.get_project(conn)
    account = Accounts.get_account_by_id(project.account_id)

    case account.plan do
      :none ->
        eighty_percent = trunc(@upload_count_threshold * 0.8)

        case account.cache_upload_event_count do
          x when x in 0..eighty_percent ->
            conn

          x when x in eighty_percent..@upload_count_threshold ->
            conn
            |> TuistCloudWeb.WarningsHeaderPlug.put_warning(
              "Your account is nearing the 30-day free limit of #{formatted_upload_count_threshold()} cache uploads on Tuist. Once this limit is reached, you won't be able to use Tuist's remote caching feature. To continue enjoying this service, please reach out to us at contact@tuist.io for a quote on a Tuist plan."
            )

          _ ->
            conn
            |> put_status(402)
            |> json(%{
              message:
                "Your account is over the 30-day free limit of #{formatted_upload_count_threshold()} cache uploads on Tuist. To continue enjoying this service, please reach out to us at contact@tuist.io for a quote on a Tuist plan."
            })
            |> halt()
        end

      :enterprise ->
        conn
    end
  end
end
