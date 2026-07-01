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

    // Workaround for plugins that don't declare 'namespace' (required by AGP 8+).
    // Registered early in the same subprojects configure pass to avoid
    // "Cannot run Project.afterEvaluate when the project is already evaluated."
    // Uses receiver methods + reflection to keep KTS compilation happy.
    afterEvaluate {
        if (hasProperty("android")) {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                    val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    if (getNamespace.invoke(androidExt) == null) {
                        val ns = "com.cyberj812.boardgamesnap.${name.replace(":", ".")}"
                        setNamespace.invoke(androidExt, ns)
                    }
                } catch (_: Exception) {
                    // best effort
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
