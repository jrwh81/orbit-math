# Getting this into the App Store and Play Store

This app is one Rails web application. The recommended path to both app
stores is to **wrap the deployed web app in a thin native shell**, rather
than building and maintaining a second native codebase — that keeps a
single source of truth (this Rails app) for gameplay, and the native
shells become a very small, low-maintenance layer.

This doc is a checklist, not code that ships pre-built — actually
generating and signing native binaries has to happen on your Mac (Xcode)
and with Android Studio installed, which weren't available in the
environment this app was written in.

## Recommended approach: Capacitor

[Capacitor](https://capacitorjs.com/) wraps a web app in a native
WebView shell and gives you real iOS/Android projects you open in Xcode
/ Android Studio to build, sign, and submit — while all your actual game
code stays in this Rails app, served over the network exactly like a
normal website.

### 1. Deploy the Rails app first

Get `OrbitMath` (or whatever you've renamed it to) live at a real HTTPS
URL — Render, Fly.io, or similar (see the deployment section of the main
README). You need a stable production URL before wrapping it.

### 2. Scaffold the native shell (run these on your Mac, outside this repo)

```bash
mkdir orbit_math_mobile && cd orbit_math_mobile
npm init -y
npm install @capacitor/core @capacitor/cli
npx cap init "OrbitMath" "com.yourcompany.orbitmath" --web-dir=www
```

Since the game is server-rendered (not a static site), point Capacitor
at your live URL instead of a local `www` folder — edit the generated
`capacitor.config.json`:

```json
{
  "appId": "com.yourcompany.orbitmath",
  "appName": "OrbitMath",
  "webDir": "www",
  "server": {
    "url": "https://your-deployed-domain.com",
    "cleartext": false
  }
}
```

### 3. Add the platforms

```bash
npm install @capacitor/ios @capacitor/android
npx cap add ios
npx cap add android
npx cap sync
```

This generates real `ios/` (Xcode project) and `android/` (Android
Studio / Gradle project) directories.

### 4. Open and configure each platform

```bash
npx cap open ios       # opens Xcode
npx cap open android   # opens Android Studio
```

In each, set your app icon (the `public/icon.svg` in this repo is a
starting point — export it to the various required PNG sizes), splash
screen, and bundle identifier / package name to match what you used in
`cap init`.

### 5. ActionCable / WebSockets over the wrapped shell

Capacitor's WebView supports WebSockets normally, so multiplayer's
ActionCable connection works the same as in a browser — no extra
config needed as long as your production URL is `https://` (required
for `cleartext: false` above) and `config.force_ssl = true` (already
set in `config/environments/production.rb`) doesn't block the WebSocket
upgrade (it won't — `wss://` rides over the same TLS termination).

### 6. Build, sign, submit

- **iOS**: Product → Archive in Xcode, then use the Organizer to upload
  to App Store Connect. You'll need an active Apple Developer Program
  membership.
- **Android**: Build → Generate Signed Bundle/APK in Android Studio,
  upload the `.aab` to the Google Play Console. You'll need a Google
  Play Developer account.

Both stores will ask for privacy policy URLs, screenshots, and content
ratings — since this app collects usernames/passwords and gameplay
stats, a short privacy policy page is worth adding to the Rails app
itself (e.g. `/privacy`) before submitting.

## Alternative: Hotwire Native

If you'd rather go deeper into native-feeling navigation (native tab
bars, native transitions) while still driving everything from this same
Rails app's HTML, look at
[Hotwire Native](https://native.hotwired.dev/) (formerly Turbo Native).
It's a heavier lift than Capacitor but gives a more "really native" feel
for an app this interactive. Not necessary for an MVP — Capacitor is the
faster path to both stores.

## What you do NOT need to do

You do not need to rewrite the game in Swift/Kotlin/React Native, and
you do not need a separate backend or API layer for mobile — the same
Rails routes, views, and ActionCable channel that power the desktop
browser experience power the wrapped native apps too.
