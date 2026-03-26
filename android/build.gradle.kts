allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val rootBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(rootBuildDir)

project(":app") {
    layout.buildDirectory.value(rootBuildDir.dir("app"))
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
