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
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                if (getNamespace.invoke(androidExt) == null) {
                    val ns = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
                    setNamespace.invoke(androidExt, ns)
                }
            } catch (_: Exception) {}
        }
    }
    plugins.withId("com.android.application") {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                if (getNamespace.invoke(androidExt) == null) {
                    val ns = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
                    setNamespace.invoke(androidExt, ns)
                }
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
