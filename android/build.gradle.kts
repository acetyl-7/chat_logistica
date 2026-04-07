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
    val rootDirAbs = rootProject.rootDir.absolutePath
    val projectDirAbs = project.projectDir.absolutePath
    if (!rootDirAbs.contains(":\\") ||
        rootDirAbs.substringBefore(":\\").equals(projectDirAbs.substringBefore(":\\"), ignoreCase = true)
    ) {
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
