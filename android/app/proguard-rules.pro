# กฎ R8 สำหรับ build release
#
# ไม่มีไฟล์นี้ = `flutter build apk --release` ตายที่ :app:minifyReleaseWithR8
# ตั้งแต่ยังไม่ทันเซ็นไฟล์ (เจอตอนทำ auto-release 31 ส.ค. 2026)

# MediaPipe (มาทาง flutter_gemma) อ้างคลาส proto สองตัวที่ไม่ได้แพ็กมาใน aar
# R8 ถือว่าคลาสหายคือ error ไม่ใช่ warning — สองบรรทัดนี้คือสิ่งที่ AGP บอกให้ใส่
# ดูของจริงได้ที่ build/app/outputs/mapping/release/missing_rules.txt
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

# MediaPipe กับ flutter_gemma เรียกคลาสฝั่ง Java กลับมาผ่าน JNI ซึ่ง R8 มองไม่เห็น
# ปล่อยไว้ R8 จะตัดทิ้งเพราะคิดว่าไม่มีใครเรียก แล้วไปตายตอนรันจริงเป็น
# NoSuchMethodError/ClassNotFoundException โดยไม่มีอะไรเตือนตอน build เลย
-keep class com.google.mediapipe.** { *; }
-keep class dev.flutterberlin.flutter_gemma.** { *; }
