plugins {
    `kotlin-dsl`
    `java-gradle-plugin`
    `maven-publish`
    id("com.gradle.plugin-publish") version "1.3.1"
}

group = "dev.tuist"
version = findProperty("version")?.takeIf { it != "unspecified" } ?: "0.1.0"

repositories {
    mavenCentral()
    gradlePluginPortal()
}

dependencies {
    implementation("com.google.code.gson:gson:2.10.1")

    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.junit.jupiter:junit-jupiter-api:5.10.2")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:5.10.2")
    testImplementation(gradleTestKit())
    testImplementation(kotlin("test"))
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

tasks.test {
    useJUnitPlatform()
}

gradlePlugin {
    website = "https://tuist.dev"
    vcsUrl = "https://github.com/tuist/tuist"
    plugins {
        create("tuist") {
            id = "dev.tuist"
            displayName = "Tuist"
            description = "Integrates Gradle projects with Tuist services including remote build caching and analytics"
            implementationClass = "dev.tuist.gradle.TuistPlugin"
            tags = listOf("build-cache", "remote-cache", "tuist", "analytics")
        }
    }
}

publishing {
    publications {
        create<MavenPublication>("pluginMaven") {
            groupId = "dev.tuist"
            artifactId = "tuist-gradle-plugin"
            version = project.version.toString()
        }
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
