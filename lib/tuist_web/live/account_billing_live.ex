defmodule TuistWeb.AccountBillingLive do
  alias Tuist.Billing
  alias Tuist.Accounts
  use TuistWeb, :live_view

  def mount(%{"account_handle" => account_handle} = params, session, %{assigns: %{}} = socket) do
    owner = Accounts.get_account_by_handle(account_handle)

    user_token = session["user_token"]

    user =
      if is_nil(user_token) do
        nil
      else
        Accounts.get_user_by_session_token(session["user_token"], preload: [:account])
      end

    if not Tuist.Authorization.can(user, :update, owner, :billing) do
      raise TuistWeb.Errors.UnauthorizedError,
            gettext("You are not authorized to perform this action.")
    end

    subscription = Billing.get_current_active_subscription(owner)

    plan = get_plan(%{params: params, subscription: subscription})

    customer = Billing.get_customer_by_id(owner.customer_id)

    payment_method =
      with {:subscription, subscription} when not is_nil(subscription) <-
             {:subscription, subscription},
           {:payment_method_id, payment_method_id} when not is_nil(payment_method_id) <-
             {:payment_method_id,
              Billing.get_payment_method_id_from_subscription_id(subscription.subscription_id)},
           {:payment_method, payment_method} <-
             {:payment_method, Billing.get_payment_method_by_id(payment_method_id)} do
        payment_method
      else
        {:subscription, nil} -> nil
        {:payment_method_id, nil} -> nil
      end

    current_month_remote_cache_hits_count = owner.current_month_remote_cache_hits_count

    remote_cache_hit_unit_price = Billing.get_unit_prices()[:remote_cache_hit]

    estimated_next_payment =
      Billing.get_estimated_next_payment(%{
        current_month_remote_cache_hits_count: current_month_remote_cache_hits_count
      })

    subscription_current_period_end =
      if is_nil(subscription) do
        nil
      else
        Billing.get_subscription_current_period_end(subscription.subscription_id)
      end

    {
      :ok,
      socket
      |> assign(:plans, Billing.get_plans())
      |> assign(:remote_cache_hit_unit_price, remote_cache_hit_unit_price)
      |> assign(:head_title, "#{gettext("Billing")} · #{owner.name} · Tuist")
      |> assign(:selected_account, owner)
      |> assign(:plan, plan)
      |> assign(:new_plan, nil)
      |> assign(:customer, customer)
      |> assign(:payment_method, payment_method)
      |> assign(:subscription_current_period_end, subscription_current_period_end)
      |> assign(
        :current_month_remote_cache_hits_count,
        current_month_remote_cache_hits_count
      )
      |> assign(:estimated_next_payment, estimated_next_payment)
      |> assign(:new_plan_period, :monthly)
    }
  end

  defp get_plan(%{params: params, subscription: subscription}) do
    plan =
      cond do
        not is_nil(params["new_plan"]) ->
          String.to_atom(params["new_plan"])

        is_nil(subscription) ->
          :air

        true ->
          subscription.plan
      end

    if not Enum.member?([:air, :pro, :enterprise, :open_source], plan) do
      raise TuistWeb.Errors.NotFoundError,
            gettext("Invalid plan")
    end

    plan
  end

  def handle_params(_params, uri, socket) do
    {:noreply, socket |> assign(:uri, uri)}
  end

  def handle_event(
        "change_plan",
        %{"plan" => plan},
        socket
      ) do
    send(self(), :change_plan)

    {:noreply,
     socket
     |> assign(:new_plan, String.to_atom(plan))}
  end

  def handle_info(
        :change_plan,
        %{
          assigns: %{
            new_plan: new_plan,
            new_plan_period: new_plan_period,
            selected_account: selected_account,
            uri: uri
          }
        } = socket
      ) do
    socket =
      case Billing.update_plan(%{
             plan: new_plan,
             period: new_plan_period,
             account: selected_account,
             success_url: uri <> "?new_plan=#{new_plan}"
           }) do
        {:ok, {:external_redirect, session_url}} ->
          socket
          |> redirect(external: session_url)

        :ok ->
          socket
      end

    send(self(), :hide_modal)

    {
      :noreply,
      socket
      |> assign(:plan, new_plan)
    }
  end

  def handle_info(
        :hide_modal,
        socket
      ) do
    {:noreply,
     socket
     |> assign(:new_plan, nil)
     |> push_event("js-exec", %{
       to: "##{Atom.to_string(socket.assigns.new_plan)}-modal",
       attr: "data-cancel"
     })}
  end

  attr(:id, :string, required: true)
  attr(:plan, :atom, required: true)
  attr(:loading, :boolean, default: false)

  def change_plan_modal(assigns) do
    ~H"""
    <.legacy_modal id={@id}>
      <.stack gap="3xl">
        <.stack gap="xs">
          <p class="text--large font--semibold color--text-primary">
            <%= if @plan == :air do %>
              {gettext("Confirm downgrade to the Air plan")}
            <% else %>
              {gettext("Confirm upgrade to the Pro plan")}
            <% end %>
          </p>
          <p class="text--small font--regular color--text-tertiary">
            {gettext(
              "Upon clicking confirm, your monthly invoice will be adjusted and your credit card will be charged immediately. Changing the plan resets your billing cycle and may result in a prorated charge for previous usage."
            )}
          </p>
        </.stack>
        <.stack direction="horizontal" gap="lg" class="billing__confirm-modal__button-group">
          <.legacy_button
            variant="secondary"
            size="medium"
            type="button"
            phx-click={JS.exec("data-cancel", to: "##{@id}")}
          >
            {gettext("Cancel")}
          </.legacy_button>
          <.legacy_button
            variant="primary"
            size="medium"
            type="submit"
            phx-click="change_plan"
            phx-value-plan={@plan}
            data-plan-changed={JS.exec("data-cancel", to: "##{@id}")}
            loading={@loading}
          >
            {gettext("Confirm")}
          </.legacy_button>
        </.stack>
      </.stack>
    </.legacy_modal>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:price, :string, default: nil)
  attr(:price_extra, :string, default: nil)
  attr(:features, :list, required: true)

  slot(:inner_block, required: true)

  def pricing_tier_card(assigns) do
    ~H"""
    <.stack gap="4xl" class="billing__pricing-tier-card">
      <.stack gap="xl">
        <p class="text--large font--semibold color--text-tertiary">
          {@title}
        </p>
        <.stack
          gap="xs"
          direction="horizontal"
          align="end"
          class="color--text-tertiary billing__pricing-tier-card__price"
        >
          <%= if not is_nil(@price) do %>
            <h3 class="font--semibold color--text-primary">
              {@price}
            </h3>
            <p class="text--medium font--medium color--text-tertiary billing__pricing-tier-card__per-month-label">
              <%= if not is_nil(assigns[:price_extra]) do %>
                {@price_extra}
              <% end %>
            </p>
          <% else %>
            <h3 class="font--semibold color--text-primary">{gettext("Custom")}</h3>
          <% end %>
        </.stack>
        <p class="text--medium font--regular color--text-tertiary">
          {@description}
        </p>
      </.stack>
      <div class="billing__pricing-tier-card__action">
        {render_slot(@inner_block)}
      </div>
      <.stack gap="3xl">
        <.stack gap="xl" class="billing__pricing-tier-card__features-list">
          <%= for feature <- @features do %>
            <.stack
              gap="lg"
              direction="horizontal"
              class="billing__pricing-tier-card__features-list__feature"
            >
              <.check_icon />
              <%= if is_tuple(feature) do %>
                <.stack gap="xs">
                  <p class="text--medium font--medium color--text-secondary">
                    {elem(feature, 0)}
                  </p>
                  <p class="text--small font--regular color--text-tertiary">
                    {elem(feature, 1)}
                  </p>
                </.stack>
              <% else %>
                <p class="text--medium font--medium color--text-secondary">{feature}</p>
              <% end %>
            </.stack>
          <% end %>
        </.stack>
      </.stack>
    </.stack>
    """
  end
end
