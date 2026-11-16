import 'package:material_ui/material_ui.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry, this.compact = false});

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card.filled(
      color: colors.errorContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 8, compact ? 4 : 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.cloud_off_outlined, size: 20, color: colors.onErrorContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('暂时无法更新', style: text.titleSmall?.copyWith(color: colors.onErrorContainer)),
            const SizedBox(height: 4),
            Text(message, style: text.bodySmall?.copyWith(color: colors.onErrorContainer)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
                onPressed: onRetry, child: const Text('重试'),
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}
