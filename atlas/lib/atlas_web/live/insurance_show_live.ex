defmodule AtlasWeb.InsuranceShowLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Insurance.Policies
  alias Atlas.Insurance.Policy
  alias Atlas.Insurance.PolicyMember

  def mount(%{"id" => id}, _session, socket) do
    case Policies.get(id) do
      %Policy{} = policy ->
        members = Policies.list_members(policy)
        claims = Policies.list_claims(policy)
        documents = Policies.list_policy_documents(policy)

        {:ok,
         socket
         |> assign(:page_title, "#{policy.provider} · #{policy.product}")
         |> assign(:policy, policy)
         |> assign(:members, members)
         |> assign(:claims, claims)
         |> assign(:documents, documents)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Insurance policy not found."))
         |> push_navigate(to: ~p"/hardware/insurance")}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="insurance-show">
      <div data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="insurance-breadcrumb-list"
              label={gettext("Insurance")}
              phx-click={JS.navigate(~p"/hardware/insurance")}
            />
            <.breadcrumb id="insurance-breadcrumb-current" label={@policy.provider} />
          </.breadcrumbs>
          <h1 data-part="title">{@policy.provider}</h1>
          <p data-part="description">
            {[@policy.product, @policy.reference]
            |> Enum.reject(&(is_nil(&1) or &1 == ""))
            |> Enum.join(" · ")}
          </p>
          <div data-part="summary">
            <.badge
              label={humanize(@policy.status)}
              color={status_color(@policy.status)}
              style="light-fill"
            />
            <.badge
              :if={@policy.covers_leased}
              label={gettext("Covers leased")}
              color="information"
              style="light-fill"
            />
            <.badge
              :if={@policy.covers_third_party_owned}
              label={gettext("Covers 3rd-party")}
              color="information"
              style="light-fill"
            />
          </div>
        </div>
      </div>

      <.card title={gettext("Coverage")} icon="file" data-part="coverage-card">
        <.card_section>
          <dl data-part="details">
            <div data-part="detail">
              <dt>{gettext("Sum insured")}</dt>
              <dd>{amount(@policy.sum_insured, @policy.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Provisional cover")}</dt>
              <dd>{@policy.provisional_cover_pct}%</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Effective cap")}</dt>
              <dd>{amount(Policy.effective_cap(@policy), @policy.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Annual premium")}</dt>
              <dd>{amount(@policy.annual_premium, @policy.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Deductible per claim")}</dt>
              <dd>{amount(@policy.deductible_per_claim, @policy.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Deductible cap")}</dt>
              <dd>{amount(@policy.deductible_cap, @policy.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Mobile use")}</dt>
              <dd>{@policy.mobile_use_pct}%</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Clean-up costs")}</dt>
              <dd>
                {sublimit_label(
                  @policy.cleanup_pct,
                  @policy.cleanup_min,
                  @policy.cleanup_max,
                  @policy.currency
                )}
              </dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Movement / protection")}</dt>
              <dd>
                {sublimit_label(
                  @policy.movement_pct,
                  @policy.movement_min,
                  @policy.movement_max,
                  @policy.currency
                )}
              </dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Starts")}</dt>
              <dd>{date_or_dash(@policy.starts_on)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Ends")}</dt>
              <dd>{date_or_dash(@policy.ends_on)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Quote valid until")}</dt>
              <dd>{date_or_dash(@policy.quote_valid_until)}</dd>
            </div>
          </dl>
          <p :if={@policy.notes} data-part="notes">{@policy.notes}</p>
        </.card_section>
      </.card>

      <.card title={gettext("Documents")} icon="file" data-part="documents-card">
        <.card_section>
          <.table
            id="insurance-documents-table"
            rows={@documents}
            row_key={fn link -> "insurance-document-#{link.id}" end}
            row_navigate={fn link -> ~p"/documents/#{link.document_id}" end}
          >
            <:col :let={link} label={gettext("Kind")}>
              <.badge_cell
                label={humanize(link.kind)}
                color={document_kind_color(link.kind)}
                style="light-fill"
              />
            </:col>
            <:col :let={link} label={gettext("Title")}>
              <.text_cell label={document_title(link)} />
            </:col>
            <:col :let={link} label={gettext("Attached")}>
              <.text_cell label={date_or_dash(datetime_to_date(link.inserted_at))} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No documents attached")}
                subtitle={
                  gettext(
                    "Use attach_document_to_insurance_policy from the MCP to link the quote, policy PDF, and AVB."
                  )
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Declared assets")} icon="server" data-part="members-card">
        <.card_section>
          <.table
            id="insurance-members-table"
            rows={@members}
            row_key={fn m -> "insurance-member-#{m.id}" end}
            row_navigate={fn m -> ~p"/hardware/#{m.asset_id}" end}
          >
            <:col :let={m} label={gettext("Asset")}>
              <.text_cell label={member_asset_label(m)} />
            </:col>
            <:col :let={m} label={gettext("Declared value")}>
              <.text_cell label={amount(m.declared_value, @policy.currency)} />
            </:col>
            <:col :let={m} label={gettext("Covered from")}>
              <.text_cell label={date_or_dash(m.covered_from)} />
            </:col>
            <:col :let={m} label={gettext("Covered to")}>
              <.text_cell label={date_or_dash(m.covered_to)} />
            </:col>
            <:col :let={m} label={gettext("Status")}>
              <.badge_cell
                label={member_status_label(m)}
                color={member_status_color(m)}
                style="light-fill"
              />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No declared assets")}
                subtitle={gettext("Use add_asset_to_insurance from the MCP to declare assets.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Claims")} icon="mail" data-part="claims-card">
        <.card_section>
          <.table
            id="insurance-claims-table"
            rows={@claims}
            row_key={fn c -> "insurance-claim-#{c.id}" end}
          >
            <:col :let={c} label={gettext("Incident")}>
              <.text_and_description_cell
                label={date_or_dash(c.incident_on)}
                description={c.claim_reference || humanize(c.incident_type)}
              />
            </:col>
            <:col :let={c} label={gettext("Type")}>
              <.badge_cell label={humanize(c.incident_type)} color="neutral" style="light-fill" />
            </:col>
            <:col :let={c} label={gettext("Status")}>
              <.badge_cell
                label={humanize(c.status)}
                color={claim_status_color(c.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={c} label={gettext("Claimed")}>
              <.text_cell label={amount(c.claimed_amount, @policy.currency)} />
            </:col>
            <:col :let={c} label={gettext("Payout")}>
              <.text_cell label={amount(c.payout_amount, @policy.currency)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No claims")}
                subtitle={gettext("Claims filed against this policy will appear here.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp member_asset_label(%PolicyMember{asset: %Ecto.Association.NotLoaded{}}), do: "-"
  defp member_asset_label(%PolicyMember{asset: nil}), do: "-"
  defp member_asset_label(%PolicyMember{asset: %{name: name}}), do: name

  defp member_status_label(%PolicyMember{covered_to: nil}), do: gettext("Active")
  defp member_status_label(%PolicyMember{}), do: gettext("Closed")

  defp member_status_color(%PolicyMember{covered_to: nil}), do: "success"
  defp member_status_color(%PolicyMember{}), do: "neutral"

  defp sublimit_label(0, _, _, _), do: "-"

  defp sublimit_label(pct, nil, nil, _currency), do: "#{pct}%"

  defp sublimit_label(pct, min, max, currency) do
    range = [min, max] |> Enum.reject(&is_nil/1) |> Enum.map_join("…", &amount(&1, currency))
    "#{pct}% (#{range})"
  end

  defp humanize(nil), do: "-"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_color("active"), do: "success"
  defp status_color("quoted"), do: "attention"
  defp status_color("expired"), do: "neutral"
  defp status_color("cancelled"), do: "destructive"
  defp status_color("terminated"), do: "destructive"
  defp status_color(_), do: "neutral"

  defp claim_status_color("paid"), do: "success"
  defp claim_status_color("approved"), do: "success"
  defp claim_status_color("submitted"), do: "information"
  defp claim_status_color("draft"), do: "attention"
  defp claim_status_color("rejected"), do: "destructive"
  defp claim_status_color("withdrawn"), do: "neutral"
  defp claim_status_color(_), do: "neutral"

  defp amount(%Decimal{} = value, currency) when is_binary(currency),
    do: "#{currency} #{Decimal.to_string(value, :normal)}"

  defp amount(_, _), do: "-"

  defp date_or_dash(nil), do: "-"
  defp date_or_dash(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")

  defp datetime_to_date(nil), do: nil
  defp datetime_to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)
  defp datetime_to_date(%DateTime{} = dt), do: DateTime.to_date(dt)

  defp document_title(%{document: %Ecto.Association.NotLoaded{}}), do: "-"
  defp document_title(%{document: nil}), do: "-"
  defp document_title(%{document: %{title: title}}) when is_binary(title) and title != "", do: title
  defp document_title(%{document: %{original_filename: name}}) when is_binary(name), do: name
  defp document_title(_), do: "-"

  defp document_kind_color("policy"), do: "success"
  defp document_kind_color("quote"), do: "attention"
  defp document_kind_color("avb"), do: "information"
  defp document_kind_color("renewal"), do: "information"
  defp document_kind_color("endorsement"), do: "information"
  defp document_kind_color(_), do: "neutral"
end
