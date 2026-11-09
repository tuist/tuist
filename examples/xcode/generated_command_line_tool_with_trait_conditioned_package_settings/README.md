# Command line tool with trait-conditioned package settings

A command line tool that depends on a local Swift package whose C and Swift settings are gated on package traits with `.when(traits:)`. The package's sources fail to compile unless the settings of enabled traits are applied and the settings of disabled traits are not.
