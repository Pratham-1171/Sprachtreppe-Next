# Sprachtreppe backend + LMS setup

Supabase hosts authentication, PostgreSQL, RLS and server-side functions. GitHub hosts source/CI. The Android app contains only the public Supabase URL + anon/publishable key; never ship a service-role key.

## 1. Apply the database schema

Use the supported **GitHub Actions → Provision Sprachtreppe Next Supabase → Run workflow** path. Add the repository secrets `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` first.

The workflow builds the canonical, timestamp-matched migration chain and runs `supabase db push`. It intentionally excludes the obsolete historical LMS migrations `001`–`012`, whose earlier schema uses incompatible class IDs. **Do not run `001_lms_phase1.sql`–`012` directly on Sprachtreppe Next, and do not reinitialize or reset the production database.** For an already provisioned database, the migration ledger ensures only unapplied canonical migrations run.

The chain includes the base schema, OTP signup, notification security, canonical LMS, submission guardrails, full personal learning-state sync, answer-event aggregation, the durable idempotent answer-event ledger and date-aware current-streak merging. See `.github/workflows/supabase-next-migrate.yml` for the exact version mapping.

### Required extension

If the base migration reports that `digest` does not exist, open **Database → Extensions**, enable **pgcrypto**, then rerun the workflow.

## 2. Create/promote the administrator

Create your account in **Authentication → Users → Add user** and auto-confirm it if desired.

Then run this in SQL Editor, replacing the email:

```sql
update public.profiles
set role = 'admin', approved = true
where email = 'you@example.com';
```

Never put the admin password in the APK, GitHub repository, JavaScript, or SQL source files.

## 3. Authentication settings

Recommended:

- Email provider: enabled.
- Minimum password length: 10+.
- Confirm email: optional for classroom use; approval still controls database access.
- Disable public signups after all students have registered if the app is private.
- CAPTCHA: recommended if the registration endpoint is public.

## 4. GitHub secrets

In **GitHub → Settings → Secrets and variables → Actions**, add:

- `SUPABASE_URL` = your Supabase project URL.
- `SUPABASE_ANON_KEY` = Supabase anon/publishable key.

Never use `service_role` as the app key.

## 5. Scheduled maintenance and email reminders

The database now creates an `email_queue`. **The database does not send email itself.** A server-side email worker/Edge Function should read pending rows and send them through your chosen provider (for example, Resend, Postmark or another transactional provider). Keep that provider API key server-side.

The following functions prepare queue entries:

```sql
select public.queue_assignment_due_reminders();
select public.queue_inactive_student_reminders();
select public.queue_weekly_student_reports();
```

Only an admin can run them.

For automatic scheduling, Supabase projects can use `pg_cron` if enabled. After enabling it, create jobs such as:

```sql
select cron.schedule(
  'sprachtreppe-assignment-reminders',
  '15 * * * *',
  $$select public.queue_assignment_due_reminders();$$
);

select cron.schedule(
  'sprachtreppe-inactive-reminders',
  '0 9 * * *',
  $$select public.queue_inactive_student_reminders();$$
);

select cron.schedule(
  'sprachtreppe-weekly-reports',
  '0 9 * * 1',
  $$select public.queue_weekly_student_reports();$$
);
```

For cleanup, `public.run_retention_cleanup()` is protected by admin authorization. If your pg_cron setup runs it directly, use a secure server-side mechanism rather than exposing an admin JWT in the database job. A Supabase Edge Function or trusted server job is preferred for scheduled privileged operations.

## 6. Retention policy implemented

Current cleanup targets are:

- Notifications: 90 days.
- Study sessions: 1 year.
- Sent email queue rows: 90 days.
- Audit log: 2 years.

Assignment/submission records are **not automatically deleted** because they are educational records and may be needed for course history. Review this policy before adding automatic deletion.

## 7. LMS capabilities now in the database

### Admin

- Promote/demote users.
- Create/manage classes.
- Add teachers.
- View class activity.
- Audit administrative actions.
- Manage the notification/email infrastructure.

### Teacher

- Create classes.
- Add co-teachers.
- Generate/revoke class invitations.
- Remove students.
- Publish announcements.
- Create assignments.
- Assign course activities.
- Set points/due dates.
- Review submissions.
- Grade and return feedback.
- View class activity and assignment statistics.

### Student

- Join classes with an invitation code.
- Leave classes.
- View announcements.
- Receive in-app notifications.
- View assignments and due dates.
- Submit assignments with idempotent client IDs for offline/retry safety.
- Receive grades and teacher feedback.
- Record study sessions for activity analytics.

## 8. Offline-first rule

Course content remains local. Assignment work can be stored locally by the app and submitted later. Every submission/session needs a stable client-generated ID so retrying after reconnect does not create duplicates.

Do not trust the phone for authorization, grades, approval, teacher role or class membership. Those decisions remain server-side through Supabase RLS/functions.

## 9. Build/test

After the database migrations are applied:

1. Build the Android APK through GitHub Actions.
2. Install/update the APK.
3. Test student login and approval.
4. Test teacher promotion.
5. Create a class.
6. Generate a class code and join as a student.
7. Publish an announcement.
8. Create an assignment.
9. Submit it as the student.
10. Grade it as the teacher.
11. Verify the student receives the grade/feedback notification.
12. Record a study session and verify teacher dashboard statistics.

## 10. Important security rule

Never expose:

- Supabase `service_role` key.
- Email provider API keys.
- Admin passwords.
- Database passwords.

The anon/publishable key is expected to be present in a client app; RLS and server-side functions are the security boundary.

## Migration workflow safety

The repository workflow `.github/workflows/supabase-next-migrate.yml` is manual-only and maps the twelve known Next migration ledger versions explicitly. It does **not** replay historical `001`–`012` SQL, and it does not delete/reinitialize the entire Supabase folder. To run that workflow, configure repository secrets `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`. New schema changes must be added as a new, immutable migration and explicitly mapped in the workflow; do not edit an already-applied migration expecting it to rerun.

## 11. Personal progress across devices

Approved students have a server-owned `learning_state` snapshot plus an append-only `learning_answer_events` ledger. A successful answer is queued locally with a stable ID before network work; each retry reuses that ID, and the database uniqueness constraint prevents duplicate answers when two devices reconnect or a response is lost. The server stores vocabulary mastery, grammar completion, mistakes and aggregate answer totals separately from the event log; study sessions are merged by stable session IDs.

The browser course merges personal state during sign-in and uploads newly scored answers. Flutter uploads local answer batches, removes only server-acknowledged event IDs from its offline queue, downloads the compact aggregate state and merges study sessions. Unsent events remain local on connection failure. The dashboard displays the latest server-synced learning aggregates and falls back to its device cache while offline. Current streak follows the most recent study date (so it can reset after a gap); the longest-ever streak remains a maximum across devices.

Old summary-only progress from before event logging cannot be reconstructed into individual answer events; it is preserved as legacy course state. Test the web and Flutter flows with two devices (including an offline answer on each) before a classroom rollout.