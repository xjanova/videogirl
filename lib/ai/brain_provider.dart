/// ที่มาของ "ความคิด" ของมินเดะ — เลือกได้ว่าจะให้ใครประมวลผล
///
/// สามทางนี้แลกกันคนละแบบจริง ๆ ไม่ใช่แค่ชื่อต่างกัน:
/// ฉลาด ↔ เป็นส่วนตัว ↔ ไม่ต้องมีเน็ต เลือกได้อย่างมากสองในสาม
enum BrainProvider {
  openai(
    'OpenAI',
    'ฉลาดที่สุด ตอบไทยเป็นธรรมชาติที่สุด',
    'ข้อความทุกคำถูกส่งออกอินเทอร์เน็ต · ต้องมีเน็ต · มีค่าใช้จ่ายต่อครั้ง',
  ),
  homeServer(
    'เซิร์ฟเวอร์ในบ้าน',
    'Ollama / LM Studio / llama.cpp บนคอมที่บ้าน',
    'ข้อมูลไม่ออกนอกบ้าน · ฟรี · แต่ต้องอยู่วงไวไฟเดียวกับคอม และคอมต้องเปิด',
  ),
  onDevice(
    'ในเครื่อง',
    'Gemma 4 รันบนมือถือเลย',
    'ออฟไลน์จริง ไม่ต้องมีเน็ตเลย · ฟรี · แต่ต้องโหลดโมเดล 2–3 GB และตอบช้ากว่า',
  );

  const BrainProvider(this.label, this.summary, this.tradeoff);

  final String label;

  /// จุดเด่นสั้น ๆ
  final String summary;

  /// สิ่งที่ต้องแลก — เขียนให้ตรงไปตรงมา ผู้ใช้ควรรู้ก่อนเลือก
  final String tradeoff;

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

  /// เขียนเป็นคำแนะนำในหน้าตั้งค่า
  static const hint = 'ใส่ IP ของคอมที่รัน Ollama เช่น http://192.168.1.100:11434/v1\n'
      'บนคอมต้องตั้ง OLLAMA_HOST=0.0.0.0 ก่อน ไม่งั้นมันรับเฉพาะ localhost';
}
