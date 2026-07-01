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

    // Force compileSdk + namespace for plugin subprojects using pure reflection inside withId.
    // No afterEvaluate registration (avoids "already evaluated" errors).
    // Direct method calls on the extension object to override values set by plugin scripts.
    plugins.withId("com.android.library") {
        val ext = project.extensions.findByName("android")
        if (ext != null) {
            try {
                // compileSdk - try several common setters
                try { ext.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(ext, 35) } catch (_: Exception) {}
                try { ext.javaClass.getMethod("compileSdkVersion", Int::class.java).invoke(ext, 35) } catch (_: Exception) {}
                try { ext.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(ext, 35) } catch (_: Exception) {}
                try { ext.javaClass.getMethod("setCompileSdk", String::class.java).invoke(ext, "35") } catch (_: Exception) {}
                // namespace
                try {
                    val ns = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
                    val cur = ext.javaClass.getMethod("getNamespace").invoke(ext)
                    if (cur == null) {
                        ext.javaClass.getMethod("setNamespace", String::class.java).invoke(ext, ns)
                    }
                } catch (_: Exception) {}
            } catch (_: Exception) {}
        }
    }
    plugins.withId("com.android.application") {
        val ext = project.extensions.findByName("android")
        if (ext != null) {
            try {
                try { ext.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(ext, 35) } catch (_: Exception) {}
                try { ext.javaClass.getMethod("compileSdkVersion", Int::class.java).invoke(ext, 35) } catch (_: Exception) {}
                try { ext.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(ext, 35) } catch (_: Exception) {}
                try { ext.javaClass.getMethod("setCompileSdk", String::class.java).invoke(ext, "35") } catch (_: Exception) {}
                try {
                    val ns = "com.cyberj812.boardgamesnap.${project.name.replace(":", ".")}"
                    val cur = ext.javaClass.getMethod("getNamespace").invoke(ext)
                    if (cur == null) {
                        ext.javaClass.getMethod("setNamespace", String::class.java).invoke(ext, ns)
                    }
                } catch (_: Exception) {}
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
