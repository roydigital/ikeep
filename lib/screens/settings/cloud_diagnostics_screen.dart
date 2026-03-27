import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models/cloud_diagnostics_snapshot.dart';
import '../../domain/models/cloud_usage_snapshot.dart';
import '../../domain/models/sync_checkpoint_state.dart';
import '../../providers/cloud_diagnostics_providers.dart';

class CloudDiagnosticsPanel extends ConsumerWidget {
  const CloudDiagnosticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(cloudDiagnosticsSnapshotProvider);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud Diagnostics',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hidden Closed Testing panel',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () =>
                        ref.invalidate(cloudDiagnosticsSnapshotProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Copy JSON',
                    onPressed: snapshotAsync.hasValue
                        ? () => _copySnapshot(
                              context,
                              snapshotAsync.requireValue,
                            )
                        : null,
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: snapshotAsync.when(
                data: (snapshot) => _DiagnosticsContent(snapshot: snapshot),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _DiagnosticsError(error: error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copySnapshot(
    BuildContext context,
    CloudDiagnosticsSnapshot snapshot,
  ) async {
    final encoder = const JsonEncoder.withIndent('  ');
    final payload = encoder.convert(snapshot.toJson());
    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
  }
}

class _DiagnosticsError extends StatelessWidget {
  const _DiagnosticsError({
    required this.error,
  });

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Unable to load diagnostics.\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DiagnosticsContent extends StatelessWidget {
  const _DiagnosticsContent({
    required this.snapshot,
  });

  final CloudDiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _DiagnosticsSectionCard(
          title: 'Plan / Entitlement Mode',
          child: Column(
            children: [
              _ValueRow(
                label: 'Build',
                value: snapshot.buildLabel,
              ),
              _ValueRow(
                label: 'Current mode',
                value: snapshot.planMode.storageValue,
              ),
              _ValueRow(
                label: 'Hard enforcement active',
                value: _boolLabel(snapshot.hardEnforcementActive),
              ),
              _ValueRow(
                label: 'Paywall active',
                value: _boolLabel(snapshot.paywallActive),
              ),
              _ValueRow(
                label: 'Quota tracking active',
                value: _boolLabel(snapshot.quotaTrackingActive),
              ),
              _ValueRow(
                label: 'Generated at',
                value: _formatDate(snapshot.generatedAt),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DiagnosticsSectionCard(
          title: 'Cloud Usage / Accounting',
          child: snapshot.usageSnapshots.isEmpty
              ? const _EmptyState(message: 'No usage snapshots available yet.')
              : Column(
                  children: snapshot.usageSnapshots
                      .map(
                        (usage) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _UsageSummaryCard(usage: usage),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 12),
        _DiagnosticsSectionCard(
          title: 'Observation Metrics',
          child: Column(
            children: [
              _ValueRow(
                label: 'restoreCount',
                value: snapshot.observationMetrics.restoreCount.toString(),
              ),
              _ValueRow(
                label: 'restoreBurstCount',
                value: snapshot.observationMetrics.restoreBurstCount.toString(),
              ),
              _ValueRow(
                label: 'fullMediaHydrationCount',
                value: snapshot.observationMetrics.fullMediaHydrationCount
                    .toString(),
              ),
              _ValueRow(
                label: 'metadataOnlyRestoreCount',
                value: snapshot.observationMetrics.metadataOnlyRestoreCount
                    .toString(),
              ),
              _ValueRow(
                label: 'thumbnailDownloadCount',
                value: snapshot.observationMetrics.thumbnailDownloadCount
                    .toString(),
              ),
              _ValueRow(
                label: 'fullImageDownloadCount',
                value: snapshot.observationMetrics.fullImageDownloadCount
                    .toString(),
              ),
              _ValueRow(
                label: 'pdfDownloadCount',
                value:
                    snapshot.observationMetrics.pdfDownloadCount.toString(),
              ),
              _ValueRow(
                label: 'estimatedDownloadBytes',
                value: _formatBytes(
                  snapshot.observationMetrics.estimatedDownloadBytes,
                ),
              ),
              _ValueRow(
                label: 'estimatedUploadBytes',
                value: _formatBytes(
                  snapshot.observationMetrics.estimatedUploadBytes,
                ),
              ),
              _ValueRow(
                label: 'repeatedSyncCount',
                value:
                    snapshot.observationMetrics.repeatedSyncCount.toString(),
              ),
              _ValueRow(
                label: 'lastRestoreAt',
                value: _formatNullableDate(
                  snapshot.observationMetrics.lastRestoreAt,
                ),
              ),
              _ValueRow(
                label: 'lastHeavyDownloadAt',
                value: _formatNullableDate(
                  snapshot.observationMetrics.lastHeavyDownloadAt,
                ),
              ),
              _ValueRow(
                label: 'lastSyncAt',
                value: _formatNullableDate(
                  snapshot.observationMetrics.lastSyncAt,
                ),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DiagnosticsSectionCard(
          title: 'Production Guardrail Summary',
          child: snapshot.guardrails.isEmpty
              ? const _EmptyState(
                  message: 'No current guardrail signals recorded.',
                )
              : Column(
                  children: snapshot.guardrails
                      .map(
                        (guardrail) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GuardrailTile(guardrail: guardrail),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 12),
        _DiagnosticsSectionCard(
          title: 'Sync Status Summary',
          child: Column(
            children: [
              _CheckpointSummary(
                title: 'Personal backup checkpoint',
                checkpoint: snapshot.personalCheckpoint,
              ),
              const SizedBox(height: 10),
              _CheckpointGroup(
                title: 'Household/shared checkpoints',
                checkpoints: snapshot.householdCheckpoints,
              ),
              const SizedBox(height: 10),
              _PendingQueueSummary(pendingSyncCounts: snapshot.pendingSyncCounts),
              const SizedBox(height: 10),
              _ValueRow(
                label: 'Fallback summary',
                value: snapshot.fallbackSummary,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DiagnosticsSectionCard(
          title: 'Cache / Media Summary',
          child: Column(
            children: [
              _ValueRow(
                label: 'cached thumbnail count',
                value: snapshot.cacheSummary.thumbnailCount.toString(),
              ),
              _ValueRow(
                label: 'cached full image count',
                value: snapshot.cacheSummary.fullImageCount.toString(),
              ),
              _ValueRow(
                label: 'cached PDF count',
                value: snapshot.cacheSummary.pdfCount.toString(),
              ),
              _ValueRow(
                label: 'invalid cache entry count',
                value: snapshot.cacheSummary.invalidEntryCount.toString(),
              ),
              _ValueRow(
                label: 'orphan cache file count',
                value: snapshot.cacheSummary.orphanFileCount.toString(),
              ),
              _ValueRow(
                label: 'estimated cache bytes',
                value: _formatBytes(snapshot.cacheSummary.estimatedCacheBytes),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _boolLabel(bool value) => value ? 'Yes' : 'No';

  static String _formatDate(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());
  }

  static String _formatNullableDate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }
    return _formatDate(value);
  }

  static String _formatBytes(int value) {
    if (value <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = value.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}

class _DiagnosticsSectionCard extends StatelessWidget {
  const _DiagnosticsSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageSummaryCard extends StatelessWidget {
  const _UsageSummaryCard({
    required this.usage,
  });

  final CloudUsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    final title = usage.scope == 'personal_cloud_plan'
        ? 'Personal backup usage'
        : 'Household ${usage.householdId ?? 'unknown'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          _ValueRow(
            label: 'backedUpItemCount',
            value: usage.backedUpItemCount.toString(),
          ),
          _ValueRow(
            label: 'totalImageCount',
            value: usage.totalImageCount.toString(),
          ),
          _ValueRow(
            label: 'totalPdfCount',
            value: usage.totalPdfCount.toString(),
          ),
          _ValueRow(
            label: 'totalStoredBytes',
            value: _DiagnosticsContent._formatBytes(usage.totalStoredBytes),
          ),
          _ValueRow(
            label: 'householdMemberCount',
            value: usage.householdMemberCount.toString(),
          ),
          _ValueRow(
            label: 'last updated',
            value: _DiagnosticsContent._formatDate(usage.updatedAt),
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _GuardrailTile extends StatelessWidget {
  const _GuardrailTile({
    required this.guardrail,
  });

  final CloudDiagnosticsGuardrailSummary guardrail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final severityColor = guardrail.wouldBlockInProduction
        ? colorScheme.error
        : guardrail.wouldThrottleInProduction
            ? colorScheme.tertiary
            : guardrail.wouldWarnInProduction
                ? colorScheme.primary
                : colorScheme.secondary;
    final severityLabel = guardrail.wouldBlockInProduction
        ? 'Would block'
        : guardrail.wouldThrottleInProduction
            ? 'Would throttle'
            : guardrail.wouldWarnInProduction
                ? 'Would warn'
                : 'Within range';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  guardrail.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Chip(
                label: Text(severityLabel),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ValueRow(
            label: 'reasonCode',
            value: guardrail.reasonCode,
          ),
          _ValueRow(
            label: 'wouldWarnInProduction',
            value: _DiagnosticsContent._boolLabel(
              guardrail.wouldWarnInProduction,
            ),
          ),
          _ValueRow(
            label: 'wouldThrottleInProduction',
            value: _DiagnosticsContent._boolLabel(
              guardrail.wouldThrottleInProduction,
            ),
          ),
          _ValueRow(
            label: 'wouldBlockInProduction',
            value: _DiagnosticsContent._boolLabel(
              guardrail.wouldBlockInProduction,
            ),
          ),
          _ValueRow(
            label: 'currentObservedUsage',
            value: guardrail.currentObservedUsage.toString(),
          ),
          _ValueRow(
            label: 'futureThreshold',
            value: guardrail.futureThreshold.toString(),
          ),
          _ValueRow(
            label: 'message',
            value: guardrail.message,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _CheckpointSummary extends StatelessWidget {
  const _CheckpointSummary({
    required this.title,
    required this.checkpoint,
  });

  final String title;
  final SyncCheckpointState? checkpoint;

  @override
  Widget build(BuildContext context) {
    if (checkpoint == null) {
      return _EmptyState(message: '$title: not available.');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _ValueRow(
            label: 'scope',
            value: checkpoint!.syncScope,
          ),
          _ValueRow(
            label: 'lastSuccessfulPullAt',
            value: _DiagnosticsContent._formatNullableDate(
              checkpoint!.lastSuccessfulPullAt,
            ),
          ),
          _ValueRow(
            label: 'lastSuccessfulPushAt',
            value: _DiagnosticsContent._formatNullableDate(
              checkpoint!.lastSuccessfulPushAt,
            ),
          ),
          _ValueRow(
            label: 'lastFullSyncAt',
            value: _DiagnosticsContent._formatNullableDate(
              checkpoint!.lastFullSyncAt,
            ),
          ),
          _ValueRow(
            label: 'remote checkpoint',
            value: checkpoint!.lastKnownRemoteCheckpoint ?? 'Not available',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _CheckpointGroup extends StatelessWidget {
  const _CheckpointGroup({
    required this.title,
    required this.checkpoints,
  });

  final String title;
  final List<SyncCheckpointState> checkpoints;

  @override
  Widget build(BuildContext context) {
    if (checkpoints.isEmpty) {
      return _EmptyState(message: '$title: none recorded.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...checkpoints.map(
          (checkpoint) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CheckpointSummary(
              title: checkpoint.householdId == null
                  ? checkpoint.syncScope
                  : 'Household ${checkpoint.householdId}',
              checkpoint: checkpoint,
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingQueueSummary extends StatelessWidget {
  const _PendingQueueSummary({
    required this.pendingSyncCounts,
  });

  final Map<String, int> pendingSyncCounts;

  @override
  Widget build(BuildContext context) {
    if (pendingSyncCounts.isEmpty) {
      return const _EmptyState(message: 'Pending sync queue is empty.');
    }

    final entries = pendingSyncCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending sync queue',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _ValueRow(
          label: 'total',
          value: total.toString(),
        ),
        ...entries.map(
          (entry) => _ValueRow(
            label: entry.key,
            value: entry.value.toString(),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
