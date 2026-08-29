/// ที่มาของ "ความคิด" ของมายด์ — เลือกได้ว่าจะให้ใครประมวลผล
///
/// สามทางนี้แลกกันคนละแบบจริง ๆ ไม่ใช่แค่ชื่อต่างกัน:
/// ฉลาด ↔ เป็นส่วนตัว ↔ ไม่ต้องมีเน็ต เลือกได้อย่างมากสองในสาม
/// ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart — enum เก็บแค่ตัวตน
enum BrainProvider {
  openai,
  homeServer,
  onDevice;

  bool get needsInternet => this != BrainProvider.onDevice;

  /// ข้อความหลุดออกนอกเครื่องไหม — ใช้เตือนตอนเปิดใช้กับข้อมูลอ่อนไหว
  bool get leavesDevice => this != BrainProvider.onDevice;
}

/// ค่าตั้งต้นของเซิร์ฟเวอร์ในบ้าน
abstract final class HomeServerDefaults {
  /// Ollama เปิดพอร์ต 11434 และมี endpoint เข้ากันได้กับ OpenAI ที่ /v1
  /// จึงใช้ client ตัวเดียวกับ OpenAI ได้เลย ไม่ต้องเขียนใหม่
  static const baseUrl = 'http://192.168.1.100:11434/v1';

  static const model = 'gemma4:latest';



}
