# In Cantiere

In Cantiere is a Flutter web app for getting structured feedback on research, games, prototypes, and creative work. The public site leads to sign-in and sign-up for the cloud workspace.

## Run with the hosted backend

If your public Supabase settings are saved in `.dart_tool/evalink-hosted.json`, run:

```powershell
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8080 --dart-define-from-file=.dart_tool/evalink-hosted.json
```

Open http://127.0.0.1:8080.

## Use Supabase locally

With Docker running:

```powershell
.\scripts\start-evalink.ps1 -LocalSupabase
```

The script starts the local stack, applies pending migrations, and starts Flutter with the local public API settings. Local email confirmation is disabled to simplify development.

## Connect a hosted project

Create a dedicated project in your own Supabase organization. Authorize the Supabase CLI with `npx --yes supabase@3.0.0 login` and run:

```powershell
.\scripts\start-evalink.ps1 -ProjectRef 'your-project-ref'
```

The script retrieves the project's publishable key and applies pending migrations. If API key lookup is unavailable, provide `-PublishableKey` from the project's Connect panel. Use a publishable key in Flutter. Add `-Build` to compile the web app into `build/web` with the chosen backend.

In the hosted project's Authentication URL settings, use the final web origin as the Site URL and add the development URL `http://localhost:8080/` to Redirect URLs. Keep hosted email confirmation enabled. Configure the intended sender and delivery settings before opening registration to external testers.

## Google sign-in

Create a Web application OAuth client in [Google Auth Platform](https://console.cloud.google.com/auth/clients). For the hosted In Cantiere backend, add `https://wjghcfgkiaixcjelczgl.supabase.co/auth/v1/callback` as an authorized redirect URI. Use `http://127.0.0.1:8080` as an authorized JavaScript origin for the current preview. If Google restricts access while the app is in testing, use the app's audience settings to add the relevant test accounts.

Enable Google under Supabase Authentication providers and enter the OAuth client ID and secret there. The Google credentials stay in Supabase. Add each deployed In Cantiere URL to the Supabase redirect allow list and use the intended site URL for the environment. The sign-in screen reads provider availability from Supabase, so enabling Google does not require a new Flutter build.

## Cloud workflows

- Sign up, confirm email, and sign in. New accounts get a profile automatically.
- The community is free to use. Members can create projects and accept review invitations with the same account.
- Edit your profile and opt into the evaluator directory. Expertise and portfolio links are self-reported.
- Create a private project with an HTTPS artifact link and a versioned rubric. Share it with signed-in community members or invite an evaluator directly.
- Accept or decline an invitation. An accepted evaluator can submit one review with scores, feedback, and a conflict-of-interest declaration.
- The database validates scores and advances the assignment when feedback is submitted. The app listens for assignment updates and also offers manual refresh.
- Signed-in members can report community projects. A trusted admin can grant moderation with the server-managed Auth app metadata property `evalink_moderator: true`. Moderators can resolve or dismiss reports.

Project and portfolio links use their external provider's access settings. Private projects should use artifact links with matching access controls.

The first release covers email accounts, profiles, a searchable evaluator directory, projects, questionnaires, assignments, feedback, and basic report handling. The Questionnaires library provides ISO/IEC 25010:2023 and MARS worksheets with original Word downloads and editable copies. Creators can save forms and PDF or Word attachments privately, then select one for a project. In-app questionnaire edits made during project creation apply to that project. Creators share a direct HTTPS link to the work under test and can also link an external form.


## Landing page photography and typography

The landing page bundles optimized WebP versions of [Group of People Studying Together by Ivan S](https://www.pexels.com/photo/group-of-people-studying-together-5676744/), [Crop female student writing notes in copybook while sitting at table by Zen Chung](https://www.pexels.com/photo/crop-female-student-writing-notes-in-copybook-while-sitting-at-table-5538622/), and [Photo Of People Looking On Laptop by fauxels](https://www.pexels.com/photo/photo-of-people-looking-on-laptop-3182804/) under the [Pexels License](https://www.pexels.com/license/). Manrope is distributed under the [SIL Open Font License](assets/landing/Manrope-OFL.txt).

The glass landing page uses [Blue and White Water Waves by Pawel Czerwinski](https://unsplash.com/photos/blue-and-white-water-waves-ISgDx2aOAB8) under the [Unsplash License](https://unsplash.com/license). The motion references are [Guglielmo Giannattasio's Nimbus UI Waterline](https://preview.21st.dev/@gughigug/components/liquid-glass-navbar) for the liquid navigation and [Annnimate's Card Fan](https://annnimate.com/animations/card-fan) for the layered hero. [Serko](https://www.serko.ai/) informed the combination of photography and product previews.
