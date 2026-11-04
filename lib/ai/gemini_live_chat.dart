/// คุยด้วยเสียงสด ๆ กับเจ้าของในแชทด้วย Gemini Live — คู่ของ [RealtimeChat] ฝั่ง Google
///
/// ## ทำไม
///
/// เจ้าของ (2026-11-04): "และ google clound live" แล้วเลือก "Gemini Live ในแชท" · เดิม Gemini Live ใช้ได้แค่ในสาย ·
/// คีย์เดียวกับสมอง Gemini และเสียง Gemini (AI Studio) · เสียงไปที่ Google ที่เดียวกับที่ข้อความแชทไปอยู่แล้ว
/// เมื่อสมองเป็น Gemini · สมองเจ้าอื่น = เจ้าของต้องเลือกยืมเอง (MindState.voiceChatBorrow)
///
/// ## ต่างจาก OpenAI ตรงไหน
///
/// - ไม่มี semantic_vad · จบตาด้วยความเงียบ จึงรอนานกว่าในสาย ([turnSilence]) คนหยุดคิดกลางประโยคไม่โดนตัด
/// - ค้นเว็บด้วย Google Search ของ Live เอง (ไม่ยืมคีย์ OpenAI) · เครื่องมือ web_search ของแชทจึงไม่ส่ง
/// - หยุดกลางประโยคไม่มีคำสั่งยกเลิก · ทิ้งเสียงที่เหลือของตานั้นแทน (GeminiLiveCall.interrupt)
library;

import '../phone/gemini_live_call.dart';
import 'realtime_chat.dart';

class GeminiLiveChat extends GeminiLiveCall with ChatSession {
  GeminiLiveChat({
    required super.apiKey,
    required super.instructions,
    required this.tools,
    required this.runChatTool,
    this.webSearch = false,
    super.voice,
    super.connect,
  }) : super(greeting: '');

  @override
  final List<Map<String, Object?>> tools;
  @override
  final ChatToolRunner runChatTool;

  /// เจ้าของเปิดหาข้อมูลจากอินเทอร์เน็ต · Google Search ของ Live
  final bool webSearch;

  @override
  bool get googleSearch => webSearch;

  /// เท่ากับใจเย็นของ semantic_vad ทาง OpenAI โดยประมาณ · สั้นกว่านี้ตัดคนที่หยุดคิด · ยาวกว่านี้รอเก้อ
  @override
  Duration get turnSilence => const Duration(milliseconds: 1100);

  @override
  String get noteLead => '(Note from your phone app, not words the owner said.) ';
}
