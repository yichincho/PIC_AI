"""Generate Android wrapper with stable package and release signing."""
from pathlib import Path
import tempfile, shutil, subprocess, re
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    target=Path(tmp)/"pic_ai"
    subprocess.run(["flutter","create","--platforms=android","--org","com.yichincho","--project-name","pic_ai",str(target)],check=True)
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
s=s.replace("<application",\'<application android:allowBackup="false"\',1) if "android:allowBackup" not in s else s
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

print("Android wrapper ready. Use stable release key for installable APKs.")
