rootProject.name = "tuist-gradle-plugin"

plugins {
    id("dev.tuist") version "0.2.4"
}

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
