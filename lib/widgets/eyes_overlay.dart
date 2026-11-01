/// สัญญาณ "กล้องเปิดอยู่" · ภาพตัวเองมุมจอ จุดแดง บอกว่าภาพไปที่ไหน และปุ่มปิดทันที
///
/// 🔴 กล้องเปิดอยู่ต้องเห็นเสมอ · วางใน MaterialApp.builder เหนือ Navigator ทุกหน้าที่เปิดทับจึงบังไม่ได้ ·
/// ตรงนั้นไม่มี Overlay จึงใช้ tooltip ไม่ได้
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/mind_eyes.dart';
import '../i18n/strings.dart';

class EyesOverlay extends StatelessWidget {
  const EyesOverlay({super.key, required this.eyes});

  final MindEyes eyes;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: eyes,
        builder: (context, _) {
          if (!eyes.showing) return const SizedBox.shrink();
          final t = S.of(context);
          return Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            width: 132,
            child: Material(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              elevation: 6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      AspectRatio(aspectRatio: 3 / 4, child: ClipRect(child: eyes.preview())),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Semantics(
                          button: true,
                          label: t.eyesOff,
                          child: IconButton(
                            onPressed: () => unawaited(eyes.turnOff()),
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.circle, size: 9, color: Color(0xFFFF3B30)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(t.eyesOnLabel,
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(t.eyesWhere, style: const TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
