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

    // Force compileSdk + namespace for plugin subprojects (network_info_plus etc).
    // Use plugins.withId + register afterEvaluate (from within the callback) + pure reflection.
    // This avoids KTS "unresolved reference" for the dynamic android extension and ensures
    // the override happens after the subproject's own build script has set its values.
    plugins.withId("com.android.library") {
        project.afterEvaluate {
            val ext = project.extensions.findByName("android") ?: return@afterEvaluate
            try {
                // compileSdk
                val setC = ext.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" || it.name == "setCompileSdk" }
                if (setC != null && setC.parameterTypes.isNotEmpty()) {
                    val p = setC.parameterTypes[0]
                    setC.invoke(ext, if (p == Int::class.java) 35 else "35")
                }
                // namespace
                val getNs = ext.javaClass.getMethod("getNamespace")
                val setNs = ext.javaClass.getMethod("setNamespace", String::class.java)
                if (getNs.invoke(ext) == null) {
                    setNs.invoke(ext, "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}")
                }
            } catch (_: Exception) {}
        }
    }
    plugins.withId("com.android.application") {
        project.afterEvaluate {
            val ext = project.extensions.findByName("android") ?: return@afterEvaluate
            try {
                val setC = ext.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" || it.name == "setCompileSdk" }
                if (setC != null && setC.parameterTypes.isNotEmpty()) {
                    val p = setC.parameterTypes[0]
                    setC.invoke(ext, if (p == Int::class.java) 35 else "35")
                }
                val getNs = ext.javaClass.getMethod("getNamespace")
                val setNs = ext.javaClass.getMethod("setNamespace", String::class.java)
                if (getNs.invoke(ext) == null) {
                    setNs.invoke(ext, "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}")
                }
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
