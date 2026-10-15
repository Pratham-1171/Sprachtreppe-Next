# Sprachtreppe backend + LMS setup

Supabase hosts authentication, PostgreSQL, RLS and server-side functions. GitHub hosts source/CI. The Android app contains only the public Supabase URL + anon/publishable key; never ship a service-role key.

## 1. Apply the database schema

In **Supabase → SQL Editor**, run `backend/schema.sql` first.

Then run these migrations in this exact order:

1. `backend/migrations/001_lms_phase1.sql` — teacher role, classes, class teachers, members and invitation codes.
2. `backend/migrations/002_lms_phase2.sql` — announcements and in-app notifications.
3. `backend/migrations/003_lms_phase3.sql` — assignments, student submissions, grading and feedback.
4. `backend/migrations/004_lms_phase4_5_6.sql` — study sessions, attendance/activity analytics, audit log, email queue, roster controls, dashboards, retention cleanup and automatic assignment/grade notifications.
5. `backend/migrations/005_lms_scheduled_jobs.sql` — reminder/report queueing functions.

**Do not run the files out of order.** They are additive and preserve the existing progress/submission system.

### Required extension

Phase 1 uses `extensions.digest()` for hashed class invitation codes. If the migration reports that `digest` does not exist, open **Database → Extensions**, enable **pgcrypto**, then rerun Phase 1.

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

The repository workflow `.github/workflows/supabase-next-migrate.yml` is manual-only and maps the seven known Next migration ledger versions explicitly. It does **not** replay historical `001`–`012` SQL, and it does not delete/reinitialize the entire Supabase folder. To run that workflow, configure repository secrets `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`. New schema changes must be added as a new, immutable migration and explicitly mapped in the workflow; do not edit an already-applied migration expecting it to rerun.
