rootProject.name = "tuist-gradle-plugin"

plugins {
    id("dev.tuist") version "0.2.5"
}

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
