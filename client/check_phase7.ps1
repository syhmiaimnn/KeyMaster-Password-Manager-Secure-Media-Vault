# KeyMaster - Phase 7 check
#
# What it does: looks at your project, tells you which Phase 7 files are
# missing, saved under a wrong name, or still the old version, checks that the
# camera package and the camera permission are in place, runs "flutter
# analyze" and all the tests (the four new test files are the Phase 7 ones),
# and lists every problem. It changes nothing.
#
# How to run it (Terminal in VS Code, inside the client folder):
#   powershell -ExecutionPolicy Bypass -File .\check_phase7.ps1
#
# It writes phase7_report.txt (short), phase7_analyze.txt (full analyzer
# output) and phase7_test.txt (test output) next to pubspec.yaml.

$report = New-Object System.Collections.Generic.List[string]

function Say {
    param([string]$Text, [string]$Color = 'White')
    Write-Host $Text -ForegroundColor $Color
    $report.Add($Text)
}

function Rel {
    param([string]$Full)
    $root = (Get-Location).Path
    if ($Full.StartsWith($root)) { return $Full.Substring($root.Length).TrimStart('\', '/') }
    return $Full
}

if (-not (Test-Path 'pubspec.yaml')) {
    Write-Host 'Run this inside the client folder (the one that contains pubspec.yaml).' -ForegroundColor Red
    exit 1
}

# Each Phase 7 file, and words that are only in the NEW version of it.
$checks = @(
    @{ Path = 'lib/vault_slot.dart';                   Markers = @('enum VaultSlot', 'class SlotFiller') },
    @{ Path = 'lib/sealed_box.dart';                   Markers = @('class SealedBox', 'X25519') },
    @{ Path = 'lib/intruder_payload.dart';             Markers = @('class IntruderPayload', 'static IntruderPayload unpack') },
    @{ Path = 'lib/decoy_seed.dart';                   Markers = @('class DecoySeed', 'example.com') },
    @{ Path = 'lib/intruder_service.dart';             Markers = @('class IntruderService', 'CameraController') },
    @{ Path = 'lib/decoy_screen.dart';                 Markers = @('class DecoyScreen', 'class DecoyPinScreen') },
    @{ Path = 'lib/intruder_log_screen.dart';          Markers = @('class IntruderLogScreen', 'Take a test photo') },
    @{ Path = 'lib/security_service.dart';             Markers = @('setDecoyPin', '_checkBothSlots') },
    @{ Path = 'lib/crypto_service.dart';               Markers = @('benchmarkKeyDerivation', 'int parallel = 1') },
    @{ Path = 'lib/unlock_screen.dart';                Markers = @('_maybeTakeIntruderPhoto') },
    @{ Path = 'lib/settings_screen.dart';              Markers = @("title: 'Decoy vault'", 'IntruderLogScreen') },
    @{ Path = 'lib/app_settings.dart';                 Markers = @('intruderOn', 'setIntruderOn') },
    @{ Path = 'lib/media_vault_service.dart';          Markers = @('ensureDirectories', 'clearSlot') },
    @{ Path = 'lib/wipe_service.dart';                 Markers = @('IntruderService.deleteAllFiles', 'MediaVaultService.deleteAllFiles') },
    @{ Path = 'lib/home_shell.dart';                   Markers = @('_announceIntruders', '_prepareStorage') },
    @{ Path = 'lib/change_pin_screen.dart';            Markers = @('PinNotAllowedException') },
    @{ Path = 'lib/recover_access_screen.dart';        Markers = @('PinNotAllowedException') },
    @{ Path = 'lib/about_screen.dart';                 Markers = @("'Intruder photo'", "'Decoy vault'") },
    @{ Path = 'test/sealed_box_test.dart';             Markers = @('SealedBox', 'changing any single byte') },
    @{ Path = 'test/intruder_payload_test.dart';       Markers = @('IntruderPayload', 'damaged data is refused') },
    @{ Path = 'test/vault_slot_test.dart';             Markers = @('SlotFiller', 'slot flags') },
    @{ Path = 'test/decoy_seed_test.dart';             Markers = @('DecoySeed', 'reserved example domains') }
)

$problems = 0
Say '== 1. Are the Phase 7 files in place? ==' 'Cyan'

foreach ($c in $checks) {
    $path = $c.Path
    if (-not (Test-Path $path)) {
        $problems++
        Say ("MISSING     " + $path) 'Red'
        $hit = Get-ChildItem -Path 'lib', 'test' -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch $c.Markers[0] -List |
            Select-Object -First 1
        if ($hit) {
            Say ("            the code is saved as " + (Rel $hit.Path) + " -> rename that file to " + (Split-Path $path -Leaf) + " (same folder: " + (Split-Path $path -Parent) + ")") 'Yellow'
        }
        continue
    }
    $text = Get-Content -Raw -Path $path
    if ($null -eq $text) { $text = '' }
    $absent = @()
    foreach ($m in $c.Markers) {
        if (-not $text.Contains($m)) { $absent += $m }
    }
    if ($absent.Count -gt 0) {
        $problems++
        Say ("OLD/BROKEN  " + $path + "  (does not contain: " + ($absent -join ', ') + ")") 'Red'
        Say '            -> paste the whole new file again, from the first line to the last.' 'Yellow'
    }
    else {
        Say ("ok          " + $path) 'Green'
    }
}

# The same file name twice (for example one copy in lib and one in a sub-folder)
$dups = Get-ChildItem -Path 'lib', 'test' -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue |
    Group-Object Name | Where-Object { $_.Count -gt 1 }
foreach ($d in $dups) {
    $problems++
    Say ("DUPLICATE   " + $d.Name + " exists in " + (($d.Group | ForEach-Object { Rel $_.DirectoryName }) -join '  AND  ')) 'Red'
}

# Dart files that are not part of the project (typos in the name, copies)
$odd = Get-ChildItem -Path 'lib' -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '(copy|\(\d+\)|_text\.dart$|_old|_new|backup)' }
foreach ($o in $odd) {
    Say ("SUSPICIOUS  " + $o.Name + " looks like a copy or a typo. Delete it if you do not need it.") 'Yellow'
}

Say ''
if ($problems -eq 0) {
    Say 'All Phase 7 files are in place.' 'Green'
}
else {
    Say ("$problems problem(s) found in step 1. Fix these first, then run this check again.") 'Yellow'
}


# The camera package and the camera permission (the intruder photo needs both)
Say ''
Say '== 2. Camera package and permission ==' 'Cyan'
$cameraProblems = 0

$pubspec = Get-Content -Raw -Path 'pubspec.yaml'
if ($null -eq $pubspec) { $pubspec = '' }
if ($pubspec -match '(?m)^\s+camera:') {
    Say 'ok          camera package is in pubspec.yaml' 'Green'
}
else {
    $cameraProblems++
    Say 'MISSING     the camera package is not in pubspec.yaml' 'Red'
    Say '            -> run:  flutter pub add camera' 'Yellow'
}

$manifestPath = 'android/app/src/main/AndroidManifest.xml'
if (-not (Test-Path $manifestPath)) {
    $cameraProblems++
    Say ("MISSING     " + $manifestPath) 'Red'
}
else {
    $manifest = Get-Content -Raw -Path $manifestPath
    if ($null -eq $manifest) { $manifest = '' }
    if ($manifest.Contains('android.permission.CAMERA')) {
        Say 'ok          the CAMERA permission is in AndroidManifest.xml' 'Green'
    }
    else {
        $cameraProblems++
        Say 'MISSING     the CAMERA permission is not in AndroidManifest.xml' 'Red'
        Say '            -> run:  powershell -ExecutionPolicy Bypass -File .\add_camera_permission.ps1' 'Yellow'
    }
}
$problems += $cameraProblems
if ($cameraProblems -eq 0) {
    Say 'The camera package and permission are in place.' 'Green'
}

# flutter analyze
Say ''
Say '== 3. What does the analyzer say? ==' 'Cyan'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Say 'flutter was not found in this terminal. Open the terminal inside VS Code and run again.' 'Red'
}
else {
    Say 'Running flutter pub get ...'
    flutter pub get 2>&1 | Out-Null
    Say 'Running flutter analyze (about 30 seconds) ...'
    $out = @(flutter analyze --no-pub 2>&1 | ForEach-Object { $_.ToString() })
    Set-Content -Path 'phase7_analyze.txt' -Value $out -Encoding UTF8

    $errors = @($out | Where-Object { $_ -match '^\s*error\b' })
    $warnings = @($out | Where-Object { $_ -match '^\s*warning\b' })
    $infos = @($out | Where-Object { $_ -match '^\s*info\b' })

    Say ("errors: " + $errors.Count + "    warnings: " + $warnings.Count + "    infos: " + $infos.Count)
    $shown = 0
    foreach ($e in $errors) {
        if ($shown -ge 40) { Say '... (more in phase7_analyze.txt)'; break }
        Say $e.Trim() 'Red'
        $shown++
    }
    foreach ($w in ($warnings | Select-Object -First 15)) {
        Say $w.Trim() 'Yellow'
    }
    if ($errors.Count -eq 0) {
        Say 'The analyzer found no errors.' 'Green'
    }
}

# flutter test (all tests, about a minute)
Say ''
Say '== 4. Do the tests pass? ==' 'Cyan'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Say 'flutter was not found, so the tests were skipped.' 'Red'
}
else {
    Say 'Running all the tests, including the sealed box, payload, slot and decoy tests ...'
    $t = @(flutter test 2>&1 | ForEach-Object { $_.ToString() })
    Set-Content -Path 'phase7_test.txt' -Value $t -Encoding UTF8

    $failed = @($t | Where-Object { $_ -match '\[E\]' })
    $last = ($t | Where-Object { $_ -match 'All tests passed|Some tests failed|Error:' } | Select-Object -Last 1)
    if ($last -and $last -match 'All tests passed') {
        Say 'All the tests passed.' 'Green'
    }
    else {
        Say 'The tests did not all pass. The first problems:' 'Red'
        $shown = 0
        foreach ($line in $t) {
            if ($line -match '\[E\]|Expected:|Actual:|Error:|reason') {
                if ($shown -ge 25) { break }
                Say $line.Trim() 'Red'
                $shown++
            }
        }
        if ($shown -eq 0 -and $t.Count -gt 0) {
            foreach ($line in ($t | Select-Object -Last 15)) { Say $line.Trim() 'Red' }
        }
    }
}

Set-Content -Path 'phase7_report.txt' -Value $report -Encoding UTF8
Write-Host ''
if (Test-Path 'phase7_analyze.txt') {
    Write-Host 'Saved phase7_report.txt, phase7_analyze.txt and phase7_test.txt in this folder.' -ForegroundColor Cyan
}
else {
    Write-Host 'Saved phase7_report.txt in this folder.' -ForegroundColor Cyan
}
Write-Host 'If something is still red, send me phase7_report.txt.' -ForegroundColor Cyan
