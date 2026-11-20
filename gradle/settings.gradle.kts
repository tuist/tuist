rootProject.name = "tuist-gradle-plugin"

plugins {
    id("dev.tuist") version "0.22.0"
}

tuist {
    coverage {
        enabled = true
    }
}

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
