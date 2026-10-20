defmodule AtlasWeb.RevenueComponents do
  use Phoenix.Component
  use Noora

  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Lifecycle

  attr :segment, :any, required: true

  def account_lifecycle_badge(assigns) do
    lifecycle = Lifecycle.from_segment(assigns.segment)
    assigns = assign(assigns, label: lifecycle.label, color: lifecycle.color)

    ~H"""
    <.badge label={@label} color={@color} style="light-fill" />
    """
  end

  attr :segment, :any, required: true

  def account_lifecycle_badge_cell(assigns) do
    lifecycle = Lifecycle.from_segment(assigns.segment)
    assigns = assign(assigns, label: lifecycle.label, color: lifecycle.color)

    ~H"""
    <.badge_cell label={@label} color={@color} style="light-fill" />
    """
  end

  attr :deal_stage, :any, required: true

  def account_deal_stage_badge(assigns) do
    case DealStage.from_key(assigns.deal_stage) do
      nil ->
        ~H"<span>-</span>"

      stage ->
        assigns = assign(assigns, label: stage.label, color: stage.color)

        ~H"""
        <.badge label={@label} color={@color} style="light-fill" />
        """
    end
  end

  attr :deal_stage, :any, required: true
  attr :poc_end_date, :any, default: nil

  def account_deal_stage_badge_cell(assigns) do
    case DealStage.from_key(assigns.deal_stage) do
      nil ->
        ~H"""
        <.text_cell label="-" />
        """

      stage ->
        label =
          case poc_countdown_label(stage.key, assigns.poc_end_date) do
            nil -> stage.label
            countdown -> "#{stage.label} · #{countdown}"
          end

        color = poc_countdown_color(stage.key, assigns.poc_end_date) || stage.color
        assigns = assign(assigns, label: label, color: color)

        ~H"""
        <.badge_cell label={@label} color={@color} style="light-fill" />
        """
    end
  end

  defp poc_countdown_label("poc", %Date{} = end_date) do
    days = Date.diff(end_date, Date.utc_today())

    cond do
      days < 0 -> "#{abs(days)}d overdue"
      days == 0 -> "ends today"
      true -> "#{days}d left"
    end
  end

  defp poc_countdown_label(_stage, _end_date), do: nil

  defp poc_countdown_color("poc", %Date{} = end_date) do
    days = Date.diff(end_date, Date.utc_today())

    cond do
      days < 0 -> "destructive"
      days <= 7 -> "warning"
      true -> nil
    end
  end

  defp poc_countdown_color(_stage, _end_date), do: nil

  attr :status, :any, required: true

  def account_status_badge_cell(assigns) do
    {label, color} =
      case assigns.status do
        "active" -> {"Active", "success"}
        "trial" -> {"Trial", "information"}
        "paused" -> {"Paused", "warning"}
        "churned" -> {"Churned", "destructive"}
        _ -> {nil, nil}
      end

    case label do
      nil ->
        ~H"""
        <.text_cell label="-" />
        """

      _ ->
        assigns = assign(assigns, label: label, color: color)

        ~H"""
        <.badge_cell label={@label} color={@color} style="light-fill" />
        """
    end
  end

  @doc """
  Builds a favicon URL for `domain` via Google's S2 favicon service.
  """
  def domain_favicon_url(domain, size \\ 64) do
    "https://www.google.com/s2/favicons?domain=#{URI.encode_www_form(domain)}&sz=#{size}"
  end
end
