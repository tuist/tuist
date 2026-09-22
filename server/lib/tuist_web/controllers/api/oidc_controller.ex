defmodule TuistWeb.API.OIDCController do
  @moduledoc """
  Controller for OIDC token exchange.

  This controller handles the exchange of CI provider OIDC tokens for
  short-lived Tuist access tokens. Supports GitHub Actions, CircleCI, and Bitrise.
  """

  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Guardian
  alias Tuist.OIDC
  alias Tuist.OIDC.ScopeRules
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.WarningsHeaderPlug

  require Logger

  plug(
    TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags(["OIDC Authentication"])

  @token_ttl_seconds 3600

  operation(:exchange_token,
    summary: "Exchange a CI provider OIDC token for a Tuist access token.",
    description: """
    Exchange an OIDC token from a supported CI provider (GitHub Actions, CircleCI, or Bitrise)
    for a short-lived Tuist access token.

    Projects and accounts can configure OIDC scope rules that require specific GitHub Actions
    claims (`ref`, `job_workflow_ref`, `environment`) before the token can use a write scope.
    When a rule doesn't match, the token keeps the matching read scope for that resource, and
    the response carries a warning naming the withheld scope.
    """,
    operation_id: "exchangeOIDCToken",
    request_body:
      {"OIDC token exchange request", "application/json",
       %Schema{
         title: "OIDCTokenExchangeRequest",
         type: :object,
         properties: %{
           token: %Schema{
             type: :string,
             description: "The OIDC JWT token from the CI provider."
           }
         },
         required: [:token]
       }},
    responses: %{
      ok:
        {"Token exchange successful", "application/json",
         %Schema{
           title: "OIDCTokenExchangeResponse",
           type: :object,
           properties: %{
             access_token: %Schema{
               type: :string,
               description: "The Tuist access token to use for API requests."
             },
             expires_in: %Schema{
               type: :integer,
               description: "Token lifetime in seconds."
             }
           },
           required: [:access_token, :expires_in]
         }},
      bad_request: {"Unsupported CI provider or missing repository claim", "application/json", Error},
      unauthorized: {"Invalid or expired OIDC token", "application/json", Error},
      forbidden: {"No projects linked to the repository", "application/json", Error}
    }
  )

  def exchange_token(%{body_params: %{token: token}} = conn, _opts) do
    with {:ok, claims} <- OIDC.claims(token),
         {:ok, projects} <- find_projects_by_repository(claims.repository),
         {:ok, account} <- single_account(projects, claims.repository),
         {withheld_scopes, failures} = ScopeRules.evaluate(account, projects, claims),
         {:ok, access_token} <- generate_token(account, projects, withheld_scopes) do
      log_exchange(claims, account, failures)

      conn
      |> put_withheld_warnings(failures)
      |> put_status(:ok)
      |> json(%{
        access_token: access_token,
        expires_in: @token_ttl_seconds
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Invalid OIDC token format"})

      {:error, :unsupported_provider, issuer} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message:
            "Unsupported CI provider. Token issuer '#{issuer}' is not supported. Currently supported: GitHub Actions, CircleCI, and Bitrise."
        })

      {:error, :missing_repository_claim} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message:
            "OIDC token does not contain required repository information used to verify it with the GitHub project connection."
        })

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token signature verification failed"})

      {:error, :token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token has expired"})

      {:error, :invalid_audience} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token audience is not valid for Tuist"})

      {:error, :jwks_fetch_failed, jwks_uri} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{message: "Failed to fetch JWKS from identity provider: #{jwks_uri}"})

      {:error, :no_projects} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "No projects linked to the repository. Connect your project to GitHub in the Tuist dashboard first."
        })

      {:error, :ambiguous_repository, repository, account_handles} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message:
            "The repository '#{repository}' is linked to projects in multiple Tuist accounts (#{Enum.join(account_handles, ", ")}). Remove the extra connections in the Tuist dashboard so the repository is linked from a single account."
        })

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Token validation failed: #{inspect(reason)}"})
    end
  end

  defp find_projects_by_repository(repository) do
    case Projects.projects_by_vcs_repository_full_handle(repository, preload: [:account]) do
      [] -> {:error, :no_projects}
      projects -> {:ok, projects}
    end
  end

  # A token is scoped to one account, and project access requires the
  # token's account to own the project. If the repository is linked from
  # several accounts, no single token can serve every linked project, so
  # refuse the exchange instead of picking an account by row order.
  defp single_account(projects, repository) do
    case projects |> Enum.map(& &1.account) |> Enum.uniq_by(& &1.id) do
      [account] -> {:ok, account}
      accounts -> {:error, :ambiguous_repository, repository, accounts |> Enum.map(& &1.name) |> Enum.sort()}
    end
  end

  defp generate_token(account, projects, withheld_scopes) do
    project_ids = Enum.map(projects, & &1.id)

    claims =
      Map.merge(
        %{
          "type" => "account",
          "scopes" => ["ci"],
          "project_ids" => project_ids
        },
        if(withheld_scopes == %{}, do: %{}, else: %{"withheld_scopes" => withheld_scopes})
      )

    case Guardian.encode_and_sign(account, claims, ttl: {@token_ttl_seconds, :second}) do
      {:ok, token, _full_claims} -> {:ok, token}
      error -> error
    end
  end

  defp log_exchange(claims, account, failures) do
    Logger.info(
      "OIDC token exchanged for account #{account.id}: repository=#{claims.repository} " <>
        "provider=#{claims[:provider]} ref=#{claims[:ref]} job_workflow_ref=#{claims[:job_workflow_ref]} " <>
        "environment=#{claims[:environment]} withheld_scopes=#{Enum.map_join(failures, ",", & &1.scope)}"
    )

    Enum.each(failures, fn failure ->
      :telemetry.execute([:tuist, :oidc, :scope_withheld], %{count: 1}, %{
        scope: failure.scope,
        level: failure.level,
        field: failure.field
      })
    end)
  end

  defp put_withheld_warnings(conn, failures) do
    Enum.reduce(failures, conn, fn failure, conn ->
      WarningsHeaderPlug.put_warning(conn, withheld_warning(failure))
    end)
  end

  defp withheld_warning(%{scope: scope, level: level, project: project, field: field, value: value}) do
    target =
      case level do
        :account -> "the account"
        :project -> "project #{project.account.name}/#{project.name}"
      end

    reason =
      case field do
        :provider -> "OIDC scope rules only support GitHub Actions tokens"
        _ when value in [nil, ""] -> "the token has no `#{field}` claim"
        _ -> "#{field} `#{value}` doesn't match the #{level} rules"
      end

    "This OIDC token can't use #{scope} for #{target}: #{reason}. It keeps read access."
  end
end
