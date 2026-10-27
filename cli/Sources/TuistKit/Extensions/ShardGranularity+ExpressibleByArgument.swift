import ArgumentParser
import TuistServer

public typealias ShardGranularity = Components.Schemas.CreateShardPlanParams.granularityPayload

extension ShardGranularity: @retroactive ArgumentParser.ExpressibleByArgument {}
