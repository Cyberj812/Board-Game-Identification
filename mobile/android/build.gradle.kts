allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    project.evaluationDependsOn(":app")

    // Namespace shim for AGP 8+: use plugins.withId so the action runs
    // exactly when the Android plugin is applied (avoids afterEvaluate timing/"already evaluated" errors).
    // Reflection used to avoid static type resolution issues in KTS.
    plugins.withId("com.android.library") {
        android {
            // Force a high enough compileSdk for plugins (network_info_plus etc) that declare 33
            // but transitives like androidx.fragment 1.7 require 34+.
            compileSdk = 35
            @Suppress("DEPRECATION")
            if (namespace == null) {
                namespace = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
            }
        }
    }
    plugins.withId("com.android.application") {
        android {
            compileSdk = 35
            @Suppress("DEPRECATION")
            if (namespace == null) {
                namespace = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
