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
// Uses safe Project receiver methods + runtime reflection (no static AGP types)
// so that Kotlin DSL script compilation does not fail with unresolved refs.
subprojects {
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
                    // best effort; ignore if the extension shape differs
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
