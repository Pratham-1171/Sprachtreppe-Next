# Sprachtreppe Android Online/Offline Test Checklist

Use this checklist with a **release APK downloaded from the newest successful GitHub Actions run on `flutter-shell`**. Before installing, confirm the artifact's commit SHA matches the branch commit you intend to test.

These checks require a real Android device. A green CI build does not prove that Android session restoration, airplane-mode behavior, or live Supabase permissions work end-to-end.

## 1. Install and sign in

- [ ] Install the APK on the Android phone.
- [ ] Sign in as an approved student created by the administrator.
- [ ] Confirm there is no client-side role selector and the student sees only student navigation.
- [ ] Open Home, Learn, Practice, Tasks, Profile, and Notifications once while online.
- [ ] Run **Sync now** and confirm the screen reports a successful sync.
- [ ] Confirm vocabulary and grammar pages open and can be searched.

## 2. Test offline relaunch and cached pages

- [ ] With the student still signed in, force-stop the app.
- [ ] Enable Airplane mode and verify Wi-Fi/mobile data are off.
- [ ] Reopen the app. A previously authenticated student should be able to reach the local learning shell after a recognized connectivity failure.
- [ ] Check Home: cached classes, assignments, announcements and summary counts should appear with an offline-view notice.
- [ ] Check Tasks: cached assignment details should appear with an offline-view notice.
- [ ] Check Notifications: cached items should appear with an offline notice.
- [ ] Verify that server actions such as marking a notification read or submitting online cannot report success while offline.
- [ ] Confirm normal page content fits the phone width and does not require horizontal scrolling.

## 3. Queue work without a network

Keep the app within the seven-day window after a successful sync so the weekly gate does not intentionally block learning.

- [ ] Complete a Practice round and confirm local session statistics change.
- [ ] Make progress on an assignment that was cached while online.
- [ ] Write and submit a reading/writing response. The app should say the response is saved locally and queued.
- [ ] Force-stop and reopen the app, still offline.
- [ ] Confirm the practice history, assignment progress and queued response remain available.
- [ ] Switch to a different test account only after recording the expected local values; the second account must not display the first account's cached pages or queued work.

## 4. Sync and verify data reaches the school

- [ ] Restore the internet connection.
- [ ] Open the notification/sync center and tap **Sync now**.
- [ ] Confirm the completion message reports the saved sessions and any queued assignment-progress or written-response items.
- [ ] Open Tasks again and confirm the submitted response is no longer shown as pending locally once the server has confirmed it.
- [ ] Sign in to the Admin account and check the review queue for the student's written response and weekly progress summary.
- [ ] Verify the submission belongs to the correct student and contains the correct response, session/question totals and accuracy.
- [ ] Run Sync now a second time without making new changes. No duplicate review entry should appear for the unchanged snapshot.
- [ ] Add one more practice session or edit a written response, sync again, and confirm the new change is delivered without deleting newer local work.

## 5. Verify the seven-day gate

- [ ] On a fresh test profile/device state with no successful sync recorded, confirm Learn, Practice and Tasks show **Weekly sync required**.
- [ ] Verify Home, Profile and the notification/sync entry point stay available so the student can connect and sync.
- [ ] Complete a successful sync; Learn, Practice and Tasks should unlock.
- [ ] Confirm unit tests cover the exact seven-day boundary. Do not change the phone clock on a real student account just to simulate expiry; use a test account/device state.

## 6. Verify role boundaries while online

- [ ] Student: can see only their own data and cannot access Admin/Teacher actions.
- [ ] Teacher: can see only assigned classes/students and can publish only to an eligible class.
- [ ] Admin: can approve students, assign teachers/classes, create assignments and review written submissions.
- [ ] Sign out and confirm the cached approved-profile entry is removed for that user.
- [ ] Attempting unauthorized operations must be denied by Supabase RLS/server-side role checks, not merely hidden in the UI.

## Results to record

| Field | Result |
|---|---|
| Android model / OS | |
| APK run number and commit SHA | |
| Student offline relaunch | Pass / Fail |
| Dashboard / Tasks / Notifications cache | Pass / Fail |
| Practice / assignment / writing queue | Pass / Fail |
| Sync delivery and duplicate prevention | Pass / Fail |
| Seven-day gate and unlock | Pass / Fail |
| Student / Teacher / Admin role checks | Pass / Fail |
| Horizontal scrolling / narrow layout | Pass / Fail |
| Issues and screenshots | |
