# Evalink

Evalink is a Flutter web app for getting structured feedback on research, games, prototypes, and creative work. The public site opens either the cloud workspace or a separately labeled browser demo.

## Run the preview

```powershell
.\scripts\start-evalink.ps1
```

Open http://localhost:8080. The demo uses fictional data and browser storage. It is independent of Supabase.

## Use Supabase locally

With Docker running:

```powershell
.\scripts\start-evalink.ps1 -LocalSupabase
```

The script starts the local stack, applies pending migrations, and starts Flutter with the local public API settings. Local email confirmation is disabled to simplify development.

## Connect a hosted project

Create a dedicated Evalink project in your own Supabase organization. Authorize the Supabase CLI with `npx --yes supabase@3.0.0 login` and run:

```powershell
.\scripts\start-evalink.ps1 -ProjectRef 'your-project-ref'
```

The script retrieves the project's publishable key and applies pending migrations. If API key lookup is unavailable, provide `-PublishableKey` from the project's Connect panel. Use a publishable key in Flutter. Add `-Build` to compile the web app into `build/web` with the chosen backend.

In the hosted project's Authentication URL settings, use the final web origin as the Site URL and add the development URL `http://localhost:8080/` to Redirect URLs. Keep hosted email confirmation enabled. Configure the intended sender and delivery settings before opening registration to external testers.

## Google sign-in

Create a Web application OAuth client in [Google Auth Platform](https://console.cloud.google.com/auth/clients). For the hosted EvaLink backend, add `https://wjghcfgkiaixcjelczgl.supabase.co/auth/v1/callback` as an authorized redirect URI. Use `http://127.0.0.1:8080` as an authorized JavaScript origin for the current preview. If Google restricts access while the app is in testing, use the app's audience settings to add the relevant test accounts.

Enable Google under Supabase Authentication providers and enter the OAuth client ID and secret there. The Google credentials stay in Supabase. Add each deployed EvaLink URL to the Supabase redirect allow list and use the intended site URL for the environment. The sign-in screen reads provider availability from Supabase, so enabling Google does not require a new Flutter build.

## Cloud workflows

- Sign up, confirm email, and sign in. New accounts get a profile automatically.
- Edit your profile and opt into the evaluator directory. Expertise and portfolio links are self-reported.
- Create a private project with an HTTPS artifact link and a versioned rubric. Share it with signed-in community members or invite an evaluator directly.
- Accept or decline an invitation. An accepted evaluator can submit one review with scores, feedback, and a conflict-of-interest declaration.
- The database validates scores and advances the assignment when feedback is submitted. The app listens for assignment updates and also offers manual refresh.
- Signed-in members can report community projects. A trusted admin can grant moderation with the server-managed Auth app metadata property `evalink_moderator: true`. Moderators can resolve or dismiss reports.

Project and portfolio links use their external provider's access settings. Private Evalink projects should use artifact links with matching access controls.

The first release covers email accounts, profiles, a searchable evaluator directory, projects, rubric templates, assignments, feedback, and basic report handling. Credential verification, custom rubric authoring, file hosting, email reminders, and appeals remain future work.


## Landing page photography and typography

The landing page bundles optimized WebP versions of [Group of People Studying Together by Ivan S](https://www.pexels.com/photo/group-of-people-studying-together-5676744/), [Crop female student writing notes in copybook while sitting at table by Zen Chung](https://www.pexels.com/photo/crop-female-student-writing-notes-in-copybook-while-sitting-at-table-5538622/), and [Photo Of People Looking On Laptop by fauxels](https://www.pexels.com/photo/photo-of-people-looking-on-laptop-3182804/) under the [Pexels License](https://www.pexels.com/license/). Manrope is distributed under the [SIL Open Font License](assets/landing/Manrope-OFL.txt).
