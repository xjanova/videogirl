/// หน้ากั้นตอนเปิดแอปบนเครื่องที่แรมไม่ถึง
///
/// **กันตั้งแต่ติดตั้งไม่ได้** — แอปนี้แจกผ่าน GitHub Releases ไม่ใช่ Play Store
/// ฝั่ง Android กันได้แค่เวอร์ชัน OS ผ่าน `minSdk` ไม่มีด่านตามขนาดแรมสำหรับ
/// การ sideload (ตัวกรองตามสเปคเครื่องเป็นของ Play Console ซึ่งเราไม่ได้ใช้)
///
/// ที่ทำได้จริงคือบอกทันทีที่เปิดครั้งแรก **ก่อน**ผู้ใช้จะเสียเน็ตโหลดโมเดล 2 GB
/// มาแล้วเจอแอปเด้งกลางบทสนทนา ซึ่งคนอ่านว่า "แอปพัง" ไม่ใช่ "เครื่องไม่ไหว"
library;

import 'package:flutter/material.dart';

import '../ai/device_capability.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';

class UnsupportedDeviceScreen extends StatelessWidget {
  const UnsupportedDeviceScreen({
    super.key,
    required this.verdict,
    required this.onContinueAnyway,
  });

  final DeviceVerdict verdict;

  /// ยังปล่อยให้เข้าได้ ไม่ใช่ทางตัน
  ///
  /// สองเหตุผล: กันตอนติดตั้งจริง ๆ ไม่ได้อยู่แล้ว การทำกำแพงตายจึงกันได้แค่
  /// คนที่ยอมทำตาม · และเครื่องแรมน้อย**ยังใช้เซิร์ฟเวอร์ในบ้านได้อยู่**
  /// ปิดตายจะกันคนกลุ่มนั้นออกไปด้วยทั้งที่เขาใช้ได้จริง
  ///
  /// จึงทำเป็นทางรอง (TextButton) ไม่ใช่ปุ่มหลัก — เห็นได้แต่ไม่ชวนกด
  final VoidCallback onContinueAnyway;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.memory_outlined,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 20),
                Text(
                  s.ramBlockedTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  s.ramBlockedDetail(verdict.gb, DeviceCapability.minLocalGb),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                Text(
                  s.ramBlockedHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onContinueAnyway,
                  child: Text(s.ramBlockedAnyway),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
