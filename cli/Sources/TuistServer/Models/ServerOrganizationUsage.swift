import Foundation

/// Server organization usage over the current billing period
public struct ServerOrganizationUsage: Codable, Equatable {
    public struct Meter: Codable, Equatable {
        public let used: Int
        public let included: Int
        public let billable: Int
        public let chargeCents: Int

        public init(used: Int, included: Int, billable: Int, chargeCents: Int) {
            self.used = used
            self.included = included
            self.billable = billable
            self.chargeCents = chargeCents
        }

        init(_ meter: Components.Schemas.OrganizationUsageMeter) {
            used = meter.used
            included = meter.included
            billable = meter.billable
            chargeCents = meter.charge_cents
        }
    }

    public struct RunnerMinutes: Codable, Equatable {
        public let used: Int
        public let included: Int
        public let chargeCents: Int

        public init(used: Int, included: Int, chargeCents: Int) {
            self.used = used
            self.included = included
            self.chargeCents = chargeCents
        }

        init(_ runnerMinutes: Components.Schemas.OrganizationUsageRunnerMinutes) {
            used = runnerMinutes.used
            included = runnerMinutes.included
            chargeCents = runnerMinutes.charge_cents
        }
    }

    public let periodStart: Date
    public let periodEnd: Date
    /// Cache egress in bytes.
    public let cacheEgress: Meter
    public let cacheRequests: Meter
    public let passingTestCases: Meter
    public let runnerMinutes: RunnerMinutes
    public let estimatedChargeCents: Int

    public init(
        periodStart: Date,
        periodEnd: Date,
        cacheEgress: Meter,
        cacheRequests: Meter,
        passingTestCases: Meter,
        runnerMinutes: RunnerMinutes,
        estimatedChargeCents: Int
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.cacheEgress = cacheEgress
        self.cacheRequests = cacheRequests
        self.passingTestCases = passingTestCases
        self.runnerMinutes = runnerMinutes
        self.estimatedChargeCents = estimatedChargeCents
    }

    init(_ organizationUsage: Components.Schemas.OrganizationUsage) {
        periodStart = organizationUsage.period.start
        periodEnd = organizationUsage.period.end
        cacheEgress = Meter(organizationUsage.cache_egress)
        cacheRequests = Meter(organizationUsage.cache_requests)
        passingTestCases = Meter(organizationUsage.passing_test_cases)
        runnerMinutes = RunnerMinutes(organizationUsage.runner_minutes)
        estimatedChargeCents = organizationUsage.estimated_charge_cents
    }

    #if DEBUG
        public static func test(
            periodStart: Date = Date(timeIntervalSince1970: 1_792_657_800),
            periodEnd: Date = Date(timeIntervalSince1970: 1_795_336_200),
            cacheEgress: Meter = Meter(used: 0, included: 100_000_000_000, billable: 0, chargeCents: 0),
            cacheRequests: Meter = Meter(used: 0, included: 1_000_000, billable: 0, chargeCents: 0),
            passingTestCases: Meter = Meter(used: 0, included: 5_000_000, billable: 0, chargeCents: 0),
            runnerMinutes: RunnerMinutes = RunnerMinutes(used: 0, included: 100, chargeCents: 0),
            estimatedChargeCents: Int = 0
        ) -> Self {
            .init(
                periodStart: periodStart,
                periodEnd: periodEnd,
                cacheEgress: cacheEgress,
                cacheRequests: cacheRequests,
                passingTestCases: passingTestCases,
                runnerMinutes: runnerMinutes,
                estimatedChargeCents: estimatedChargeCents
            )
        }
    #endif
}
