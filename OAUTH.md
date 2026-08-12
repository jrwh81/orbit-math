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
   roles**) can actually log in with it. Switching to **Live** mode for
   real public use typically requires Meta's **App Review** for the
   `email` permission specifically — this can take some time and isn't
   instant like Google's. Budget for this being the slower half of the
   two to fully launch; Development mode is enough for you and a friend
   to test with in the meantime.

## Setting the credentials

**Locally** — create (or edit) `.env` in the project root:

```
GOOGLE_CLIENT_ID=your-client-id-here
GOOGLE_CLIENT_SECRET=your-client-secret-here
FACEBOOK_APP_ID=your-app-id-here
FACEBOOK_APP_SECRET=your-app-secret-here
```

**On Heroku**:

```zsh
heroku config:set GOOGLE_CLIENT_ID=your-client-id-here
heroku config:set GOOGLE_CLIENT_SECRET=your-client-secret-here
heroku config:set FACEBOOK_APP_ID=your-app-id-here
heroku config:set FACEBOOK_APP_SECRET=your-app-secret-here
```

## Testing it

Once credentials are set (even just Google, if you're doing these one
at a time), restart `bin/dev` and visit `/login` or `/signup` — you
should see "Continue with Google" and "Continue with Facebook" buttons.
Clicking one you haven't configured credentials for yet will error —
that's expected until you've done that provider's setup above.

If a provider isn't configured (env vars blank), OmniAuth will still
attempt the request and fail at Google/Facebook's side with an
authentication error, landing you on the login page with a "that
sign-in didn't work" message — it won't crash the app.
