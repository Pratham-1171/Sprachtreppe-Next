# Sprachtreppe Flutter Shell

This directory is the gradual Flutter migration for Sprachtreppe.

## Migration rule

Flutter replaces the legacy LMS feature-by-feature. A legacy module is removed only after its Flutter replacement passes CI, is tested on Android, and its Supabase behavior is verified.

## Current migration status

- ✅ Mobile-first application shell
- ✅ Authentication and role routing
- ✅ Student dashboard
- 🚧 Course catalog / lessons — Flutter replacement started
- ⏳ Vocabulary
- ⏳ Grammar
- ⏳ Practice and exercises
- ⏳ Progress and offline storage
- ⏳ Assignments and announcements
- ⏳ Teacher tools
- ⏳ Admin tools
- ⏳ Sync and notifications
- ⏳ Final legacy LMS removal

## Cleanup rule

Safe infrastructure cleanup can happen before feature migration when it is proven unused by the Flutter branch. The obsolete Capacitor APK workflow has been removed from this branch. The legacy course, Capacitor Android project, Node build system, and course JavaScript remain until their corresponding Flutter replacements are verified.

## Planned migration order

1. Mobile-first application shell
2. Authentication and role routing
3. Student dashboard
4. Course, vocabulary and grammar
5. Practice and exercises
6. Progress and offline storage
7. Assignments and announcements
8. Teacher tools
9. Admin tools
10. Sync and notifications
11. Remove obsolete LMS modules only after verified Flutter replacements exist

## Mobile requirement

The Flutter UI must be designed for narrow Android screens first and must not introduce horizontal scrolling for normal app content.

## Safety

Never remove a legacy feature merely because a Flutter screen exists. The replacement must contain the required behavior, pass CI, be tested on-device, and be verified against Supabase first.
