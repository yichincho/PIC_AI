"""Generate Android wrapper with stable package and release signing."""
from pathlib import Path
import tempfile, shutil, subprocess, re
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    target=Path(tmp)/"pic_ai"
    subprocess.run(["flutter","create","--no-pub","--platforms=android","--org","com.yichincho","--project-name","pic_ai",str(target)],check=True)
    for platform in ("android",):
        if not (root/platform).exists():
            shutil.copytree(target/platform,root/platform)
manifest=root/"android/app/src/main/AndroidManifest.xml"
s=manifest.read_text()
permissions="""<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
    <uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>"""
if "READ_MEDIA_IMAGES" not in s:
    s=s.replace("<application",permissions+"\n    <application",1)
s=s.replace("<application", '<application android:allowBackup="false"', 1) if "android:allowBackup" not in s else s
manifest.write_text(s)
for gradle in (root/"android/app/build.gradle.kts",root/"android/app/build.gradle"):
    if gradle.exists():
        s=gradle.read_text().replace("minSdk = flutter.minSdkVersion","minSdk = 28").replace("minSdkVersion flutter.minSdkVersion","minSdkVersion 28")
        if gradle.suffix != ".kts":
            raise RuntimeError("Expected Kotlin Gradle template")
        s=re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.yichincho.pic_ai"',s)
        if "PIC_AI_KEYSTORE" not in s:
            marker="    buildTypes {"
            if marker not in s: raise RuntimeError("Unsupported Gradle template")
            s=s.replace(marker,'''    signingConfigs {
        create("picAiRelease") {
            val keyPath = System.getenv("PIC_AI_KEYSTORE")
            if (!keyPath.isNullOrBlank()) {
                storeFile = file(keyPath)
                storePassword = System.getenv("PIC_AI_STORE_PASSWORD")
                keyAlias = System.getenv("PIC_AI_KEY_ALIAS")
                keyPassword = System.getenv("PIC_AI_KEY_PASSWORD")
            }
        }
    }
'''+marker,1)
            old='signingConfig = signingConfigs.getByName("debug")'
            if old not in s: raise RuntimeError("Missing signing marker")
            s=s.replace(old,'signingConfig = signingConfigs.getByName("picAiRelease")')
        gradle.write_text(s)

# Third-party plugins (e.g. tflite_flutter) compile Java at 1.8 while Kotlin targets 17,
# which fails Gradle's JVM-target validation. Downgrade it to a warning; the bytecode is
# fine for minSdk 28.
props=root/"android/gradle.properties"
prop_line="kotlin.jvm.target.validation.mode=warning"
current=props.read_text() if props.exists() else ""
if prop_line not in current.splitlines():
    if current and not current.endswith("\n"):
        current+="\n"
    props.write_text(current+prop_line+"\n")

# Transitive TFLite 2.11 artifacts (via tflite_flutter) share namespace org.tensorflow.lite,
# which new AGP rejects. Pin them to 2.16.1 in the root project, once.
root_gradle=root/"android/build.gradle.kts"
if not root_gradle.exists(): raise RuntimeError("Missing android/build.gradle.kts")
root_text=root_gradle.read_text()
if "PIC_AI_TFLITE_PIN" not in root_text:
    if root_text and not root_text.endswith("\n"):
        root_text+="\n"
    root_text+="""
// PIC_AI_TFLITE_PIN: TFLite 2.11 artifacts share namespace org.tensorflow.lite, which new AGP rejects.
subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.tensorflow" && requested.name.startsWith("tensorflow-lite")) {
                useVersion("2.16.1")
                because("TFLite 2.11 namespace collision under new AGP")
            }
        }
    }
}
"""
    root_gradle.write_text(root_text)

# Some plugins (tflite_flutter) still compile against android-31, but their androidx
# dependencies need compileSdk >= 34. Raise only those at build time; minSdk/targetSdk
# of the app are unchanged. state.executed guard: the template's evaluationDependsOn(":app")
# may already have evaluated some projects.
root_text=root_gradle.read_text()
if "PIC_AI_PLUGIN_COMPILESDK" not in root_text:
    if not root_text.endswith("\n"):
        root_text+="\n"
    root_text+="""
// PIC_AI_PLUGIN_COMPILESDK: some plugins (tflite_flutter) still compile against android-31.
subprojects {
    if (!project.state.executed) {
        project.afterEvaluate {
            project.extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let { lib ->
                if ((lib.compileSdk ?: 0) < 34) {
                    lib.compileSdk = 36
                }
            }
        }
    }
}
"""
    root_gradle.write_text(root_text)

print("Android wrapper ready. Use stable release key for installable APKs.")
