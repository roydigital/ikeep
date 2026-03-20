import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

import '../theme/app_colors.dart';

const appShowcaseTooltipActionConfig = TooltipActionConfig(
  alignment: MainAxisAlignment.spaceBetween,
  position: TooltipActionPosition.inside,
  gapBetweenContentAndAction: 14,
  crossAxisAlignment: CrossAxisAlignment.center,
);

List<TooltipActionButton> appShowcaseTooltipActions() {
  return [
    TooltipActionButton.custom(
      button: const _AppShowcaseActionButton(
        label: 'Skip',
        outlined: true,
        action: _AppShowcaseAction.skip,
      ),
    ),
    TooltipActionButton.custom(
      button: const _AppShowcaseActionButton(
        label: 'Next',
        action: _AppShowcaseAction.next,
      ),
    ),
  ];
}

enum _AppShowcaseAction { skip, next }

class _AppShowcaseActionButton extends StatelessWidget {
  const _AppShowcaseActionButton({
    required this.label,
    required this.action,
    this.outlined = false,
  });

  final String label;
  final _AppShowcaseAction action;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 6 : 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            final showcase = ShowCaseWidget.of(context);
            switch (action) {
              case _AppShowcaseAction.skip:
                showcase.dismiss();
              case _AppShowcaseAction.next:
                showcase.next();
            }
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minWidth: 92),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: outlined ? Colors.transparent : AppColors.primary,
              borderRadius: BorderRadius.circular(999),
              border: outlined
                  ? Border.all(color: Colors.white24)
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: outlined ? Colors.white70 : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
