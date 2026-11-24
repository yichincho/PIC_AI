"""Generate Flutter native wrappers without replacing app source."""
from pathlib import Path
import tempfile, shutil, subprocess, plistlib
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    target=Path(tmp)/"pic_ai"
    subprocess.run(["flutter","create","--platforms=android,ios","--org","com.yichincho","--project-name","pic_ai",str(target)],check=True)
    for platform in ("android","ios"):
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
        gradle.write_text(s)
plist=root/"ios/Runner/Info.plist"
with plist.open("rb") as f: data=plistlib.load(f)
data["NSPhotoLibraryUsageDescription"]="PIC_AI 只在本機建立照片搜尋索引。"
with plist.open("wb") as f: plistlib.dump(data,f)
pbx=root/"ios/Runner.xcodeproj/project.pbxproj"
s=pbx.read_text()
import re
s=re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;",s)
pbx.write_text(s)
pod=root/"ios/Podfile"
if pod.exists():
    s=pod.read_text()
    s=re.sub(r"(?m)^#?\s*platform :ios, .*","platform :ios, '15.5'",s)
    pod.write_text(s)
print("Platform wrappers generated. Run flutter pub get.")
