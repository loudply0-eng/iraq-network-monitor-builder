allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        val androidExtension = extensions.findByName("android")

        if (androidExtension != null) {
            val compileSdkSetter = androidExtension.javaClass.methods
                .filter {
                    (it.name == "setCompileSdk" ||
                     it.name == "setCompileSdkVersion") &&
                    it.parameterCount == 1
                }
                .firstOrNull {
                    it.name == "setCompileSdk" &&
                    (it.parameterTypes[0] == Integer.TYPE ||
                     it.parameterTypes[0] == Integer::class.java)
                }
                ?: androidExtension.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdkVersion" &&
                    it.parameterCount == 1 &&
                    it.parameterTypes[0] == String::class.java
                }
                ?: throw GradleException(
                    "Could not find a compatible compileSdk setter for ${project.path}"
                )

            val compileSdkValue: Any =
                if (compileSdkSetter.parameterTypes[0] == String::class.java) "35" else 35

            compileSdkSetter.invoke(androidExtension, compileSdkValue)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
