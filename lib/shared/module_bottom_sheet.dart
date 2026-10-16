import 'package:flutter/material.dart';

class ModuleBottomSheet extends StatelessWidget {
  const ModuleBottomSheet({
    required this.title,
    this.actions,
    this.titleAction,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? actions;
  final Widget? titleAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?titleAction,
              ],
            ),
            const SizedBox(height: 16),
            child,
            if (actions case final actions?) ...[
              const SizedBox(height: 20),
              actions,
            ],
          ],
        ),
      ),
    );
  }
}
