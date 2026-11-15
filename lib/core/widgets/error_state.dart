import 'package:material_ui/material_ui.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry, this.compact = false});

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 24),
      decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.cloud_off_outlined, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(child: Text('暂时无法更新', style: TextStyle(color: colors.onErrorContainer, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: colors.onErrorContainer)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重试')),
        ],
      ),
    );
  }
}
