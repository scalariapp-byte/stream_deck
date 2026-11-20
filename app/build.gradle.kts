plugins {
    alias(libs.plugins.kotlin.compose)
    id("com.android.application")
}

// Numero de version = nombre de commits Git (1 si Git est absent).
val gitCommitCount: Int = runCatching {
    providers.exec { commandLine("git", "rev-list", "--count", "HEAD") }
        .standardOutput.asText.get().trim().toInt()
}.getOrDefault(1)

android {
    namespace = "com.myblackwhite.deck"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.myblackwhite.deck"
        minSdk = 26
        targetSdk = 37
        versionCode = gitCommitCount
        versionName = "0.$gitCommitCount"
    }

    buildTypes {
        release {
            optimization {
                enable = true
            }
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
}
