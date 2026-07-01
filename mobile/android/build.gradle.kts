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
            // Force compileSdk >=34 for plugins pulling newer androidx (e.g. network_info_plus + fragment 1.7+)
            try {
                val m = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" || it.name == "setCompileSdk" }
                if (m != null && m.parameterTypes.isNotEmpty()) {
                    val arg = if (m.parameterTypes[0] == Int::class.java) 34 else "34"
                    m.invoke(androidExt, arg)
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
            try {
                val m = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" || it.name == "setCompileSdk" }
                if (m != null && m.parameterTypes.isNotEmpty()) {
                    val arg = if (m.parameterTypes[0] == Int::class.java) 34 else "34"
                    m.invoke(androidExt, arg)
                }
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
