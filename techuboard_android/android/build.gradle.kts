import java.io.File
import org.gradle.api.plugins.ExtensionAware

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    if (project.name != "app") {
        project.ext.set("flutter", mapOf(
            "compileSdkVersion" to 35,
            "minSdkVersion" to 24,
            "targetSdkVersion" to 35,
            "ndkVersion" to "27.0.12077973"
        ))
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
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            
            if ((android as? ExtensionAware)?.extensions?.findByName("flutter") == null) {
                (android as? ExtensionAware)?.extensions?.add("flutter", mapOf(
                    "compileSdkVersion" to 35,
                    "minSdkVersion" to 24,
                    "targetSdkVersion" to 35,
                    "ndkVersion" to "27.0.12077973"
                ))
            }

            if (android.compileSdkVersion == null) {
                android.compileSdkVersion("android-35")
            }

            val manifestFile = android.sourceSets.getByName("main").manifest.srcFile
            if (manifestFile.exists()) {
                val manifestContents = manifestFile.readText()
                val packageMatch = Regex("package=\"([^\"]+)\"").find(manifestContents)
                
                if (packageMatch != null) {
                    val packageName = packageMatch.groupValues[1]
                    
                    if (android.namespace == null) {
                        android.namespace = packageName
                    }
                    
                    val tempDir = File(project.layout.buildDirectory.get().asFile, "intermediates/fixed_manifests/${project.name}")
                    if (!tempDir.exists()) tempDir.mkdirs()
                    
                    val fixedManifest = File(tempDir, "AndroidManifest.xml")
                    val cleanContent = manifestContents.replace(Regex("package=\"[^\"]+\""), "")
                    fixedManifest.writeText(cleanContent)
                    
                    android.sourceSets.getByName("main").manifest.srcFile(fixedManifest)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
