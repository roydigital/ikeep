import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'service_providers.dart';

final googleSignInProvider = Provider<GoogleSignIn>((ref) => GoogleSignIn());
bool _interactiveGoogleSignInInProgress = false;

/// Source of truth for signed-in state across the app.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Restores Firebase auth from a cached Google account when available.
final authSessionBootstrapProvider = FutureProvider<void>((ref) async {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth.currentUser != null || _interactiveGoogleSignInInProgress) return;

  final googleSignIn = ref.watch(googleSignInProvider);

  try {
    final account = await googleSignIn.signInSilently();
    if (_interactiveGoogleSignInInProgress || auth.currentUser != null) return;

    final restoredAccount = account ?? googleSignIn.currentUser;
    if (restoredAccount == null) return;

    await signInFirebaseWithGoogleAccount(auth, restoredAccount);
  } catch (e, st) {
    debugPrint('Silent Google->Firebase restore failed: $e');
    debugPrintStack(stackTrace: st);
    // Leave the app signed out when silent restoration fails.
  }
});

final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull != null;
});

Future<T> runInteractiveGoogleSignInFlow<T>(
  Future<T> Function() action,
) async {
  _interactiveGoogleSignInInProgress = true;
  try {
    return await action();
  } finally {
    _interactiveGoogleSignInInProgress = false;
  }
}

Future<void> signInFirebaseWithGoogleAccount(
  FirebaseAuth auth,
  GoogleSignInAccount account,
) async {
  if (auth.currentUser != null) {
    return;
  }

  final googleAuth = await account.authentication;
  final idToken = googleAuth.idToken;
  final accessToken = googleAuth.accessToken;

  if ((idToken == null || idToken.isEmpty) &&
      (accessToken == null || accessToken.isEmpty)) {
    throw StateError('Google Sign-In did not return an auth token.');
  }

  final credential = GoogleAuthProvider.credential(
    idToken: (idToken?.isEmpty ?? true) ? null : idToken,
    accessToken: (accessToken?.isEmpty ?? true) ? null : accessToken,
  );
  await auth.signInWithCredential(credential);
}
