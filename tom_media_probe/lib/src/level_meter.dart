import 'package:flutter/material.dart';

/// A level meter over a value in dBFS (0 is full scale, -60 and below empty).
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.dbfs});

  final double? dbfs;

  @override
  Widget build(BuildContext context) {
    final double db = (dbfs ?? -160).clamp(-60, 0).toDouble();
    final double fraction = (db + 60) / 60;
    final Color color = db > -3
        ? Colors.red
        : db > -12
        ? Colors.orange
        : Colors.green;
    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 14,
              color: color,
              backgroundColor: Colors.black12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            dbfs == null ? '- dBFS' : '${db.toStringAsFixed(0)} dBFS',
          ),
        ),
      ],
    );
  }
}
