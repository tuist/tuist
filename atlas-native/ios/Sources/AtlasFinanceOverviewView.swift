import Charts
import SwiftUI

struct AtlasFinanceOverviewView: View {
    let overview: AtlasFinanceOverview?

    var body: some View {
        if let overview {
            if overview.accountCount == 0 {
                Section("Finance overview") {
                    Text("No connected bank accounts yet.").foregroundStyle(.secondary)
                }
            } else if !overview.excludedCurrencies.isEmpty {
                Section("Finance overview") {
                    Label("Currency conversion unavailable", systemImage: "exclamationmark.triangle")
                    Text(
                        """
                        Totals are unavailable because exchange rates are missing for \
                        \(overview.excludedCurrencies.joined(separator: ", ")). Pull to refresh to retry.
                        """
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                metrics(overview)
                cashFlow(overview)
            }
        } else {
            Section("Finance overview") {
                Text("Update your Atlas server to see cash flow in one reporting currency.").foregroundStyle(.secondary)
            }
        }
    }

    private func metrics(_ overview: AtlasFinanceOverview) -> some View {
        Section {
            LabeledContent("Available cash", value: money(overview.availableCash, overview.currency))
                .accessibilityIdentifier("finance-available-cash")
            LabeledContent("Monthly burn", value: money(overview.monthlyBurn, overview.currency))
            LabeledContent(
                "Runway",
                value: overview.runwayMonths.map {
                    "\(NSDecimalNumber(string: $0).doubleValue.formatted(.number.precision(.fractionLength(0...1)))) months"
                } ?? "Not enough data")
        } header: {
            Text("Overview · \(overview.currency)")
        } footer: {
            Text("As of \(AtlasBusinessFormatting.date(overview.asOf)). Burn and runway require sufficient transaction history.")
        }
    }

    private func cashFlow(_ overview: AtlasFinanceOverview) -> some View {
        Section {
            if let current = overview.months.last {
                LabeledContent("Income this month", value: money(current.income, overview.currency))
                LabeledContent("Expenses this month", value: money(current.expense, overview.currency))
            }
            Chart(overview.months) { month in
                if let date = month.date {
                    BarMark(x: .value("Month", date, unit: .month), y: .value("Amount", Double(month.income) ?? 0))
                        .foregroundStyle(by: .value("Series", "Income"))
                        .position(by: .value("Series", "Income"))
                        .accessibilityLabel("\(date.formatted(.dateTime.month(.wide).year())), income")
                        .accessibilityValue(money(month.income, overview.currency))
                    BarMark(x: .value("Month", date, unit: .month), y: .value("Amount", Double(month.expense) ?? 0))
                        .foregroundStyle(by: .value("Series", "Expenses"))
                        .position(by: .value("Series", "Expenses"))
                        .accessibilityLabel("\(date.formatted(.dateTime.month(.wide).year())), expenses")
                        .accessibilityValue(money(month.expense, overview.currency))
                }
            }
            .chartForegroundStyleScale(["Income": Color.green, "Expenses": Color.orange])
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxisLabel(overview.currency)
            .frame(height: 190)
            .accessibilityIdentifier("finance-cash-flow")
            DisclosureGroup("Monthly values") {
                ForEach(overview.months) { month in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(month.date?.formatted(.dateTime.month(.wide).year()) ?? month.month).font(.headline)
                        LabeledContent("Income", value: money(month.income, overview.currency))
                        LabeledContent("Expenses", value: money(month.expense, overview.currency))
                    }.font(.subheadline)
                }
            }
        } header: {
            Text("Income and expenses")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bank transactions in \(overview.currency), excluding internal transfers. The current month is incomplete.")
                if let published = overview.fxPublishedOn {
                    Text("Exchange rates published \(AtlasBusinessFormatting.date(published)).")
                }
            }
        }
    }

    private func money(_ amount: String?, _ currency: String) -> String {
        amount.map { AtlasBusinessFormatting.money($0, currency: currency) } ?? "Not enough data"
    }
}
