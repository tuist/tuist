defmodule TuistCloudWeb.BillingLive do
  alias TuistCloud.Environment
  alias TuistCloud.Billing
  alias TuistCloud.Accounts
  use TuistCloudWeb, :live_view

  def mount(%{"owner_handle" => owner_handle} = params, session, %{assigns: %{}} = socket) do
    if not Environment.new_pricing_model?() do
      raise TuistCloudWeb.Errors.NotFoundError,
            gettext("The billing page is not available at the moment.")
    end

    owner = Accounts.get_account_by_handle(owner_handle)

    user_token = session["user_token"]

    user =
      if is_nil(user_token) do
        nil
      else
        Accounts.get_user_by_session_token(session["user_token"], preloads: [:account])
      end

    if not TuistCloud.Authorization.can(user, :update, owner, :billing) do
      raise TuistCloudWeb.Errors.UnauthorizedError,
            gettext("You are not authorized to perform this action.")
    end

    subscription = Billing.get_current_active_subscription(owner)

    plan = get_plan(%{params: params, subscription: subscription})

    customer = Billing.get_customer_by_id(owner.customer_id)

    payment_method =
      if is_nil(subscription) or is_nil(subscription.default_payment_method) do
        nil
      else
        Billing.get_payment_method_by_id(subscription.default_payment_method)
      end

    {
      :ok,
      socket
      |> assign(:selected_owner, owner)
      |> assign(:plan, plan)
      |> assign(:new_plan, nil)
      |> assign(:customer, customer)
      |> assign(:payment_method, payment_method)
      |> assign(
        :current_month_remote_cache_hits,
        Accounts.get_current_month_remote_cache_hits_count(owner)
      )
      |> assign(:new_plan_period, :monthly)
      |> assign(:is_trialing, not is_nil(subscription) and subscription.status == "trialing")
    }
  end

  defp get_plan(%{params: params, subscription: subscription}) do
    plan =
      cond do
        not is_nil(params["new_plan"]) ->
          String.to_atom(params["new_plan"])

        is_nil(subscription) ->
          :none

        true ->
          subscription.plan
      end

    if not Enum.member?([:air, :pro, :enterprise, :none], plan) do
      raise TuistCloudWeb.Errors.NotFoundError,
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
            selected_owner: selected_owner,
            uri: uri
          }
        } = socket
      ) do
    session_url =
      Billing.update_plan(%{
        plan: new_plan,
        period: new_plan_period,
        account: selected_owner,
        success_url: uri <> "?new_plan=#{new_plan}"
      })

    socket =
      if is_nil(session_url) do
        socket
      else
        socket
        |> redirect(external: session_url)
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
    <.modal id={@id}>
      <.stack gap="3xl">
        <.stack gap="xs">
          <p class="text--large font--semibold color--text-primary">
            <%= if @plan == :air do %>
              <%= gettext("Confirm downgrade to the Air plan") %>
            <% else %>
              <%= gettext("Confirm upgrade to the Pro plan") %>
            <% end %>
          </p>
          <p class="text--small font--regular color--text-tertiary">
            <%= gettext(
              "Upon clicking confirm, your monthly invoice will be adjusted and your credit card will be charged immediately. Changing the plan resets your billing cycle and may result in a prorated charge for previous usage."
            ) %>
          </p>
        </.stack>
        <.stack direction="horizontal" gap="lg" class="billing__confirm-modal__button-group">
          <.button
            variant="secondary"
            size="medium"
            type="button"
            phx-click={JS.exec("data-cancel", to: "##{@id}")}
          >
            <%= gettext("Cancel") %>
          </.button>
          <.button
            variant="primary"
            size="medium"
            type="submit"
            phx-click="change_plan"
            phx-value-plan={@plan}
            data-plan-changed={JS.exec("data-cancel", to: "##{@id}")}
            loading={@loading}
          >
            <%= gettext("Confirm") %>
          </.button>
        </.stack>
      </.stack>
    </.modal>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:price, :string, default: nil)
  attr(:features, :list, required: true)

  slot(:inner_block, required: true)

  def pricing_tier_card(assigns) do
    ~H"""
    <.stack gap="4xl" class="billing__pricing-tier-card">
      <.stack gap="xl">
        <p class="text--large font--semibold color--text-tertiary">
          <%= @title %>
        </p>
        <.stack
          gap="xs"
          direction="horizontal"
          align="end"
          class="color--text-tertiary billing__pricing-tier-card__price"
        >
          <%= if not is_nil(@price) do %>
            <h2 class="font--semibold color--text-primary">
              <%= @price %>
            </h2>
            <p class="text--medium font--medium color--text-tertiary billing__pricing-tier-card__per-month-label">
              <%= gettext("per month") %>
            </p>
            <p class="text--extraLarge font--medium color--text-secondary">
              <%= gettext("+ Usage") %>
            </p>
          <% else %>
            <h2 class="font--semibold color--text-primary"><%= gettext("Custom") %></h2>
          <% end %>
        </.stack>
        <p class="text--medium font--regular color--text-tertiary">
          <%= @description %>
        </p>
      </.stack>
      <div class="billing__pricing-tier-card__action">
        <%= render_slot(@inner_block) %>
      </div>
      <.stack gap="3xl">
        <.stack gap="xs">
          <p class="text--medium font--semibold color--text-primary"><%= gettext("Features") %></p>
        </.stack>
        <.stack gap="xl" class="billing__pricing-tier-card__features-list">
          <%= for feature <- @features do %>
            <.stack
              gap="lg"
              direction="horizontal"
              class="billing__pricing-tier-card__features-list__feature"
            >
              <.check />
              <%= if is_tuple(feature) do %>
                <.stack gap="xs">
                  <p class="text--medium font--medium color--text-secondary">
                    <%= elem(feature, 0) %>
                  </p>
                  <p class="text--small font--regular color--text-tertiary">
                    <%= elem(feature, 1) %>
                  </p>
                </.stack>
              <% else %>
                <p class="text--medium font--medium color--text-secondary"><%= feature %></p>
              <% end %>
            </.stack>
          <% end %>
        </.stack>
      </.stack>
    </.stack>
    """
  end
end
