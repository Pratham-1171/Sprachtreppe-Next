# Sprachtreppe Flutter Shell

This directory is the beginning of the gradual Flutter migration for Sprachtreppe.

## Migration rule

The existing LMS remains intact. Flutter is introduced alongside it and will replace features incrementally only after each replacement is tested.

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

Do not delete or modify the existing LMS as part of the initial Flutter work. The legacy implementation is the fallback until the corresponding Flutter feature is production-ready.
