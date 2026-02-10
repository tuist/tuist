import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    kotlin("multiplatform") version "2.1.0"
}

repositories {
    mavenCentral()
}

group = "com.example"
version = "1.0.0"

kotlin {
    val xcf = XCFramework("SharedKMP")

    iosArm64 {
        binaries.framework {
            baseName = "SharedKMP"
            xcf.add(this)
        }
    }

    iosSimulatorArm64 {
        binaries.framework {
            baseName = "SharedKMP"
            xcf.add(this)
        }
    }

    iosX64 {
        binaries.framework {
            baseName = "SharedKMP"
            xcf.add(this)
        }
    }
}
