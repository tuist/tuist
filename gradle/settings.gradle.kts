rootProject.name = "tuist-gradle-plugin"

plugins {
    id("dev.tuist") version "0.9.0"
}

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
