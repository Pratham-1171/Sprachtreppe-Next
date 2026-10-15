# Sprachtreppe Next — Supabase setup

This setup is for **Sprachtreppe-Next only**: Supabase project \`sprachtreppe-next\` (\`nkmiziinazafpbsavyxg\`). Do not use the old \`sprachtreppe\` project.

## Shared backend

The current Flutter APK and web app share one backend:
- \`profiles\`: email-OTP accounts, role (\`student\`, \`teacher\`, \`admin\`) and administrator approval.
- \`submissions\`: idempotent weekly progress snapshots, written responses and review/feedback.
- \`classes\`, \`class_teachers\`, \`class_members\`, \`teacher_students\`: classrooms and authorised roster links.
- \`assignments\`, \`assignment_progress\`, \`announcements\`, \`notifications\`, \`audit_log\`: assigned work, progress, announcements, notifications and staff audit.
- Row-level security (RLS) and checked server RPCs are the security boundary. Client-side navigation is not authorization.

## Existing production project

The production project has already received the base, OTP, notification, canonical LMS and submission-guard migrations. **Do not rerun \`backend/schema.sql\` or apply old LMS migrations to this existing project.** The Supabase migration ledger is authoritative.

## Fresh database setup only

For a new Next environment, run \`backend/schema.sql\` first, then the following files in order:

1. \`backend/migrations/013_student_otp_signup.sql\`
2. \`backend/migrations/014_flutter_notification_center.sql\`
3. \`backend/migrations/015_harden_flutter_notification_read.sql\`
4. \`backend/migrations/016_flutter_lms_canonical.sql\`
5. \`backend/migrations/017_lms_submission_guardrails.sql\`

The historical \`001\`–\`012\` files are old intermediate LMS versions. They use incompatible UUID-based class/assignment IDs or partial schemas; **do not run them for Sprachtreppe Next**. The canonical migration uses bigint class/assignment IDs to match the current APK.

## OTP and administrator

- Enable the Email provider in Supabase Auth.
- Ensure the OTP email template includes \`{{ .Token }}\` so users receive the six-digit code. Configure SMTP/custom email delivery for dependable delivery.
- New self-registered users are students and remain pending until administrator approval. Student registration must not allow selecting a role.
- After creating the first Auth account, promote it through a trusted, one-time SQL Editor operation:
  \`\`\`sql
  update public.profiles set role='admin', approved=true where email='you@example.com';
  \`\`\`
- The app may contain the public publishable/anon key. Never embed \`service_role\`, provider secrets, database passwords or admin passwords.

## Supported behavior

- Admin approval, promoting/demoting staff, creating classes, linking teachers/students, progress review and staff audit.
- Teacher workspace for assigned classes, students, assignments and announcements.
- Student Learn/Practice/Tasks, local-first progress, queued writing and weekly sync through \`submit_progress\`.
- Shared notification inbox. Users may only read their own notifications; direct updates are restricted to \`read_at\`.
- Written work and weekly sync use the existing reviewable \`submissions\` table; no separate incompatible LMS submission table is required.

Optional invitation-code, attendance analytics, scheduled reminder queue and email-worker subsystems from older LMS iterations are **not part of the canonical Next schema** and are not required by the current APK/web app.

## Verification checklist

On a fresh environment, verify the classroom tables have RLS enabled and these RPCs exist: \`my_classroom()\`, \`my_students()\`, \`admin_students_overview()\`, \`create_class(text)\`, \`create_assignment(bigint,text,text,text,integer,timestamptz)\`, \`update_assignment_progress(bigint,integer,integer)\`, \`submit_progress(jsonb,text)\`.

Test OTP registration/approval, teacher promotion, class creation, linking a teacher/student, publishing an assignment/announcement, syncing progress and reviewing a submission. A student must not be able to approve themselves, change roles, read another user's progress or mark another user's notification read.

## Deployment ownership

- The root GitHub Pages site is owned by the \`web-first\` branch and \`.github/workflows/deploy-web.yml\` on that branch.
- The Android APK is owned by \`flutter-shell\` and \`.github/workflows/flutter-android.yml\`.
- The Flutter branch's web workflow is manual-only for build/preview checks and must not automatically deploy over the root site.
- Database migrations and schema docs are mirrored on both branches; they do not require running the legacy LMS migration chain.
