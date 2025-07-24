import 'package:flutter/material.dart';

class ControlPanel extends StatelessWidget {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8.0),
      ),
      margin: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('系统状态', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('运行正常'),
            ],
          ),
          Row(
            children: [
              _buildStatusIndicator(context, 'CPU', 25, Colors.green),
              const SizedBox(width: 16),
              _buildStatusIndicator(context, '内存', 45, Colors.orange),
              const SizedBox(width: 16),
              _buildStatusIndicator(context, '网络', 10, Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  // 状态指示器
  Widget _buildStatusIndicator(
    BuildContext context,
    String label,
    double value,
    Color color,
  ) {
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text('${value.toInt()}%', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
