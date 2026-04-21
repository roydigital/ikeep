# Firebase Security Rules — Deployment Guide

Version-controlled Firebase rules for iKeep. Rules are committed here and deployed via Firebase CLI.

## Files
- firestore.rules — Firestore database rules
- storage.rules — Firebase Storage rules
- firestore.indexes.json — composite indexes (empty until needed)
- firebase.json — maps rule files to Firebase services
- .firebaserc — sets default project to ikeep-1af18

## One-time setup
1. Install CLI: npm install -g firebase-tools
2. Login: firebase login (use roy@roydigital.in)
3. Verify project: firebase projects:list (should show ikeep-1af18)

## Deploy rules
From repo root:
    firebase deploy --only firestore:rules,storage

Dry-run to preview:
    firebase deploy --only firestore:rules,storage --dry-run

## Workflow for any rules change
1. Edit firestore.rules or storage.rules
2. Test in Firebase Rules Playground (console → Firestore → Rules → Playground)
3. Commit: git add firestore.rules storage.rules && git commit -m "Update rules: <reason>"
4. Deploy: firebase deploy --only firestore:rules,storage
5. Verify deployed rules match committed file in console

## Emergency rollback
1. git revert <bad-commit-sha>
2. firebase deploy --only firestore:rules,storage

Under 60 seconds to rollback.
