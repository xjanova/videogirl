import '../ai/provider_connection.dart';
import 'strings.dart';

extension ConnectionStrings on S {
  String get connectionTest => pick('ทดสอบการเชื่อมต่อ', 'Test connection');
  String get connectionTesting => pick('กำลังทดสอบ…', 'Testing…');
  String connectionResult(ConnectionResult result) => switch (result) {
    ConnectionResult.connected => pick(
      'เชื่อมต่อสำเร็จ · คีย์และสิทธิ์อ่านรายการใช้ได้ การใช้งานจริงยังขึ้นกับสิทธิ์รุ่นและเครดิต',
      'Connected · key and list access verified. Actual use also depends on model access and credit.',
    ),
    ConnectionResult.missingKey => pick('กรอกคีย์ก่อนทดสอบ', 'Enter an API key first.'),
    ConnectionResult.missingRegion => pick(
      'กรอกภูมิภาค Azure ก่อนทดสอบ',
      'Enter your Azure region first.',
    ),
    ConnectionResult.invalidRegion => pick(
      'ภูมิภาค Azure ไม่ถูกต้อง เช่น southeastasia',
      'Invalid Azure region, e.g. southeastasia.',
    ),
    ConnectionResult.badKey => pick(
      'คีย์ใช้ไม่ได้หรือหมดอายุ · ตรวจคีย์อีกครั้ง',
      'Invalid or expired API key. Check your key.',
    ),
    ConnectionResult.forbidden => pick(
      'ไม่มีสิทธิ์เข้าถึง · ตรวจคีย์ สิทธิ์ API และภูมิภาค',
      'Access denied. Check the key, API permissions and region.',
    ),
    ConnectionResult.quota => pick(
      'บริการจำกัดคำขอหรือเครดิตไม่พอ · ตรวจบัญชีแล้วลองใหม่',
      'Request limit or insufficient credit. Check your account and retry.',
    ),
    ConnectionResult.offline => pick(
      'เชื่อมต่อไม่ถึงหรือหมดเวลา · ตรวจอินเทอร์เน็ตแล้วลองใหม่',
      'Unreachable or timed out. Check your internet and retry.',
    ),
    ConnectionResult.failed => pick(
      'บริการตอบกลับผิดปกติ · ลองใหม่อีกครั้ง',
      'Unexpected service response. Please retry.',
    ),
  };
}
