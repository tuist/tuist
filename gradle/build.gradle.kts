plugins {
    `kotlin-dsl`
    `java-gradle-plugin`
    `maven-publish`
    id("com.gradle.plugin-publish") version "1.3.1"
    id("com.gradleup.shadow") version "9.0.0-beta12"
}

group = "dev.tuist"
version = findProperty("version")?.takeIf { it != "unspecified" } ?: "0.1.0"

repositories {
    mavenCentral()
    gradlePluginPortal()
}

dependencies {
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-gson:2.11.0")
    implementation("org.tomlj:tomlj:1.1.1")
    implementation("net.java.dev.jna:jna:5.14.0")

    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.junit.jupiter:junit-jupiter-api:5.10.2")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:5.10.2")
    testImplementation(gradleTestKit())
    testImplementation(kotlin("test"))
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

tasks.shadowJar {
    archiveClassifier.set("")
    dependencies {
        exclude(dependency("org.jetbrains.kotlin:.*"))
        exclude(dependency("org.jetbrains:annotations:.*"))
    }
    relocate("okhttp3", "dev.tuist.shadow.okhttp3")
    relocate("retrofit2", "dev.tuist.shadow.retrofit2")
    relocate("okio", "dev.tuist.shadow.okio")
    relocate("com.google.gson", "dev.tuist.shadow.gson")
    relocate("org.tomlj", "dev.tuist.shadow.tomlj")
    relocate("org.antlr", "dev.tuist.shadow.antlr")
    minimize {
        exclude(dependency("net.java.dev.jna:.*"))
    }
}

tasks.jar {
    archiveClassifier.set("thin")
}

listOf(configurations.apiElements, configurations.runtimeElements).forEach { config ->
    config.configure {
        outgoing.artifacts.clear()
        outgoing.artifact(tasks.shadowJar)
    }
}

tasks.test {
    useJUnitPlatform()
    maxParallelForks = (Runtime.getRuntime().availableProcessors() / 2).coerceAtLeast(1)
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

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}
