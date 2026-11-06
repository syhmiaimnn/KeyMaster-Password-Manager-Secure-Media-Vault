# KeyMaster - Phase 7: add the camera permission
#
# What it does: adds the CAMERA permission to
# android/app/src/main/AndroidManifest.xml. The intruder photo needs it.
# If the permission is already there, it does nothing. Before it changes
# anything it saves a copy of the file as AndroidManifest.xml.bak-phase7.
#
# How to run it (Terminal in VS Code, inside the client folder):
#   powershell -ExecutionPolicy Bypass -File .\add_camera_permission.ps1

$relative = 'android/app/src/main/AndroidManifest.xml'

if (-not (Test-Path 'pubspec.yaml')) {
    Write-Host 'Run this inside the client folder (the one that contains pubspec.yaml).' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $relative)) {
    Write-Host ("Cannot find " + $relative) -ForegroundColor Red
    exit 1
}

$full = (Resolve-Path $relative).Path
$text = [System.IO.File]::ReadAllText($full)

if ($text.Contains('android.permission.CAMERA')) {
    Write-Host 'The CAMERA permission is already in AndroidManifest.xml. Nothing to do.' -ForegroundColor Green
    exit 0
}

# Keep the file's own line endings (Windows files use CR+LF).
$nl = "`n"
if ($text.Contains("`r`n")) { $nl = "`r`n" }

# The permission goes inside <manifest>, just before <application>.
$match = [regex]::Match($text, '(?m)^([ \t]*)<application\b')
if (-not $match.Success) {
    Write-Host 'Could not find the <application> line in AndroidManifest.xml.' -ForegroundColor Red
    Write-Host 'Add these lines by hand, inside <manifest> and above <application>:' -ForegroundColor Yellow
    Write-Host '    <uses-permission android:name="android.permission.CAMERA" />'
    Write-Host '    <uses-feature android:name="android.hardware.camera" android:required="false" />'
    exit 1
}

$indent = $match.Groups[1].Value
$add = $indent + '<uses-permission android:name="android.permission.CAMERA" />' + $nl +
       $indent + '<uses-feature android:name="android.hardware.camera" android:required="false" />' + $nl +
       $indent + '<uses-feature android:name="android.hardware.camera.front" android:required="false" />' + $nl

$backup = $full + '.bak-phase7'
if (-not (Test-Path $backup)) { Copy-Item -Path $full -Destination $backup }

$new = $text.Insert($match.Index, $add)
# UTF-8 without a byte order mark, the way Android Studio saves it.
[System.IO.File]::WriteAllText($full, $new, (New-Object System.Text.UTF8Encoding($false)))

Write-Host 'Added the CAMERA permission to AndroidManifest.xml.' -ForegroundColor Green
Write-Host ('A copy of the old file is saved as ' + $relative + '.bak-phase7') -ForegroundColor Cyan
Write-Host 'Stop "flutter run" and start it again, so the new permission is built into the app.' -ForegroundColor Cyan
