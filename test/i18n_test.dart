import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';

/// กันข้อความไทยหลุดไปอยู่ฝั่งอังกฤษ
///
/// รูปแบบ `_('ไทย','English')` บังคับให้เขียนครบสองช่องตั้งแต่ตอนคอมไพล์
/// แต่ **ไม่ได้กันการก๊อปไทยใส่ทั้งสองช่อง** ซึ่งเป็นความผิดพลาดที่เกิดง่ายที่สุด
/// เวลาแปลรวดเดียวหลายร้อยสตริง เทสต์นี้จับตรงนั้น
void main() {
  const th = S(AppLang.th);
  const en = S(AppLang.en);

  /// อักษรไทยอยู่ในช่วง U+0E00–U+0E7F
  bool hasThai(String s) =>
      s.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F);

  group('ตารางแปล', () {
    test('ฝั่งอังกฤษต้องไม่มีอักษรไทยหลุดมา', () {
      final offenders = <String>[];

      void check(String name, String value) {
        if (hasThai(value)) offenders.add('$name -> $value');
      }

      // ทั่วไป
      check('cancel', en.cancel);
      check('save', en.save);
      check('reset', en.reset);
      check('resetToDefault', en.resetToDefault);
      check('tapToEdit', en.tapToEdit);
      check('typeHere', en.typeHere);
      check('lines', en.lines(3));

      // นำทาง
      check('tabMind', en.tabMind);
      check('tabMail', en.tabMail);
      check('tabCalendar', en.tabCalendar);
      check('tabTimeline', en.tabTimeline);
      check('tabSettings', en.tabSettings);

      // หน้าเปิดแอป
      check('splashSkip', en.splashSkip);
      check('splashLoading', en.splashLoading(42));
      check('chatTapToOpen', en.chatTapToOpen);
      check('chatCollapse', en.chatCollapse);

      // โหมด
      check('modeWork', en.modeWork);
      check('modeLove', en.modeLove);
      check('modeAuto', en.modeAuto);
      check('statusWork', en.statusWork);
      check('statusLove', en.statusLove);
      check('autoModeExplained', en.autoModeExplained);
      for (final c in en.workChips) {
        check('workChip', c);
      }
      for (final c in en.loveChips) {
        check('loveChip', c);
      }

      // บทสนทนาตัวอย่าง
      check('seedGreeting', en.seedGreeting);
      check('seedAsk', en.seedAsk);
      check('seedAnswer', en.seedAnswer);
      check('cannedWork', en.cannedWork);
      check('cannedLove', en.cannedLove);
      for (final lv in [0.1, 0.3, 0.6, 0.9]) {
        check('flirtSample($lv)', en.flirtSample(lv));
      }

      // ร้าน
      check('shopTitle', en.shopTitle);
      check('shopSubtitle', en.shopSubtitle);
      check('shopOpen', en.shopOpen);
      check('refresh', en.refresh);
      check('shopUnreachable', en.shopUnreachable);
      check('shopUnreachableWhy', en.shopUnreachableWhy);
      check('shopNoUrl', en.shopNoUrl);
      check('shopEmpty', en.shopEmpty);
      check('shopOwned', en.shopOwned);
      check('shopFree', en.shopFree);
      check('shopBuy', en.shopBuy);
      check('shopGet', en.shopGet);
      check('shopBuyOnWeb', en.shopBuyOnWeb);
      check('shopKind', en.shopKind('prop'));

      // ความจำ
      check('memTitle', en.memTitle);
      check('memCount', en.memCount(3));
      check('memEmpty', en.memEmpty);
      check('memWhy', en.memWhy);
      check('memPin', en.memPin);
      check('memPinned', en.memPinned);
      check('memPinWhy', en.memPinWhy);
      check('memForget', en.memForget);
      check('memForgetAll', en.memForgetAll);
      check('memForgetAllConfirm', en.memForgetAllConfirm);
      check('memEdit', en.memEdit);
      check('memKind', en.memKind('routine'));
      check('speakerMe', en.speakerMe);
      check('speakerHer', en.speakerHer);

      // สิทธิ์
      check('permTitle', en.permTitle);
      check('permAllSet', en.permAllSet);
      check('permMissing', en.permMissing(2));
      check('permGrant', en.permGrant);
      check('permGrantAll', en.permGrantAll);
      check('permOk', en.permOk);
      check('permNo', en.permNo);
      check('permBlocked', en.permBlocked);
      check('permGoesToSettings', en.permGoesToSettings);
      check('permCamera', en.permCamera);
      check('permCameraWhy', en.permCameraWhy);
      check('permMic', en.permMic);
      check('permMicWhy', en.permMicWhy);
      check('permNotify', en.permNotify);
      check('permNotifyWhy', en.permNotifyWhy);
      check('permBattery', en.permBattery);
      check('permInstall', en.permInstall);
      check('permInstallWhy', en.permInstallWhy);

      // เฝ้างานเบื้องหลัง
      check('bgTitle', en.bgTitle);
      check('bgWhy', en.bgWhy);
      check('bgWatching', en.bgWatching);
      check('bgUpdateFound', en.bgUpdateFound('0.2.0'));
      check('bgNeverRan', en.bgNeverRan);
      check('bgLastBeat', en.bgLastBeat('x'));
      check('bgBeats', en.bgBeats(3));
      check('bgBatteryTitle', en.bgBatteryTitle);
      check('bgBatteryWhy', en.bgBatteryWhy);
      check('bgBatteryOn', en.bgBatteryOn);
      check('bgBatteryOff', en.bgBatteryOff);
      check('bgBatteryAsk', en.bgBatteryAsk);
      check('agoMinutes', en.agoMinutes(5));
      check('agoHours', en.agoHours(2));
      check('agoJustNow', en.agoJustNow);

      // ชุดตัวมายด์
      check('packTitle', en.packTitle);
      check('packWhy', en.packWhy);
      check('packMissing', en.packMissing);
      check('packReady', en.packReady);
      check('packMissingHint', en.packMissingHint);
      check('packInstalled', en.packInstalled);
      check('packAdd', en.packAdd);
      check('packWearing', en.packWearing);
      check('packKindCharacter', en.packKindCharacter);
      check('packKindOutfit', en.packKindOutfit);
      check('packRemoveConfirm', en.packRemoveConfirm('X'));
      check('packDownload', en.packDownload);
      check('packRemove', en.packRemove);
      check('packUrlLabel', en.packUrlLabel);
      check('packDownloading', en.packDownloading);
      check('packVerifying', en.packVerifying);
      check('packUnpacking', en.packUnpacking);
      check('packErrNoUrl', en.packErrNoUrl);
      check('packErrNetwork', en.packErrNetwork);
      check('packErrHash', en.packErrHash);
      check('packErrBadPack', en.packErrBadPack);
      check('packErrServer', en.packErrServer);

      // กล้องเชิดหุ่น
      check('puppetMode', en.puppetMode);
      check('puppetStart', en.puppetStart);
      check('puppetStop', en.puppetStop);
      check('puppetCalibrating', en.puppetCalibrating);
      check('puppetRecalibrate', en.puppetRecalibrate);
      check('puppetNoFace', en.puppetNoFace);
      check('puppetStarting', en.puppetStarting);
      check('puppetDenied', en.puppetDenied);
      check('puppetBlocked', en.puppetBlocked);
      check('puppetFailed', en.puppetFailed);
      check('openSettings', en.openSettings);
      check('puppetPrivacy', en.puppetPrivacy);

      // ฟองคำพูด
      check('bubbleTitle', en.bubbleTitle);
      check('bubbleEnabled', en.bubbleEnabled);
      check('bubbleHint', en.bubbleHint);
      check('bubbleStay', en.bubbleStay);
      check('bubbleStayNote', en.bubbleStayNote);
      check('bubbleFadeNote', en.bubbleFadeNote(5));
      check('bubbleOffNote', en.bubbleOffNote);

      // ตั้งค่า
      check('settingsTitle', en.settingsTitle);
      check('language', en.language);
      check('sectionBrain', en.sectionBrain);
      check('sectionVoice', en.sectionVoice);
      check('sectionCall', en.sectionCall);
      check('sectionUpdate', en.sectionUpdate);
      check('noKeyBanner', en.noKeyBanner);
      check('ownerProfileTitle', en.ownerProfileTitle);
      check('ownerProfileHint', en.ownerProfileHint);
      check('ownerProfileEditorHint', en.ownerProfileEditorHint);
      check('boundariesTitle', en.boundariesTitle);
      check('boundariesHint', en.boundariesHint);
      check('boundariesEditorHint', en.boundariesEditorHint);

      // เสียง
      check('voiceEnabled', en.voiceEnabled);
      check('voiceEngine', en.voiceEngine);
      check('voiceModel', en.voiceModel);
      check('channelChat', en.channelChat);
      check('channelAnswer', en.channelAnswer);
      check('channelOutgoing', en.channelOutgoing);
      check('ttsOpenAiHint', en.ttsOpenAiHint);
      check('ttsDeviceHint', en.ttsDeviceHint);
      check('ttsCloneHint', en.ttsCloneHint);

      // รับสาย
      check('autoAnswer', en.autoAnswer);
      check('autoAnswerHint', en.autoAnswerHint);
      check('ringImmediate', en.ringImmediate);
      check('ringDelayNote', en.ringDelayNote(15));

      // อัปเดต
      check('updateChecking', en.updateChecking);
      check('updateReady', en.updateReady);
      check('updateSource', en.updateSource);
      check('updateProgress', en.updateProgress('1.0 / 2.0 MB', 50));
      check('updateNoConnection', en.updateNoConnection);
      check('updateInstall', en.updateInstall('12 MB'));

      // ฝั่ง AI
      check('brainProxy', en.brainProxy);
      check('brainProxySummary', en.brainProxySummary);
      check('brainProxyTradeoff', en.brainProxyTradeoff);
      check('licenseTitle', en.licenseTitle);
      check('licenseNotSet', en.licenseNotSet);
      check('licenseHint', en.licenseHint);
      check('licenseNeeded', en.licenseNeeded);
      check('proxyModelNote', en.proxyModelNote);
      check('ownKeyTitle', en.ownKeyTitle);
      check('ownKeyHint', en.ownKeyHint);
      check('ownKeyNotSet', en.ownKeyNotSet);
      check('ownKeySaved', en.ownKeySaved);
      check('ownKeyRemoved', en.ownKeyRemoved);
      check('ownKeyLooksWrong', en.ownKeyLooksWrong);
      check('ownKeyNeeded', en.ownKeyNeeded);
      check('gemmaInstalledTag', en.gemmaInstalledTag);
      check('gemmaDeviceTooSmall', en.gemmaDeviceTooSmall('4.0', '4.5'));
      check('brainOpenAiSummary', en.brainOpenAiSummary);
      check('brainOpenAiTradeoff', en.brainOpenAiTradeoff);
      check('brainHome', en.brainHome);
      check('brainHomeTradeoff', en.brainHomeTradeoff);
      check('brainOnDevice', en.brainOnDevice);
      check('brainOnDeviceTradeoff', en.brainOnDeviceTradeoff);
      check('homeServerHint', en.homeServerHint);
      check('ramBlockedTitle', en.ramBlockedTitle);
      check('ramBlockedDetail', en.ramBlockedDetail('3.6', '4.5'));
      check('ramBlockedHint', en.ramBlockedHint);
      check('ramBlockedAnyway', en.ramBlockedAnyway);
      check('ramTooSmall', en.ramTooSmall);
      check('ramTooSmallDetail', en.ramTooSmallDetail('3.6'));
      check('ramTightDetail', en.ramTightDetail('5.4'));
      check('ramComfortableDetail', en.ramComfortableDetail('7.4'));
      check('ramRoomyDetail', en.ramRoomyDetail('11.2'));
      check('errOffline', en.errOffline);
      check('errBadKey', en.errBadKey);
      check('updateInstallerBlocked', en.updateInstallerBlocked);

      // ข้อมูลตัวอย่างในหน้าจอ
      check('mailTitle', en.mailTitle);
      check('mailSubtitle', en.mailSubtitle);
      check('mail1Title', en.mail1Title);
      check('mailDraftBody', en.mailDraftBody);
      check('mailReadAloud', en.mailReadAloud);
      check('mailCompose', en.mailCompose);
      check('demoAction', en.demoAction);
      check('calRestClear', en.calRestClear);
      check('calRestHours', en.calRestHours(4));
      check('calNoneToday', en.calNoneToday);
      check('calCount', en.calCount(3));
      check('calNeedPermission', en.calNeedPermission);
      check('calNeedPermissionWhy', en.calNeedPermissionWhy);
      check('calGrant', en.calGrant);
      check('calAllDay', en.calAllDay);
      check('calNow', en.calNow);
      check('calToday', en.calToday);
      check('calTomorrow', en.calTomorrow);
      check('calLoading', en.calLoading);
      check('calFailed', en.calFailed);
      check('permCalendarWhy', en.permCalendarWhy);
      // ชื่อวันกับชื่อเดือนฝั่งอังกฤษต้องไม่ใช่ไทย ไม่งั้นวันที่จะโผล่เป็นไทย
      // กลางหน้าจอภาษาอังกฤษ ซึ่งเป็นจุดที่คนสังเกตเห็นทันที
      for (final w in en.weekdayNames) {
        check('weekdayNames', w);
      }
      for (final m in en.monthShort) {
        check('monthShort', m);
      }
      check('tlTitle', en.tlTitle);
      check('tlDidToday', en.tlDidToday(3));
      check('tlNothingToday', en.tlNothingToday);
      check('tlEmpty', en.tlEmpty);
      check('tlEmptyWhy', en.tlEmptyWhy);
      check('tlStatTalk', en.tlStatTalk);
      check('tlStatLearn', en.tlStatLearn);
      check('tlStatMeet', en.tlStatMeet);
      check('tlStatCall', en.tlStatCall);
      check('tlKindCall', en.tlKindCall);
      check('permPhone', en.permPhone);
      check('permPhoneWhy', en.permPhoneWhy);
      check('permContacts', en.permContacts);
      check('permContactsWhy', en.permContactsWhy);
      check('permAnswer', en.permAnswer);
      check('permDialer', en.permDialer);
      check('permDialerWhy', en.permDialerWhy);
      check('permAnswerWhy', en.permAnswerWhy);
      check('tlKindAsked', en.tlKindAsked);
      check('tlKindReplied', en.tlKindReplied);
      check('tlKindLearned', en.tlKindLearned);
      check('tlKindPack', en.tlKindPack);
      check('tlClear', en.tlClear);
      check('tlClearAsk', en.tlClearAsk);
      check('calYesterday', en.calYesterday);

      expect(offenders, isEmpty,
          reason: 'ข้อความพวกนี้ยังเป็นไทยอยู่ในฝั่งอังกฤษ:\n'
              '${offenders.join('\n')}');
    });

    test('ฝั่งไทยต้องเป็นไทยจริง ไม่ใช่อังกฤษที่ลืมแปล', () {
      // ไม่ใช่ทุกสตริงที่ต้องมีอักษรไทย (เช่นชื่อรุ่น "Sol") แต่ข้อความยาว ๆ ต้องมี
      final longThai = <String, String>{
        'autoModeExplained': th.autoModeExplained,
        'seedGreeting': th.seedGreeting,
        'boundariesEditorHint': th.boundariesEditorHint,
        'ramTooSmallDetail': th.ramTooSmallDetail('3.6'),
        'brainOnDeviceTradeoff': th.brainOnDeviceTradeoff,
        'updateSource': th.updateSource,
        'mailDraftBody': th.mailDraftBody,
        'puppetCalibrating': th.puppetCalibrating,
        'puppetPrivacy': th.puppetPrivacy,
        'packWhy': th.packWhy,
        'bgWhy': th.bgWhy,
        'permBlocked': th.permBlocked,
        'memWhy': th.memWhy,
        'shopUnreachableWhy': th.shopUnreachableWhy,
        'permInstallWhy': th.permInstallWhy,
        'bgBatteryWhy': th.bgBatteryWhy,
        'calRestClear': th.calRestClear,
      };
      for (final e in longThai.entries) {
        expect(hasThai(e.value), isTrue,
            reason: '${e.key} ฝั่งไทยไม่มีอักษรไทยเลย น่าจะลืมแปล');
      }
    });

    test('สองภาษาต้องต่างกันจริง ไม่ใช่ค่าเดียวกันสองช่อง', () {
      final pairs = <String, (String, String)>{
        'tabMail': (th.tabMail, en.tabMail),
        'modeWork': (th.modeWork, en.modeWork),
        'settingsTitle': (th.settingsTitle, en.settingsTitle),
        'voiceEnabled': (th.voiceEnabled, en.voiceEnabled),
        'autoAnswer': (th.autoAnswer, en.autoAnswer),
        'errOffline': (th.errOffline, en.errOffline),
        'splashSkip': (th.splashSkip, en.splashSkip),
        'puppetMode': (th.puppetMode, en.puppetMode),
        'puppetCalibrating': (th.puppetCalibrating, en.puppetCalibrating),
      };
      for (final e in pairs.entries) {
        expect(e.value.$1, isNot(e.value.$2),
            reason: '${e.key} ไทยกับอังกฤษเหมือนกันเป๊ะ น่าจะก๊อปมาช่องเดียว');
      }
    });
  });

  group('ไม่มีข้อความไทยตกค้างในโค้ด UI', () {
    test('lib/ นอก i18n ต้องไม่เหลือสตริงไทยที่ผู้ใช้เห็น', () {
      final thai = RegExp(r'[\u0E00-\u0E7F]');
      final quoted = RegExp(r"'([^'\n]*)'");

      // ยกเว้นตามเหตุผล ไม่ใช่ยกเว้นเพื่อให้เทสต์ผ่าน
      const allowed = {
        // ครึ่งไทยของคู่แปล — ต้องมีไทยอยู่แล้ว
        'lib/ai/mind_persona.dart',
        // ข้อความ assert สำหรับนักพัฒนา ผู้ใช้ไม่มีวันเห็น
        'lib/widgets/mind_nav_bar.dart',
        // regex ตรวจจับความลับ ไม่ใช่ข้อความที่ผู้ใช้เห็น — คำไทยในนั้นคือ
        // สิ่งที่ต้อง **จับให้ได้** ("รหัสผ่าน") ย้ายเข้า i18n แล้วจะจับไม่ได้
        'lib/memory/mind_memory.dart',
        // เหตุผลเดียวกับ mind_memory — คำไทยในนั้นคือ **รายการคำที่ต้องจับ**
        // กับช่วงอักขระไทยของ regex ไม่ใช่ข้อความที่ผู้ใช้เห็น
        // ย้ายเข้า i18n แล้วด่านตรวจชื่อจะจับไม่ได้เลย
        // (ข้อความที่ผู้ใช้เห็นจริงอยู่ใน strings.dart หมดแล้ว — nameRude ฯลฯ)
        'lib/persona/mind_name.dart',
        // ตาราง 12 ราศี — ไทยกับอังกฤษอยู่คู่กันเป็นฟิลด์ `xxxTh`/`xxxEn`
        // ของคลาสเดียวกัน ซึ่งคอมไพเลอร์บังคับให้มีครบทั้งคู่อยู่แล้ว
        // แข็งกว่าที่ regex ตัวนี้ตรวจได้ · และมีเทสต์เฉพาะคุมอีกชั้นว่า
        // ทั้งสองภาษาไม่ว่างและไม่ใช่ข้อความเดียวกัน (ดู test/soul_test.dart)
        'lib/persona/zodiac.dart',
      };

      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll(r'\', '/');
        if (rel.contains('/i18n/')) continue;
        if (allowed.any(rel.endsWith)) continue;

        var n = 0;
        // debugPrint ที่ยาวเกินบรรทัดจะถูกตัดเป็นหลายบรรทัด
        // ถ้าดูทีละบรรทัดจะเห็นบรรทัดต่อเป็นสตริงลอย ๆ แล้วรายงานผิด
        // จึงต้องจำว่ายังอยู่ในวงเล็บของ debugPrint หรือยัง
        var inDebugPrint = false;
        for (final line in f.readAsLinesSync()) {
          n++;
          final t = line.trim();

          if (inDebugPrint) {
            if (line.contains(');')) inDebugPrint = false;
            continue;
          }
          if (t.startsWith('//') || t.startsWith('*')) continue;
          if (line.contains('debugPrint')) {
            if (!line.contains(');')) inDebugPrint = true;
            continue;
          }

          for (final m in quoted.allMatches(line)) {
            if (thai.hasMatch(m.group(1)!)) {
              offenders.add('$rel:$n  ${m.group(1)}');
            }
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'ยังมีข้อความไทยฝังในโค้ด ต้องย้ายเข้า lib/i18n:\n'
              '${offenders.take(20).join('\n')}');
    });
  });
}
