import '../store/knowledge_pack.dart';
import 'strings.dart';

/// ข้อความของแพ็กความรู้ (lib/store/knowledge_pack.dart) และแท็บ "ความรู้" ในร้าน
extension KnowledgeStrings on S {
  String get shopTabLooks => pick('ชุดและตัวละคร', 'Looks');
  String get shopTabKnowledge => pick('ความรู้', 'Knowledge');

  String get kpHowItWorks => pick(
        'มายด์ค้นแพ็กที่เปิดไว้ในเครื่องทุกครั้งที่คุยในแชท จึงใช้ได้แม้ออฟไลน์กับสมองในเครื่อง · '
            'ไม่ใช้ในสายโทรศัพท์',
        'Mind searches the packs you switch on, right on this phone, every time you chat, so they work even '
            'offline with the on-device brain · Not used on phone calls',
      );
  String get kpInstalledTitle => pick('ติดตั้งในเครื่อง', 'On this phone');
  String get kpStoreTitle => pick('ในร้าน', 'In the shop');
  String get kpNoneInstalled => pick('ยังไม่มีแพ็กความรู้ในเครื่อง', 'No knowledge packs on this phone yet');
  String get kpStoreEmpty => pick('ยังไม่มีแพ็กความรู้ในร้าน', 'No knowledge packs in the shop yet');
  String get kpBundledTitle => pick('แพ็กฟรีที่มากับแอป', 'Free pack included with the app');
  String get kpUseInChat => pick('ใช้ในแชท', 'Use in chat');
  String get kpInstall => pick('ติดตั้ง', 'Install');
  String get kpInstalled => pick('ติดตั้งแล้ว', 'Installed');
  String get kpUpdate => pick('อัปเดตแพ็ก', 'Update pack');
  String get kpTryAsking => pick('ลองถาม', 'Try asking');
  String get kpRead => pick('อ่าน', 'Read');
  String get kpAskAbout => pick('ถามมายด์เรื่องนี้', 'Ask Mind about this');
  String get kpGone => pick('แพ็กนี้ถูกลบออกจากเครื่องแล้ว', 'This pack was removed from this phone');
  String get kpTradingNote => pick(
        'ความรู้เพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน · มายด์จะไม่บอกให้ซื้อหรือขายตัวไหน',
        'For learning, not investment advice · Mind will not tell you what to buy or sell',
      );

  String kpTopics(int n, String version) => pick('$n หัวข้อ · รุ่น $version', '$n topics · v$version');
  String kpReady(String name) => pick('"$name" พร้อมใช้ในแชทแล้ว', '"$name" is ready in chat');
  String kpRemoveConfirm(String name) => pick(
        'ลบ "$name" ออกจากเครื่อง? ถ้าซื้อไว้แล้วโหลดใหม่จากร้านได้เสมอ',
        'Remove "$name" from this phone? If you bought it, you can download it again from the shop',
      );
  String get kpSaveFailed => pick('บันทึกไม่สำเร็จ ลองใหม่อีกครั้ง', 'Could not save, please try again');

  String kpCategory(PackCategory c) => switch (c) {
        PackCategory.cooking => pick('ทำอาหาร', 'Cooking'),
        PackCategory.survival => pick('เอาตัวรอด', 'Survival'),
        PackCategory.firstAid => pick('ปฐมพยาบาล', 'First aid'),
        PackCategory.engine => pick('เครื่องยนต์', 'Engines'),
        PackCategory.trading => pick('การลงทุน', 'Investing'),
        PackCategory.general => pick('แพ็กความรู้', 'Knowledge pack'),
      };

  /// บอกเหตุผลที่ผู้ใช้ทำอะไรต่อได้ · ไม่ใช่ "ผิดพลาด" เฉย ๆ
  String kpError(KnowledgePackError e) => switch (e) {
        KnowledgePackError.network => pick('โหลดไม่สำเร็จ ลองเช็คเน็ตแล้วกดใหม่', 'Download failed, check your connection and try again'),
        KnowledgePackError.hashMismatch => pick(
            'ไฟล์ที่โหลดมาไม่ครบหรือไม่ตรงกับในร้าน ลองโหลดใหม่อีกครั้ง',
            'The downloaded file is incomplete or does not match the shop, please try again'),
        KnowledgePackError.badPack => pick(
            'แพ็กนี้เสียหรือไม่ตรงกับที่ซื้อ แจ้งร้านได้เลย', 'This pack is damaged or not the one you bought, please tell the shop'),
        KnowledgePackError.notKnowledge => pick('ไฟล์นี้ไม่ใช่แพ็กความรู้', 'This file is not a knowledge pack'),
        KnowledgePackError.tooLarge => pick(
            'แพ็กใหญ่เกินที่เครื่องรับได้ ลบแพ็กที่ไม่ใช้ออกก่อน', 'The pack is too large for this phone, remove packs you do not use first'),
        KnowledgePackError.needsUpdate => pick(
            'แพ็กนี้ต้องใช้แอปรุ่นใหม่กว่านี้ อัปเดตแอปก่อนนะคะ', 'This pack needs a newer version of the app, please update first'),
        KnowledgePackError.busy => pick('กำลังติดตั้งแพ็กอื่นอยู่ รอสักครู่', 'Another pack is installing, please wait'),
      };
}
