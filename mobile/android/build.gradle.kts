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
// conditional namespace setting. Must be in KTS compatible form.
subprojects {
    afterEvaluate {
        if (this.hasProperty("android")) {
            val androidExt = this.extensions.findByName("android")
            if (androidExt is com.android.build.gradle.BaseExtension && androidExt.namespace == null) {
                androidExt.namespace = "com.cyberj812.boardgamesnap.${this.name.replace(":", ".")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
