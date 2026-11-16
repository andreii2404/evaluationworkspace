# In Cantiere

In Cantiere is a Flutter web app for getting structured feedback on research, games, prototypes, and creative work. The public site leads to sign-in and sign-up for the cloud workspace.

## Run with the hosted backend

With your public Supabase settings saved in `.dart_tool/evalink-hosted.json`, run this from the project folder:

```powershell
.\run.cmd
```

The launcher opens Chrome at http://127.0.0.1:8080 with the hosted backend settings.

## Deploy to Vercel

Import this GitHub repository into Vercel. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the Vercel project for the deployment environments you use. The repository's build settings install Flutter 3.41.6 and publish the release files from `build/web`.

Set the production URL as the Supabase Authentication Site URL and add its exact URL under Redirect URLs. Keep the local redirect entries if you still run the app locally.

## Use Supabase locally

With Docker running:

```powershell
.\scripts\start-evalink.ps1 -LocalSupabase
```

The script starts the local stack, applies pending migrations, and starts Flutter with the local public API settings. Retrieve signup and password-reset codes from the local mail inbox shown by `supabase status`.

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

Hosted email signup and password recovery default to Supabase's confirmation and reset links. To use email codes on a hosted deployment, configure custom SMTP, install the confirmation and recovery templates in `supabase/templates`, and build with `--dart-define=AUTH_EMAIL_CODES=true`. The app accepts the Supabase email code range of six to ten digits. The local Supabase configuration uses six-digit email codes with these templates. A custom SMTP sender is required for public email delivery on this hosted project.

Members can enroll a backup authenticator on a second device under **Profile → Two-step verification**. A moderator must verify an authenticator to access the workspace.

## Cloud workflows

- Sign up, confirm email, and sign in. New accounts get a profile automatically.
- The community is free to use. Members can create projects and accept review invitations with the same account.
- Edit your profile and opt into the evaluator directory. Expertise and portfolio links are self-reported.
- Create a private project with an HTTPS artifact link and an in-app questionnaire. Publish it to Community or invite an evaluator directly.
- Accept or decline an invitation. An accepted evaluator can submit one review with scores, feedback, and a conflict-of-interest declaration.
- The database validates scores and advances the assignment when feedback is submitted. The app listens for assignment updates and also offers manual refresh.
- Signed-in members can report community projects. A trusted admin can grant moderation with the server-managed Auth app metadata property `evalink_moderator: true`. Moderators can resolve or dismiss reports.

Project and portfolio links use their external provider's access settings. Private projects should use artifact links with matching access controls.

Build a questionnaire from scratch or start with an editable in-app template. The owner can edit the project questionnaire before reviews are assigned or submitted. Signed-in community members can choose **Evaluate** on a published post and submit a response directly without an invitation. The owner and collaborators open **Projects → My projects & teams → Responses** for summaries, individual submissions, and CSV export. Existing attachments and results remain available on older projects.


## Team projects

Open a project and use **Team** to add collaborators from the directory or your connections. Collaborators can access the project, its results, review conversations, revisions, and shared files. The owner manages the team and sends review invitations. A collaborator cannot evaluate the same project.

**Files** in the sidebar is personal. The **Files** tab inside a project is shared with its team. Both support nested folders and common research files up to 10 MB each. Use **Rounds** to collect feedback on a new version without losing the previous round.

## Landing page photography and typography

The landing page bundles optimized WebP versions of [Group of People Studying Together by Ivan S](https://www.pexels.com/photo/group-of-people-studying-together-5676744/), [Crop female student writing notes in copybook while sitting at table by Zen Chung](https://www.pexels.com/photo/crop-female-student-writing-notes-in-copybook-while-sitting-at-table-5538622/), and [Photo Of People Looking On Laptop by fauxels](https://www.pexels.com/photo/photo-of-people-looking-on-laptop-3182804/) under the [Pexels License](https://www.pexels.com/license/). Manrope is distributed under the [SIL Open Font License](assets/landing/Manrope-OFL.txt).

The glass landing page uses [Blue and White Water Waves by Pawel Czerwinski](https://unsplash.com/photos/blue-and-white-water-waves-ISgDx2aOAB8) under the [Unsplash License](https://unsplash.com/license). The motion references are [Guglielmo Giannattasio's Nimbus UI Waterline](https://preview.21st.dev/@gughigug/components/liquid-glass-navbar) for the liquid navigation and [Annnimate's Card Fan](https://annnimate.com/animations/card-fan) for the layered hero. [Serko](https://www.serko.ai/) informed the combination of photography and product previews.
