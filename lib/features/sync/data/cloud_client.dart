import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The publishable key is designed for public clients. RLS protects user data.
const cloudUrl = 'https://kmgfrnpjgewoatucgcqi.supabase.co';
const cloudPublishableKey = 'sb_publishable_fIGKj6JI4bOZS7OwdBbrdw_GPTYh2yu';
SupabaseClient? initializedCloudClient;

Future<void> initializeCloud() async {
  try {
    await Supabase.initialize(url: cloudUrl, publishableKey: cloudPublishableKey);
    initializedCloudClient = Supabase.instance.client;
  } catch (_) {
    // A storage or SDK failure must never block local learning.
    initializedCloudClient = null;
  }
}

final cloudClientProvider = Provider<SupabaseClient?>((ref) => initializedCloudClient);
