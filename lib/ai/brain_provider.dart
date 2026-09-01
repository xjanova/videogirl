/// ที่มาของ "ความคิด" ของมายด์ — เลือกได้ว่าจะให้ใครประมวลผล
///
/// สามทางนี้แลกกันคนละแบบจริง ๆ ไม่ใช่แค่ชื่อต่างกัน:
/// ฉลาด ↔ เป็นส่วนตัว ↔ ไม่ต้องมีเน็ต เลือกได้อย่างมากสองในสาม
/// ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart — enum เก็บแค่ตัวตน
enum BrainProvider {
  /// ผ่านหลังบ้านของเรา — **ผู้ใช้ไม่ต้องมีคีย์เอง**
  ///
  /// คีย์อยู่ที่เซิร์ฟเวอร์และไม่เคยถูกส่งลงมาที่เครื่อง แอปยืนยันตัวด้วย
  /// license key ของตัวเอง (ตัวเดียวกับที่ใช้กับร้าน) แล้วเซิร์ฟเวอร์เป็นคน
  /// ไปคุยกับ OpenAI ให้ · แกะ APK ก็ไม่เจอคีย์เพราะมันไม่เคยอยู่ในนั้น
  mindProxy,

  /// คีย์ของผู้ใช้เอง กรอกในหน้าตั้งค่า เก็บใน Keystore ของเครื่องเขา
  openai,

  homeServer,
  onDevice;

  bool get needsInternet => this != BrainProvider.onDevice;

  /// ข้อความหลุดออกนอกเครื่องไหม — ใช้เตือนตอนเปิดใช้กับข้อมูลอ่อนไหว
  bool get leavesDevice => this != BrainProvider.onDevice;

  /// ต้องมีคีย์ของผู้ใช้เองไหม — มีแค่ทางเดียวที่ต้อง
  bool get needsOwnKey => this == BrainProvider.openai;
}

/// ค่าตั้งต้นของเซิร์ฟเวอร์ในบ้าน
abstract final class HomeServerDefaults {
  /// Ollama เปิดพอร์ต 11434 และมี endpoint เข้ากันได้กับ OpenAI ที่ /v1
  /// จึงใช้ client ตัวเดียวกับ OpenAI ได้เลย ไม่ต้องเขียนใหม่
  static const baseUrl = 'http://192.168.1.100:11434/v1';

  static const model = 'gemma4:latest';



}
