<#
    My Day Buddy - Android toolchain setup + Capacitor project prep
    ---------------------------------------------------------------
    Run it as many times as you like. It checks what is already done
    and only does the next missing thing.

    Usage:  right-click -> Run with PowerShell
       or:  powershell -ExecutionPolicy Bypass -File .\setup-mydaybuddy-android.ps1

    It never touches your keystore and never asks for a password.
#>

$ErrorActionPreference = 'Stop'

$Zip        = "$env:USERPROFILE\Downloads\mydaybuddy-capacitor.zip"
$BuildRoot  = "$env:USERPROFILE\Downloads\mydaybuddy-build"
$Proj       = "$BuildRoot\daybook-capacitor"
$StudioJbr  = $null   # discovered below - Studio can be installed anywhere
$Sdk        = "$env:LOCALAPPDATA\Android\Sdk"

$VersionCode = 2
$VersionName = '1.1'
$CapMajor    = 8      # Capacitor 8 => compileSdk/targetSdk 36, which Play now requires

function Say  ($m) { Write-Host "  $m" }
function Step ($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host ""; Write-Host "STOPPED: $m" -ForegroundColor Red; Write-Host ""; Read-Host "Press Enter to close"; exit 1 }

function Have ($exe) { return [bool](Get-Command $exe -ErrorAction SilentlyContinue) }

# Native programs (winget, npm, sdkmanager) write ordinary warnings to stderr.
# With ErrorActionPreference = Stop, PowerShell turns any of those into a fatal
# NativeCommandError. Merge stderr into stdout inside cmd so PowerShell never
# sees a separate error stream, and relax the preference for the duration.
# PowerShell 5.1's Set-Content -Encoding UTF8 writes a BYTE ORDER MARK. Groovy and
# Gradle choke on it with "Unexpected character: '"'" on line 1, and the mark is
# invisible in every editor, so it looks like a mystery. Always write these files
# BOM-free.
function Write-TextNoBom ($path, $text) {
    [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Invoke-Native ($cmdline) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & cmd /c "$cmdline 2>&1" | ForEach-Object { Say $_ }
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

function Find-StudioHome {
    # Android Studio can be installed anywhere. Look in the usual places,
    # then ask the registry, then sweep the drive roots as a last resort.
    $cands = @(
        "C:\Program Files\Android\Android Studio",
        "C:\Program Files\Android Studio",
        "C:\Program Files\Google\Android Studio",
        "$env:LOCALAPPDATA\Programs\Android Studio",
        "$env:LOCALAPPDATA\Programs\Android\Android Studio",
        "C:\android sdk"
    )
    foreach ($k in @('HKLM:\SOFTWARE\Android Studio','HKLM:\SOFTWARE\WOW6432Node\Android Studio')) {
        try {
            $v = (Get-ItemProperty -Path $k -ErrorAction Stop).Path
            if ($v) { $cands += $v }
        } catch { }
    }
    try {
        $lnk = Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Filter 'Android Studio*.lnk' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) {
            $sh = New-Object -ComObject WScript.Shell
            $t = $sh.CreateShortcut($lnk.FullName).TargetPath
            if ($t) { $cands += (Split-Path (Split-Path $t -Parent) -Parent) }
        }
    } catch { }
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c 'jbr\bin\java.exe'))) { return $c }
    }
    # last resort: shallow sweep of drive roots
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
        $hit = Get-ChildItem $drive.Root -Directory -ErrorAction SilentlyContinue |
               Where-Object { Test-Path (Join-Path $_.FullName 'jbr\bin\java.exe') } |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function WingetInstall ($id, $label) {
    Say "installing $label (this can take a while - it is a big download)"
    $code = Invoke-Native "winget install --id $id -e --accept-package-agreements --accept-source-agreements --disable-interactivity"
    if ($code -ne 0 -and $code -ne -1978335189) {
        Die "winget could not install $label (exit $code). Install it by hand and re-run this script."
    }
}

Write-Host ""
Write-Host "My Day Buddy - Android build setup" -ForegroundColor White
Write-Host "----------------------------------"

# ---------------------------------------------------------------- 0. sanity
Step "Checking prerequisites"
if (-not (Have 'winget')) { Die "winget is missing. Update 'App Installer' from the Microsoft Store, then re-run." }
if (-not (Test-Path $Zip)) { Die "Cannot find $Zip - put mydaybuddy-capacitor.zip in your Downloads folder." }
Ok "winget present"
Ok "found mydaybuddy-capacitor.zip"

# ---------------------------------------------------------------- 1. Node.js
Step "Node.js"
if (Have 'node') {
    Ok ("already installed: " + (node -v))
} else {
    WingetInstall 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    if (Have 'node') { Ok ("installed: " + (node -v)) }
    else { Warn "Node installed but not on PATH yet - close this window, open a NEW PowerShell, re-run this script." ; exit 0 }
}

# ---------------------------------------------------------------- 2. Android Studio
Step "Android Studio (brings JDK 21 + the Android SDK)"
$studioHome = Find-StudioHome
if (-not $studioHome) {
    WingetInstall 'Google.AndroidStudio' 'Android Studio'
    $studioHome = Find-StudioHome
}
if (-not $studioHome) {
    Write-Host ""
    Warn "Android Studio is installed, but this script cannot find where."
    Say  "Open Android Studio -> Help -> About. The install path is listed there."
    $studioHome = (Read-Host "Paste the Android Studio folder (the one containing 'jbr')").Trim('"').TrimEnd('\')
    if (-not (Test-Path (Join-Path $studioHome 'jbr\bin\java.exe'))) { Die "No jbr\bin\java.exe under '$studioHome'." }
}
$StudioJbr = Join-Path $studioHome 'jbr'
Ok "found at $studioHome"

# ---------------------------------------------------------------- 3. SDK (needs the first-run wizard)
Step "Android SDK"
if (-not (Test-Path "$Sdk\platform-tools")) {
    Warn "The SDK is not downloaded yet. This part cannot be automated."
    Write-Host ""
    Write-Host "  Do this now:" -ForegroundColor Yellow
    Write-Host "    1. Open Android Studio from the Start menu."
    Write-Host "    2. Accept the defaults in the Setup Wizard and let it download."
    Write-Host "       (Standard install is fine. It fetches ~2-3 GB.)"
    Write-Host "    3. When you reach the Welcome screen, close Android Studio."
    Write-Host "    4. Re-run this script. It will pick up from here."
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 0
}
Ok "SDK found at $Sdk"

# ---------------------------------------------------------------- 4. env vars
Step "Environment variables (JAVA_HOME / ANDROID_HOME)"
[Environment]::SetEnvironmentVariable('JAVA_HOME',    $StudioJbr, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $Sdk,       'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $Sdk,   'User')
$env:JAVA_HOME = $StudioJbr; $env:ANDROID_HOME = $Sdk; $env:ANDROID_SDK_ROOT = $Sdk

$userPath = [Environment]::GetEnvironmentVariable('Path','User')
foreach ($p in @("$Sdk\platform-tools", "$Sdk\cmdline-tools\latest\bin")) {
    if (Test-Path $p) {
        if ($userPath -notlike "*$p*") {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$p", 'User')
            $userPath = "$userPath;$p"
            Say "added to PATH: $p"
        }
    }
}
$env:Path = "$env:Path;$Sdk\platform-tools;$Sdk\cmdline-tools\latest\bin"
Ok "JAVA_HOME = $StudioJbr"
Ok "ANDROID_HOME = $Sdk"

# ---------------------------------------------------------------- 5. SDK licences
Step "SDK licences"
# Best effort only. The Studio setup wizard already accepts these, and newer
# SDKs deprecate sdkmanager, so a failure here is not worth stopping for.
if (Test-Path "$Sdk\licenses") {
    Ok "licence files already present (accepted by the Studio wizard)"
} else {
    $sdkmanager = Get-ChildItem -Path "$Sdk\cmdline-tools" -Filter 'sdkmanager.bat' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sdkmanager) {
        try {
            $yfile = Join-Path $env:TEMP 'mdb-sdk-yes.txt'
            ("y`r`n" * 60) | Set-Content $yfile -Encoding ASCII
            Invoke-Native "`"$($sdkmanager.FullName)`" --licenses < `"$yfile`"" | Out-Null
            Remove-Item $yfile -ErrorAction SilentlyContinue
            Ok "licences accepted"
        } catch {
            Warn "could not run sdkmanager - carrying on. If Gradle complains about licences later, accept them in Android Studio > SDK Manager."
        }
    } else {
        Warn "sdkmanager not found - carrying on. If Gradle complains about licences later, accept them in Android Studio > SDK Manager."
    }
}

# ---------------------------------------------------------------- 6. unpack project
Step "Unpacking the Capacitor project"
if (Test-Path "$Proj\package.json") {
    Ok "already unpacked at $Proj"
} else {
    New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $BuildRoot -Force
    if (-not (Test-Path "$Proj\package.json")) { Die "Unpacked, but $Proj\package.json is missing. Check the zip." }
    Ok "unpacked to $Proj"
}

# ---------------------------------------------------------------- 7. pin Capacitor 8
Step "Pinning Capacitor $CapMajor (target SDK 36 - Play's current requirement)"
$pkgPath = "$Proj\package.json"
$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
$changed = $false
foreach ($dep in @('@capacitor/core','@capacitor/android','@capacitor/local-notifications')) {
    if ($pkg.dependencies.$dep -ne "^$CapMajor.0.0") { $pkg.dependencies.$dep = "^$CapMajor.0.0"; $changed = $true }
}
if ($pkg.devDependencies.'@capacitor/cli' -ne "^$CapMajor.0.0") { $pkg.devDependencies.'@capacitor/cli' = "^$CapMajor.0.0"; $changed = $true }
if ($changed) {
    Write-TextNoBom $pkgPath ($pkg | ConvertTo-Json -Depth 10)
    if (Test-Path "$Proj\node_modules") { Remove-Item "$Proj\node_modules" -Recurse -Force }
    if (Test-Path "$Proj\package-lock.json") { Remove-Item "$Proj\package-lock.json" -Force }
    if (Test-Path "$Proj\android") {
        Rename-Item "$Proj\android" ("android-old-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Say "moved the old android/ folder aside so it gets regenerated at API 36"
    }
    Ok "package.json now asks for Capacitor $CapMajor"
} else {
    Ok "already on Capacitor $CapMajor"
}

# ---------------------------------------------------------------- 8. npm install
Step "Installing npm dependencies"
Push-Location $Proj
try {
    if (-not (Test-Path "$Proj\node_modules\@capacitor\cli")) {
        $code = Invoke-Native "npm install"
        if ($code -ne 0) { Die "npm install failed. Scroll up for the reason." }
    }
    Ok "dependencies installed"

    # ------------------------------------------------------------ 9. android platform
    Step "Generating the native Android project"
    if (-not (Test-Path "$Proj\android\app\build.gradle")) {
        Invoke-Native "npx --no-install cap add android" | Out-Null
        if (-not (Test-Path "$Proj\android\app\build.gradle")) { Die "'cap add android' did not produce android\app\build.gradle." }
        Ok "android/ created"
    } else {
        Ok "android/ already there"
    }

    Invoke-Native "npx --no-install cap sync android" | Out-Null
    Ok "web assets synced"
}
finally { Pop-Location }

# ---------------------------------------------------------------- 10. notification icons
Step "Notification icons"
$src = "$Proj\notification-icon"
$dst = "$Proj\android\app\src\main\res"
if (Test-Path $src) {
    Get-ChildItem $src -Directory | ForEach-Object {
        $target = Join-Path $dst $_.Name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item "$($_.FullName)\*" $target -Force
    }
    $n = (Get-ChildItem $dst -Recurse -Filter 'ic_stat_daybook.png' | Measure-Object).Count
    Ok "ic_stat_daybook.png in place at $n densities"
} else {
    Warn "no notification-icon folder in the zip - status bar icon will be a grey blob"
}

# ---------------------------------------------------------------- 11. version code
Step "Version code / name"
$gradle = "$Proj\android\app\build.gradle"
$g = Get-Content $gradle -Raw
$g = [regex]::Replace($g, 'versionCode\s+\d+',        "versionCode $VersionCode")
$g = [regex]::Replace($g, 'versionName\s+"[^"]*"',    "versionName `"$VersionName`"")
Write-TextNoBom $gradle $g
Ok "versionCode $VersionCode / versionName $VersionName"

# strip any BOM left on the gradle files by an earlier run of this script
foreach ($f in @($gradle, "$Proj\android\variables.gradle", "$Proj\android\build.gradle")) {
    if (Test-Path $f) {
        $bytes = [IO.File]::ReadAllBytes($f)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            [IO.File]::WriteAllBytes($f, $bytes[3..($bytes.Length - 1)])
            Say "removed a UTF-8 BOM from $(Split-Path $f -Leaf)"
        }
    }
}

# ---------------------------------------------------------------- 12. verify
Step "Verifying"
$vars = Get-Content "$Proj\android\variables.gradle" -Raw
$target  = ([regex]::Match($vars, 'targetSdkVersion\s*=\s*(\d+)')).Groups[1].Value
$compile = ([regex]::Match($vars, 'compileSdkVersion\s*=\s*(\d+)')).Groups[1].Value
$appId   = ([regex]::Match((Get-Content $gradle -Raw), 'applicationId\s+"([^"]+)"')).Groups[1].Value

Write-Host ""
Write-Host "  applicationId     $appId"      -ForegroundColor White
Write-Host "  versionCode       $VersionCode" -ForegroundColor White
Write-Host "  compileSdk        $compile"    -ForegroundColor White
Write-Host "  targetSdk         $target"     -ForegroundColor White
Write-Host ""

$fail = $false
if ($appId  -ne 'io.github.gauravvdev.daybook') { Warn "applicationId is NOT io.github.gauravvdev.daybook - Play will treat this as a different app"; $fail = $true }
if ($target -ne '36') { Warn "targetSdk is $target, but Play has required 36 since 31 Aug 2026 - the upload will be rejected"; $fail = $true }

$manifest = Get-Content "$Proj\android\app\src\main\AndroidManifest.xml" -Raw
foreach ($perm in @('POST_NOTIFICATIONS','RECEIVE_BOOT_COMPLETED','SCHEDULE_EXACT_ALARM')) {
    if ($manifest -match $perm) { Ok "permission $perm present" }
    else { Warn "permission $perm missing from AndroidManifest.xml (the plugin usually merges it in at build time - check the merged manifest in Android Studio)" }
}
if ($manifest -match 'USE_EXACT_ALARM') { Warn "USE_EXACT_ALARM is declared - REMOVE IT. Google restricts it to alarm-clock and calendar apps; on a tracker it is a rejection risk." }

# ---------------------------------------------------------------- done
Write-Host ""
if ($fail) { Write-Host "Setup finished WITH WARNINGS - read them above before building." -ForegroundColor Yellow }
else       { Write-Host "Setup complete." -ForegroundColor Green }
Write-Host ""
Write-Host "Next, by hand:" -ForegroundColor White
Write-Host "  1. Open the project in Android Studio:"
Write-Host "       cd `"$Proj`"  then  npx cap open android"
Write-Host "     (first open takes several minutes while Gradle downloads)"
Write-Host "  2. Build > Generate Signed App Bundle / APK > Android App Bundle"
Write-Host "  3. Choose EXISTING keystore -> signing.keystore from Daybook-Play-Package.zip"
Write-Host "     Build variant: release"
Write-Host "  4. The .aab lands in android\app\release\"
Write-Host "  5. TEST BEFORE UPLOADING: set a reminder 3 minutes out, swipe the app"
Write-Host "     away from recents, lock the phone. The notification must still arrive."
Write-Host "  6. Play Console > Closed testing > new release > upload."
Write-Host ""
Read-Host "Press Enter to close"
