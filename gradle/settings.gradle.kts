rootProject.name = "tuist-gradle-plugin"

plugins {
    id("dev.tuist") version "0.7.0"
}

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
