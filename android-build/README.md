# android-build — how My Day Buddy becomes an Android app

The web app in the repo root is the whole product. This folder is only the
shell that wraps it for Google Play, and the pieces that shell needs.

**The generated `android/` project is deliberately not committed.** It is
hundreds of files that `npx cap add android` recreates exactly, and the one
thing it *doesn't* recreate — the icons and the app name — is what this
folder holds.

---

## Rebuilding from scratch

On Windows, run `setup-mydaybuddy-android.ps1`. It is idempotent: run it as
many times as you like and it continues from wherever it stopped. It installs
Node and Android Studio, sets `JAVA_HOME` / `ANDROID_HOME`, generates the
native project, copies the icons in, sets the version code, and verifies the
result before you build.

By hand, the same thing:

```
npm install
npx cap add android
npx cap sync android
```

Then, and this part is not optional:

1. Copy `notification-icon/drawable-*` into `android/app/src/main/res/`
2. Copy `launcher-icons/mipmap-*` and `launcher-icons/values/*`
   into `android/app/src/main/res/`
3. Check `android/app/src/main/res/values/strings.xml` says
   `app_name` = **My Day Buddy**
4. Set `versionCode` in `android/app/build.gradle` to one higher than the
   last uploaded build

**Why steps 1–3 exist:** `cap add android` fills `mipmap-*` with Capacitor's
own placeholder launcher icon. It does not read the web manifest. Skip this
and you ship a generic icon — this nearly happened on versionCode 2.

---

## Permissions

`@capacitor/local-notifications` merges in `POST_NOTIFICATIONS`,
`RECEIVE_BOOT_COMPLETED` and `WAKE_LOCK` on its own. One must be added by hand
to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

Without it Android downgrades reminders to inexact alarms, which drift 10–15
minutes on a sleeping phone — the exact symptom the Capacitor build exists to
fix.

**Never add `USE_EXACT_ALARM`.** That one is restricted by Play to alarm-clock
and calendar apps and is a rejection risk here. `SCHEDULE_EXACT_ALARM` is not
restricted; the user grants it in Settings → Apps → My Day Buddy → Alarms &
reminders.

---

## Version pinning

Google Play raises its minimum target SDK every August. Capacitor ships a major
version to match, and hand-editing `targetSdkVersion` is explicitly
unsupported. So: **bump the Capacitor major once a year** rather than patching
`variables.gradle`.

| Capacitor | targetSdk | minSdk |
|---|---|---|
| 8 | 36 (Android 16) | 24 |
| 7 | 35 | 23 |

Moving 7 → 8 raised minSdk from 23 to 24, which drops ~1,000 older device
models. Play blocks the release over this and you accept it with "Proceed
anyway". Expect the same prompt every year.

Decline every upgrade Android Studio offers mid-release — AGP, Kotlin, the
Gradle daemon toolchain. Capacitor 8 pins AGP 8.13.0 and Kotlin 2.2.20.

---

## Signing

The keystore is **not** in this repo and must never be. Signing with any other
key makes Play treat the upload as a different app and reject it.

`signing.keystore` lives in `Daybook-Play-Package.zip`, kept offline. If it is
ever lost, Play App Signing has a key-reset path, but it takes days.

---

## Identifiers that must never change

| | |
|---|---|
| Package name | `io.github.gauravvdev.daybook` |
| localStorage key | `daybook_state_v1` |
| IndexedDB store | `daybook_media` |
| Notification channel | `daybook-reminders` |
| Notification icon | `ic_stat_daybook` |

They still say "daybook" and that is correct. The package name can never be
changed after publishing, and renaming the storage keys would wipe every
existing user's data.

---

## Gotchas that cost real time

- **PowerShell's `Set-Content -Encoding UTF8` writes a BOM.** Groovy then fails
  with `Unexpected character: '"'` on line 1 of a file that looks perfectly
  fine in the editor. Use
  `[IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding $false))`.
- **`npx` is blocked by the default execution policy** — use `npx.cmd`.
- **Android Studio's SDK Manager lists `36.0`, `36.1` and `36.0-ext*` together.**
  `compileSdk 36` resolves to `platforms/android-36` only. Install the row
  reading API Level `36.0`, Revision `2`.
- **Studio's first-run wizard installs only the newest platform**, never the one
  the project needs.
- **Studio bundles JDK 25; Gradle 8.14.3 supports ≤ 24.** Take Studio's
  "Use JVM 21" offer.
