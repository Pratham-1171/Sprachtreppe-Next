# Sprachtreppe Flutter Shell

This directory contains the gradual Flutter migration for Sprachtreppe.

## Migration rule

Flutter replaces the legacy LMS feature-by-feature. A legacy module is removed only after its Flutter replacement passes CI, is tested on Android, and its Supabase behavior is verified.

## Current migration status

- ✅ Mobile-first Flutter shell, sign-in and role-based navigation
- 🚧 Supabase-backed student dashboard with classes, assignments, class and school-wide announcements, and local study statistics (global-announcement visibility fix under CI verification)
- ✅ A1–B1 course outline, searchable offline vocabulary and grammar library
- ✅ Offline practice quizzes with locally stored session history, accuracy and streaks
- ✅ Last-approved profile cache for restoring the learning UI after recognized network failures (CI passed; device verification pending)
- ✅ Student assignment list and reading/writing submissions
- ✅ Teacher dashboard, assigned classes and class work
- ✅ Admin dashboard, student approval, class/teacher setup, assignment creation and submission review
- 🚧 Teacher/admin in-app announcement publishing (implementation added; CI verification pending)
- ✅ Role-aware profile page with local progress, password-reset email and sign-out controls (CI passed; device verification pending)
- ✅ Weekly sync gate for offline Learn/Practice access (CI passed; device verification pending)
- ✅ Notification inbox and weekly progress sync (CI passed; Android device verification pending)
- ⏳ Final online/offline end-to-end testing and legacy LMS removal

These checkmarks indicate that the Flutter code exists; they do not claim device-level verification.

## Gradual migration order

1. App shell, authentication and role routing
2. Student dashboard
3. Course catalogue, vocabulary and grammar
4. Practice and local progress storage
5. Assignments and announcements
6. Teacher tools
7. Admin tools
8. Notification inbox and weekly progress sync
9. End-to-end online/offline verification on Android
10. Remove legacy modules only after verified Flutter replacements exist

## Mobile requirement

Design for narrow Android screens first. Normal content should never require horizontal scrolling.

## Safety and security

- Protected server-side role checks and Supabase RLS remain the security boundary; hiding a button is not authorization.
- The local profile cache is used only to restore the learning UI after recognized network/DNS failures. It does not grant database or RPC access, and it is cleared on sign-out or when an online profile is unapproved.
- Never put a Supabase service-role or secret key in a mobile app.
- Do not remove the legacy course, Capacitor project, Node build setup or course JavaScript until the corresponding Flutter replacement has passed CI, been tested on an Android device and had its Supabase behavior verified.
- Keep main stable until the flutter-shell branch is ready for a reviewed merge.
