buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Classpath ya Google Services kwa ajili ya Firebase
        classpath("com.google.gms:google-services:4.4.1")
    }
}

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

// FIX: flutter_webrtc (na plugins nyingine za zamani) zimeandaliwa kwa
// compileSdk 31, lakini dependencies zake za androidx (fragment, lifecycle,
// core-ktx n.k.) zinahitaji compileSdk 34+. Bila hii, task ya
// checkDebugAarMetadata inafail na "requires libraries ... compiled against
// version 34 or later".
fun Project.forceMinCompileSdk(minSdkLevel: Int) {
    val applySdk: () -> Unit = {
        val ext = extensions.findByName("android")
        if (ext is com.android.build.gradle.LibraryExtension) {
            val current = ext.compileSdk
            if (current != null && current < minSdkLevel) {
                ext.compileSdk = minSdkLevel
            }
        }
    }
    if (state.executed) {
        applySdk()
    } else {
        afterEvaluate { applySdk() }
    }
}

subprojects {
    forceMinCompileSdk(34)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}