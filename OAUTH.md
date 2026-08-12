# Setting up Google & Facebook sign-in

The Rails side of this is done -- both providers work in code the
moment real credentials exist. That's the part I can't do for you:
creating the actual OAuth apps and getting Client IDs/Secrets requires
you to have accounts on Google Cloud Console and Meta for Developers,
and to make judgment calls (app name, logo, which of your own domains
to authorize) that only you can make.

## Google (the simpler one -- start here)

1. Go to **console.cloud.google.com** and create a new project (or use
   an existing one) — top-left project dropdown → "New Project".
2. In the left sidebar: **APIs & Services → OAuth consent screen**.
   - User type: **External** (unless you have a Google Workspace org).
   - Fill in app name (e.g. "OrbitMath"), your email, and a support
     email. Logo/domain fields are optional for now.
   - Scopes: the defaults (`email`, `profile`) are enough — this app
     only asks for those.
   - Test users: while your app is in "Testing" publishing status,
     only accounts you explicitly add here can sign in. Add your own
     Google account (and your friend's, if he's testing) here, or
     publish the app (see step 4).
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
   - Application type: **Web application**.
   - Authorized redirect URIs — add BOTH of these exactly:
     ```
     http://localhost:3000/auth/google_oauth2/callback
     https://orbit-math.us/auth/google_oauth2/callback
     ```
   - Click Create. You'll get a **Client ID** and **Client Secret** —
     copy both.
4. **Publishing status**: while "Testing," only the test users you
   listed in step 2 can actually sign in — everyone else gets blocked
   by Google before they ever reach your app. When you're ready for
   anyone to be able to sign up with Google, go back to the OAuth
   consent screen and click **Publish App**. Google may require a
   basic verification for apps requesting more than the default
   scopes, but `email`/`profile` alone typically doesn't trigger that.

## Facebook (expect more friction)

1. Go to **developers.facebook.com** → **My Apps → Create App**.
   - Use case: choose **Authenticate and request data from users with
     Facebook Login** (or similar — Meta's exact wording changes
     periodically).
   - App type: **Consumer**.
2. In the app dashboard, add the **Facebook Login** product if it
   isn't already added.
3. **Facebook Login → Settings** — under "Valid OAuth Redirect URIs," add:
   ```
   http://localhost:3000/auth/facebook/callback
   https://orbit-math.us/auth/facebook/callback
   ```
4. **App Settings → Basic** — copy your **App ID** and **App Secret**.
5. **App Mode**: new Facebook apps start in **Development mode**, where
   only you (the app's admin/developers/testers, added under **App
   roles**, or via Business Manager → People if your app is tied to a
   Business Portfolio) can actually log in with it.

## Reality check on going Live with Facebook (learned the hard way)

Getting Facebook out of Development mode turned out to be real, possibly
significant friction, worth knowing about before you invest time:

- Meta requires **Business Verification** before an app can be used by
  the general public, not just testers -- this needs actual legal
  business documents (incorporation certificate, business tax
  documents, etc.). If you don't have a registered business entity,
  this isn't just paperwork friction, it can be a genuine dead end.
- There's supposedly a simpler **Individual/Admin verification** path
  (just a government ID) documented for solo developers without a
  registered business -- but it did **not** actually appear as an
  option in practice; the Business Portfolio verification flow only
  offered the full document-based path.
- If your Business Portfolio (Business Manager account) has no legal
  business name, address, or phone on file, that's exactly why it asks
  for documents -- it's treating the request as full business
  verification with no alternative offered.

**Current decision for this app**: staying in Development mode.
Facebook sign-in works fully for the app owner and anyone explicitly
added as a Business Manager tester; the "Continue with Facebook" button
is hidden from public view (see `FACEBOOK_LOGIN_PUBLIC` below) so a
random visitor without tester access never hits Facebook's dead-end
error. Google and traditional signup handle everyone else. Revisit this
if/when a registered business entity exists.

## Setting the credentials

**Locally** — create (or edit) `.env` in the project root:

```
GOOGLE_CLIENT_ID=your-client-id-here
GOOGLE_CLIENT_SECRET=your-client-secret-here
FACEBOOK_APP_ID=your-app-id-here
FACEBOOK_APP_SECRET=your-app-secret-here
FACEBOOK_LOGIN_PUBLIC=false
```

**On Heroku**:

```zsh
heroku config:set GOOGLE_CLIENT_ID=your-client-id-here
heroku config:set GOOGLE_CLIENT_SECRET=your-client-secret-here
heroku config:set FACEBOOK_APP_ID=your-app-id-here
heroku config:set FACEBOOK_APP_SECRET=your-app-secret-here
heroku config:set FACEBOOK_LOGIN_PUBLIC=false
```

`FACEBOOK_LOGIN_PUBLIC` controls whether the "Continue with Facebook"
button shows up for every visitor (`true`) or stays hidden from
everyone except people who navigate to it directly (`false`, the
default). The Facebook credentials themselves stay fully configured and
working either way -- this only controls the button's visibility.
Flip it to `true` (and restart the app) once Facebook sign-in is
actually out of Development mode.

## Testing it

Once credentials are set (even just Google, if you're doing these one
at a time), restart `bin/dev` and visit `/login` or `/signup` — you
should see a "Continue with Google" button always, and "Continue with
Facebook" only if `FACEBOOK_LOGIN_PUBLIC=true`.

If a provider isn't configured (env vars blank), OmniAuth will still
attempt the request and fail at Google/Facebook's side with an
authentication error, landing you on the login page with a "that
sign-in didn't work" message — it won't crash the app.
