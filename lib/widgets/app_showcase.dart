import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

import '../theme/app_colors.dart';

const appShowcaseTooltipActionConfig = TooltipActionConfig(
  alignment: MainAxisAlignment.spaceBetween,
  position: TooltipActionPosition.inside,
  gapBetweenContentAndAction: 14,
  crossAxisAlignment: CrossAxisAlignment.center,
);

/// Tooltip action buttons for showcase tours.
///
/// Uses the built-in [TooltipDefaultActionType] instead of custom widgets
/// because tooltip actions are rendered in an overlay — not as a descendant
/// of [ShowCaseWidget] — so [ShowCaseWidget.of(context)] would fail.
List<TooltipActionButton> appShowcaseTooltipActions() {
  return [
    TooltipActionButton(
      type: TooltipDefaultActionType.skip,
      backgroundColor: Colors.transparent,
      textStyle: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      border: Border.all(color: Colors.white24),
    ),
    TooltipActionButton(
      type: TooltipDefaultActionType.next,
      backgroundColor: AppColors.primary,
      textStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    ),
  ];
}
