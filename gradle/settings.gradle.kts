rootProject.name = "tuist-gradle-plugin"

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
