# lyrics_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supabase setup (optional)

To enable Supabase-backed remote sync instead of the default JSON sync:

1. Create a Supabase project and add a `songs` table matching the app's song fields (`id`, `title`, `lyrics`, `language`, `category`, `updatedAt`, `fontSize`, `favorite`).
2. Open `lib/config.dart` and set `SUPABASE_URL` and `SUPABASE_ANON_KEY` with your project's values.
3. Run `flutter pub get` to fetch the new dependency (`supabase_flutter`).
4. Start the app. The app will initialize Supabase and use it for remote sync automatically when the keys are provided.

Notes:
- The Supabase sync implementation fetches all rows from the `songs` table and upserts them into the local Hive store.
- For production you should add filtering (by `updatedAt`), server-side pagination, and proper Row Level Security (RLS) if you store per-user data.

