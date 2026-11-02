/// แท็ก `[[ทำในเครื่อง: …]]` ที่เธอเขียนในแชทเมื่อเจ้าของสั่งงานที่ต้องทำในมือถือ
///
/// สอนไว้ที่ MindPersona.phoneControlBlock · MindState อ่านแล้วส่งให้ PhoneAgent ·
/// แท็กไม่ขึ้นจอ ไม่ถูกอ่านออกเสียง
library;

/// คำของเจ้าของเรื่องกล้อง · ตัดสินในเครื่อง ไม่ใช่จากโมเดล (ดู MindEyes)
abstract final class EyesWords {
  /// ขอให้เปิด/ดู/ถ่าย · ไม่มีคำเหล่านี้ = โมเดลคิดเปิดเอง หรือถูกข้อความจากที่อื่นสั่ง
  /// "ดู" เดี่ยว ๆ ไม่นับ เพราะ "ดูข่าว" "ดูแรม" ไม่ใช่การขอให้มอง · "ดูหน้า" "ดูหน่อย" "ดูนี่" นับ
  static final ask = RegExp(
    r'กล้อง|ถ่าย|เซลฟี่|มอง|เห็น(?!ด้วย)|ดู(หน้า|หน่อย|นี่|นี้|นั่น|ซิ|สิ|ดิ|ที|ฉัน|ผม|เรา|พี่|ชุด|รูป|ภาพ)|'
    r'camera|photo|picture|selfie|look(?!\s+up)|\bsee\b',
    caseSensitive: false,
  );

  /// (?<!เ) เพราะ "ปิดกล้อง" ซ้อนอยู่ใน "เปิดกล้อง" · ไม่กันคือสั่งเปิดแล้วปิดทันที
  static final _off = RegExp(
    r'(?<!เ)ปิดกล้อง|(?<!เ)ปิดตา|เลิกมอง|หยุดมอง|ไม่ต้องมอง|พอแล้วไม่ต้องดู|camera off|close the camera|turn off the camera|stop looking',
    caseSensitive: false,
  );

  /// สั่งปิดกล้อง · ไม่ผ่านโมเดล · ต้องปิดทันที
  static bool off(String text) => _off.hasMatch(text);
}

/// คำของเจ้าของเรื่องหน้าจอ · ตัดสินในเครื่อง · โมเดลหรือข้อความบนเว็บสั่งดูจอเองไม่ได้
abstract final class ScreenWords {
  /// 🔴 "จอ" เดี่ยว ๆ ไม่นับ เพราะอยู่ใน "เจอ" และ "จองโต๊ะ"
  static final _ask = RegExp(
    r'หน้าจอ|(ดู|ใน|บน|ที่|เห็น)จอ(?!ง)|จอ(มือถือ|โทรศัพท์|นี้)|แคป|สกรีน|อ่านให้|อ่านหน่อย|screen|capture',
    caseSensitive: false,
  );

  /// ขอเก็บภาพ ไม่ใช่แค่ดู
  static final _keep = RegExp(r'แคป|เก็บ|บันทึก|เซฟ|screenshot|screen ?cap|\bsave\b', caseSensitive: false);

  static bool asks(String text) => _ask.hasMatch(text) || EyesWords.ask.hasMatch(text);
  static bool keeps(String text) => _keep.hasMatch(text);
}

/// งานในเครื่องที่จริง ๆ คือการโทร · 🔴 สายต้องไปทางกล่องยืนยันของเธอเท่านั้น
///
/// เจ้าของ: "มายด์เธอไปใช้การโทรของเครื่อง แทนที่จะใช้ของตัวเอง" · มือไปกดแอปโทรศัพท์ = ไม่มีกล่องยืนยัน ไม่มีบทเปิด
/// และเธอไม่ได้คุยในสาย · โทรผ่านแอปอื่น (LINE) ไม่เกี่ยว เธอมีทางเดียวคือใช้มือ
abstract final class CallGoal {
  static final _dial = RegExp(
    r'โทรหา|โทรออก|โทรไป|โทรกลับ|กดโทร|ต่อสาย|แอ[ปพ]โทรศัพท์|แป้นโทร|'
    r'\bdial|\b(make|place) a (phone )?call\b|\bcall\s+(?!logs?\b|history\b|record|setting)\S|\bphone app\b',
    caseSensitive: false,
  );
  static final _otherApp = RegExp(
    r'\bline\b|ไลน์|messenger|whatsapp|telegram|zoom|discord|facetime|skype|\bmeet\b',
    caseSensitive: false,
  );

  static bool isPhoneCall(String goal) => _dial.hasMatch(goal) && !_otherApp.hasMatch(goal);
}

/// คำสั่งคุมเครื่องหนึ่งคำสั่ง · [action] ตรงกับ DeviceControl.kt
typedef DeviceOrder = ({String action, int? level, String? stream});

/// แก้ตารางแอปหนึ่งครั้ง · [action]: set_category set_order add_alias
typedef AppEdit = ({String action, String app, String value});

/// แปลคำในแท็ก `[[เสียง: …]]` `[[ไฟฉาย: …]]` `[[เพลง: …]]` `[[โหมดเสียง: …]]` เป็นคำสั่ง · ไม่เข้าใจ = null ไม่ทำอะไร
abstract final class DeviceWords {
  static const actions = [
    'volume_up', 'volume_down', 'volume_set', 'volume_mute', 'volume_unmute', 'flashlight_on', 'flashlight_off',
    'media_play', 'media_pause', 'media_next', 'media_previous', 'ringer_normal', 'ringer_vibrate',
  ];

  /// (?<!เ) เพราะ "ปิด" ซ้อนอยู่ใน "เปิด" · ไม่กันคือ "เปิดเสียง" กลายเป็นปิดเสียง
  static final _off = RegExp(r'(?<!เ)ปิด|\boff\b', caseSensitive: false);
  static final _on = RegExp(r'เปิด|\bon\b', caseSensitive: false);

  static String? _stream(String t) {
    if (RegExp(r'เรียกเข้า|\bring', caseSensitive: false).hasMatch(t)) return 'ring';
    if (RegExp(r'ปลุก|alarm', caseSensitive: false).hasMatch(t)) return 'alarm';
    if (RegExp(r'แจ้งเตือน|notification', caseSensitive: false).hasMatch(t)) return 'notification';
    if (RegExp(r'ในสาย|\bcall\b', caseSensitive: false).hasMatch(t)) return 'call';
    if (RegExp(r'เพลง|สื่อ|วิดีโอ|\b(media|music|video)\b', caseSensitive: false).hasMatch(t)) return 'media';
    return null;
  }

  static DeviceOrder? volume(String said) {
    final stream = _stream(said);
    final n = RegExp(r'[0-9]{1,3}').firstMatch(said);
    if (n != null) return (action: 'volume_set', level: int.parse(n[0]!).clamp(0, 100), stream: stream);
    String? action;
    if (RegExp(r'unmute', caseSensitive: false).hasMatch(said)) {
      action = 'volume_unmute';
    } else if (RegExp(r'\bmute\b|เงียบ', caseSensitive: false).hasMatch(said) || _off.hasMatch(said)) {
      action = 'volume_mute';
    } else if (RegExp(r'ดัง|เพิ่ม|เร่ง|\bup\b|louder', caseSensitive: false).hasMatch(said)) {
      action = 'volume_up';
    } else if (RegExp(r'เบา|ลด|\bdown\b|quieter|softer|lower', caseSensitive: false).hasMatch(said)) {
      action = 'volume_down';
    } else if (_on.hasMatch(said)) {
      action = 'volume_unmute';
    }
    return action == null ? null : (action: action, level: null, stream: stream);
  }

  static DeviceOrder? torch(String said) {
    if (_off.hasMatch(said)) return (action: 'flashlight_off', level: null, stream: null);
    if (_on.hasMatch(said)) return (action: 'flashlight_on', level: null, stream: null);
    return null;
  }

  static DeviceOrder? media(String said) {
    String? action;
    if (RegExp(r'หยุด|พัก|pause|stop', caseSensitive: false).hasMatch(said)) {
      action = 'media_pause';
    } else if (RegExp(r'ถัดไป|ต่อไป|ข้าม|next|skip', caseSensitive: false).hasMatch(said)) {
      action = 'media_next';
    } else if (RegExp(r'ก่อนหน้า|ย้อน|prev|back', caseSensitive: false).hasMatch(said)) {
      action = 'media_previous';
    } else if (RegExp(r'เล่น|play|resume', caseSensitive: false).hasMatch(said)) {
      action = 'media_play';
    }
    return action == null ? null : (action: action, level: null, stream: null);
  }

  static DeviceOrder? ringer(String said) {
    if (RegExp(r'สั่น|vibrate', caseSensitive: false).hasMatch(said)) {
      return (action: 'ringer_vibrate', level: null, stream: null);
    }
    if (RegExp(r'ปกติ|normal|ดัง|\bring', caseSensitive: false).hasMatch(said)) {
      return (action: 'ringer_normal', level: null, stream: null);
    }
    return null;
  }
}

/// คำเกี่ยวกับหมวดแอป · เดาหมวดจากชื่อ และแปลงคำที่เจ้าของพูดเป็นคีย์ของหมวด
abstract final class AppWords {
  static const categories = [
    'chat', 'social', 'video', 'music', 'photo', 'game', 'shopping', 'food', 'travel', 'finance', 'work', 'news',
    'tools', 'other',
  ];

  static const _said = {
    'แชท': 'chat', 'แชต': 'chat', 'สนทนา': 'chat', 'โซเชียล': 'social', 'วิดีโอ': 'video', 'หนัง': 'video',
    'เพลง': 'music', 'ดนตรี': 'music', 'รูป': 'photo', 'รูปภาพ': 'photo', 'ภาพ': 'photo', 'กล้อง': 'photo',
    'เกม': 'game', 'ช้อปปิ้ง': 'shopping', 'ช้อป': 'shopping', 'ซื้อของ': 'shopping', 'อาหาร': 'food',
    'เดินทาง': 'travel', 'แผนที่': 'travel', 'การเงิน': 'finance', 'ธนาคาร': 'finance', 'งาน': 'work',
    'ทำงาน': 'work', 'ข่าว': 'news', 'เครื่องมือ': 'tools', 'อื่นๆ': 'other', 'อื่น ๆ': 'other', 'อื่น': 'other',
  };

  /// ตามลำดับนี้ · เจอกลุ่มแรกหยุด
  static final _guess = <(String, RegExp)>[
    ('finance', RegExp(r'\bbank|wallet|truemoney|paypal|binance|bitkub|krungthai|krungsri|ธนาคาร|กระเป๋าเงิน', caseSensitive: false)),
    ('chat', RegExp(r'\bline\b|messenger|whatsapp|telegram|discord|wechat|viber|\bsignal\b|\bsms\b|\bmms\b|messag|ข้อความ', caseSensitive: false)),
    ('social', RegExp(r'facebook|instagram|tiktok|twitter|threads|reddit|snapchat|pinterest', caseSensitive: false)),
    ('video', RegExp(r'youtube|netflix|disney|\bviu\b|wetv|iqiyi|video|วิดีโอ', caseSensitive: false)),
    ('music', RegExp(r'spotify|joox|music|soundcloud|podcast|เพลง', caseSensitive: false)),
    ('photo', RegExp(r'camera|gallery|photo|album|capcut|canva|lightroom|กล้อง|รูปภาพ|แกลเลอรี', caseSensitive: false)),
    ('game', RegExp(r'game|garena|roblox|pubg|minecraft|\brov\b|เกม', caseSensitive: false)),
    ('shopping', RegExp(r'shopee|lazada|\bshop|amazon|aliexpress|temu|ช้อป', caseSensitive: false)),
    ('food', RegExp(r'grab|lineman|foodpanda|robinhood|mcdonald|starbucks|\bkfc\b|\bfood|อาหาร', caseSensitive: false)),
    ('travel', RegExp(r'\bmaps?\b|agoda|booking|airbnb|traveloka|airasia|\buber\b|\bbolt\b|แผนที่', caseSensitive: false)),
    ('work', RegExp(r'mail|outlook|calendar|\bdrive\b|\bdocs\b|sheets|slides|office|excel|powerpoint|\bteams\b|zoom|notion|slack|เมล|ปฏิทิน', caseSensitive: false)),
    ('news', RegExp(r'\bnews|ข่าว', caseSensitive: false)),
    ('tools', RegExp(r'settings|clock|calculator|\bfile|browser|chrome|ตั้งค่า|นาฬิกา|เครื่องคิดเลข|ไฟล์', caseSensitive: false)),
  ];

  /// หมวดของแอป · แอปที่มือแตะไม่ได้เป็นการเงินเสมอ · ชื่อบอกชัดกว่าหมวดที่แอปประกาศเอง
  static String guess(String pkg, String label, String declared, {bool blocked = false}) {
    if (blocked) return 'finance';
    final name = '${pkg.replaceAll('.', ' ')} $label';
    for (final (category, words) in _guess) {
      if (words.hasMatch(name)) return category;
    }
    return declared.isNotEmpty ? declared : 'other';
  }

  /// คำที่เจ้าของพูดเป็นคีย์หมวด · ไม่ตรงหมวดไหน = ชื่อหมวดใหม่ของเขาเอง
  static String category(String said) {
    final t = said.trim().toLowerCase().replaceFirst(RegExp(r'^(หมวด(หมู่)?|แอ[ปพ])\s*'), '').trim();
    final key = _said[t] ?? t;
    final name = key.replaceAll(RegExp(r'[\[\]|\n]'), '').trim();
    return name.length <= 30 ? name : name.substring(0, 30).trim();
  }

  static bool isNew(String q) => RegExp(r'^(ใหม่|ล่าสุด|เข้าออก|new|recent|changes?)$', caseSensitive: false).hasMatch(q);
  static bool isAll(String q) => RegExp(r'^(|ทั้งหมด|ทุกหมวด|หมวด|all|categories)$', caseSensitive: false).hasMatch(q);
}

/// แท็กของที่เธอทำได้ทันทีไม่ต้องใช้มือ: `[[เปิดแอป: YouTube]]` · `[[เปิดเสียงสาย: ชื่อ]]` · `[[ถ่ายรูป: หลัง]]` ·
/// `[[เสียง: เบาลง]]` · `[[ไฟฉาย: เปิด]]` · `[[เพลง: หยุด]]` · `[[หมวดแอป: LINE | งาน]]`
abstract final class QuickTag {
  static final _app = RegExp(r'\[\[\s*(เปิดแอป|เปิดแอพ|open app)\s*[:：]\s*([^\]\n]{1,80})\]\]', caseSensitive: false);
  static final _recording =
      RegExp(r'\[\[\s*(เปิดเสียงสาย|play recording)\s*(?:[:：]\s*([^\]\n]{0,80}))?\]\]', caseSensitive: false);
  static final _photo = RegExp(r'\[\[\s*(ถ่ายรูป|take photo)\s*(?:[:：]\s*([^\]\n]{0,20}))?\]\]', caseSensitive: false);

  /// เสียง ไฟฉาย เพลง โหมดเสียงเรียกเข้า · ตอบเดียวสั่งได้หลายอย่าง ("ปิดไฟฉายแล้วเบาเสียง")
  static final _device = RegExp(
    r'\[\[\s*(เสียง|volume|ไฟฉาย|flashlight|torch|เพลง|media|โหมดเสียง|ringer)\s*[:：]\s*([^\]\n]{1,40})\]\]',
    caseSensitive: false,
  );

  static final _appEdit = RegExp(
    r'\[\[\s*(หมวดแอป|หมวดแอพ|app category|ลำดับแอป|ลำดับแอพ|app order|ชื่อแอป|ชื่อแอพ|app alias)\s*[:：]\s*'
    r'([^\]\n|]{1,60})\|\s*([^\]\n|]{1,40})\]\]',
    caseSensitive: false,
  );

  static List<DeviceOrder> _devices(String reply) => [
        for (final m in _device.allMatches(reply))
          ?switch (m.group(1)!.toLowerCase()) {
            'เสียง' || 'volume' => DeviceWords.volume(m.group(2)!),
            'ไฟฉาย' || 'flashlight' || 'torch' => DeviceWords.torch(m.group(2)!),
            'เพลง' || 'media' => DeviceWords.media(m.group(2)!),
            _ => DeviceWords.ringer(m.group(2)!),
          },
      ];

  static List<AppEdit> _edits(String reply) => [
        for (final m in _appEdit.allMatches(reply))
          (
            action: switch (m.group(1)!.toLowerCase()) {
              'หมวดแอป' || 'หมวดแอพ' || 'app category' => 'set_category',
              'ลำดับแอป' || 'ลำดับแอพ' || 'app order' => 'set_order',
              _ => 'add_alias',
            },
            app: m.group(2)!.trim(),
            value: m.group(3)!.trim(),
          ),
      ];

  /// [app] = ชื่อแอป · [recording] = คนที่จะเปิดเสียงสาย ('' = ล่าสุด · null = ไม่มีแท็ก) ·
  /// [photo] = กล้องที่จะถ่าย ('หลัง'/'back' = กล้องหลัง · null = ไม่มีแท็ก)
  static ({
    String text,
    String? app,
    String? recording,
    String? photo,
    List<DeviceOrder> device,
    List<AppEdit> edits,
  }) parse(String reply) {
    final app = _app.firstMatch(reply)?.group(2)?.trim();
    final rec = _recording.firstMatch(reply);
    final photo = _photo.firstMatch(reply);
    final text = reply
        .replaceAll(_app, '')
        .replaceAll(_recording, '')
        .replaceAll(_photo, '')
        .replaceAll(_device, '')
        .replaceAll(_appEdit, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return (
      text: text,
      app: app == null || app.isEmpty ? null : app,
      recording: rec == null ? null : (rec.group(2) ?? '').trim(),
      photo: photo == null ? null : (photo.group(2) ?? '').trim(),
      device: _devices(reply),
      edits: _edits(reply),
    );
  }

  static bool backCamera(String which) => RegExp(r'หลัง|back|rear', caseSensitive: false).hasMatch(which);
}

abstract final class HandsTag {
  static final _tag = RegExp(
    r'\[\[\s*(ทำในเครื่อง|ใช้เครื่อง|ทำในมือถือ|phone|on phone|do on phone)\s*[:：]\s*([^\]\n]{1,600})\]\]',
    caseSensitive: false,
  );

  /// [text] = ข้อความที่เหลือ (ตัดแท็กออก) · [goal] = งานที่สั่ง (null = ไม่มีแท็ก)
  static ({String text, String? goal}) parse(String reply) {
    final m = _tag.firstMatch(reply);
    final goal = m?.group(2)?.trim();
    final text = reply.replaceAll(_tag, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return (text: text, goal: goal == null || goal.isEmpty ? null : goal);
  }
}
