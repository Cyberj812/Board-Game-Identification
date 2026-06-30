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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Workaround for plugins that don't declare 'namespace' (required by AGP 8+).
// This forces a namespace on library subprojects (like flutter_secure_storage) that use
// conditional namespace setting. Using simple dynamic access for compatibility.
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            project.android {
                @Suppress("DEPRECATION")
                if (namespace == null) {
                    namespace = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
