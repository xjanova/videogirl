import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../avatar/avatar_pack.dart';
import '../i18n/strings.dart';
import '../i18n/strings_knowledge.dart';
import '../state/mind_state.dart';
import '../store/knowledge_pack.dart';
import '../store/pack_catalogue.dart';
import '../theme/tokens.dart';
import '../update/updater.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';
import '../widgets/segment_switch.dart';
import 'knowledge_reader_screen.dart';

/// ร้านของมายด์ — ซื้อชุด ตัวละครใหม่ ของประดับเวที และแพ็กความรู้
///
/// เป็นหน้าที่ push ทับ ไม่ใช่แท็บ เพราะแถบล่างมีห้าช่องและปุ่มกลางต้องอยู่
/// ช่องกลางพอดี (มี assert กันไว้) เพิ่มเป็นหกจะพังโครงนั้นทั้งหมด
/// และร้านไม่ใช่ของที่คนเปิดวันละหลายรอบเหมือนสี่แท็บที่มีอยู่
///
/// **จ่ายเงินบนเว็บ ไม่ใช่ในแอป** — ทำได้เพราะแอปนี้แจกผ่าน GitHub Releases
/// ไม่ได้อยู่บน Play (กฎ Play billing บังคับเฉพาะแอปบน Play)
/// ดู `docs/pack-store.md`
///
/// สองแท็บ: ชุดและตัวละคร (AvatarPacks) · ความรู้ (KnowledgePacks) · คนละตัวติดตั้ง
/// เพราะแพ็กความรู้เป็นข้อความล้วน ไม่มีโมเดล 3D ให้เวทีโหลด
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, this.initialTab = 0, this.onAsk});

  /// 0 = ชุดและตัวละคร · 1 = ความรู้
  final int initialTab;

  /// แตะตัวอย่างคำถามของแพ็ก → ปิดร้านแล้วถามในแชท · null (เปิดจากหน้าตั้งค่า) = แสดงเป็นข้อความเฉย ๆ
  final ValueChanged<String>? onAsk;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final PackCatalogue _shop = PackCatalogue();
  late int _tab = widget.initialTab.clamp(0, 1);

  /// ชิ้นที่กำลังติดตั้งอยู่ — null = ไม่ได้ติดตั้งอะไรอยู่
  ///
  /// `AvatarPacks` บอกได้แค่ว่า "กำลังโหลดอยู่" ไม่ได้บอกว่าโหลดของชิ้นไหน
  /// หน้านี้มีหลายการ์ด จึงต้องจำเองว่ากดของชิ้นไหนไป ไม่งั้นแถบความคืบหน้า
  /// จะขึ้นพร้อมกันทุกใบ
  String? _installingId;

  /// แพ็กความรู้ที่กำลังติดตั้ง (เหตุผลเดียวกับ [_installingId] · คนละตัวติดตั้งจึงคนละช่อง)
  String? _kpBusyId;

  /// แพ็กฟรีที่มากับแอป · อ่าน manifest จาก asset ครั้งเดียว เอาชื่อมาแสดงก่อนติดตั้ง
  late final Future<List<KnowledgeManifest>> _bundled = _readBundled();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _shop.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final state = context.read<MindState>();
    await _shop.load(state.storeBaseUrl, licenseKey: state.licenseKey);
  }

  static Future<List<KnowledgeManifest>> _readBundled() async {
    final out = <KnowledgeManifest>[];
    for (final id in KnowledgePacks.bundled) {
      try {
        out.add(KnowledgeManifest.parse(
            jsonDecode(await rootBundle.loadString('${KnowledgePacks.bundledRoot}/$id/manifest.json'))));
      } on Object catch (e) {
        // asset หายจาก build = ไม่มีการ์ดแพ็กฟรี ดีกว่าหน้าร้านพัง
        debugPrint('shop: อ่านแพ็กฟรี $id ไม่ได้ — ${e.runtimeType}');
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final kp = context.read<MindState>().knowledgePacks;

    // 🔴 `watch` ไม่ใช่ `read` — ตัวรู้ความคืบหน้าการโหลดคือ AvatarPacks
    // ไม่ใช่ `_shop` · เดิมหน้านี้ฟังแค่ `_shop` ซึ่งไม่ขยับเลยระหว่างโหลด
    // ผลคือกดโหลดแล้วจอนิ่งสนิททั้งที่ไฟล์กำลังวิ่งอยู่จริง
    context.watch<AvatarPacks>();

    return Scaffold(
      body: LiquidBackground(
        gradient: MindGradients.settings,
        orbs: Orb.settings,
        child: SafeArea(
          child: ListenableBuilder(
            // แพ็กความรู้รายงานความคืบหน้าเอง · ฟังด้วย ไม่งั้นกดติดตั้งแล้วจอนิ่ง (บั๊กเดิมของชุด)
            listenable: Listenable.merge([_shop, kp]),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MindScreenHeader(
                  overline: 'GigGok',
                  title: t.shopTitle,
                  subtitle: t.shopSubtitle,
                  trailing: MindIconButton(
                    icon: Icons.close_rounded,
                    tooltip: t.cancel,
                    mode: mode,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(MindSpace.lg, 0, MindSpace.lg, MindSpace.md),
                  child: MindSegmentSwitch(
                    labels: [t.shopTabLooks, t.shopTabKnowledge],
                    selected: _tab,
                    mode: mode,
                    onSelect: (i) => setState(() => _tab = i),
                  ),
                ),
                Expanded(child: _tab == 0 ? _looks(context, mode, t) : _knowledge(context, mode, t, kp)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══ ชุดและตัวละคร ═══════════════════════════════════════

  Widget _looks(BuildContext context, MindMode mode, S t) {
    if (_shop.stage == ShopStage.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_shop.stage == ShopStage.failed) {
      // แยก "ยังไม่ได้ตั้งที่อยู่ร้าน" ออกจาก "ต่อไม่ติด" — คนละเรื่อง
      // และคนละวิธีแก้ · รวมเป็นข้อความเดียวคือบอกให้ผู้ใช้ไปเดาเอง
      final noUrl = _shop.error == ShopError.noUrl;
      return _message(
        mode,
        icon: noUrl ? Icons.link_off_rounded : Icons.storefront_outlined,
        title: noUrl ? t.shopNoUrl : t.shopUnreachable,
        body: t.shopUnreachableWhy,
        action: (t.refresh, _reload),
      );
    }

    final items = [for (final i in _shop.items) if (i.kind != AvatarPackKind.knowledge) i];
    if (items.isEmpty) {
      return _message(
        mode,
        icon: Icons.inventory_2_outlined,
        title: t.shopEmpty,
        body: t.shopSubtitle,
        action: (t.refresh, _reload),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            MindSpace.lg, 0, MindSpace.lg, MindSpace.xxl),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: MindSpace.md),
        itemBuilder: (_, i) => _card(mode, t, items[i], _avatarAction(context, mode, t, items[i])),
      ),
    );
  }

  Widget _message(
    MindMode mode, {
    required IconData icon,
    required String title,
    required String body,
    required (String, Future<void> Function()) action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MindSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: MindColors.ink22),
            const SizedBox(height: MindSpace.md),
            Text(title, style: MindType.title, textAlign: TextAlign.center),
            const SizedBox(height: MindSpace.sm),
            Text(body, style: MindType.caption, textAlign: TextAlign.center),
            const SizedBox(height: MindSpace.lg),
            MindButton(
              label: action.$1,
              icon: Icons.refresh_rounded,
              mode: mode,
              onTap: action.$2,
            ),
          ],
        ),
      ),
    );
  }

  /// การ์ดสินค้า · ปุ่มล่างต่างกันตามชนิด (ชุด = AvatarPacks · ความรู้ = KnowledgePacks)
  Widget _card(MindMode mode, S t, ShopItem item, Widget action) {
    final price = item.price <= 0
        ? t.shopFree
        : t.shopPrice(item.price.toStringAsFixed(0), item.currency);
    final summary = item.summaryFor(t.isThai);

    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(MindSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.preview != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(MindRadius.control),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.network(
                  item.preview!,
                  fit: BoxFit.cover,
                  // รูปโหลดไม่ขึ้นไม่ควรทำให้ทั้งรายการหาย — ของยังซื้อได้อยู่
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: MindColors.glass80,
                    child: Icon(Icons.image_not_supported_outlined,
                        color: MindColors.ink22),
                  ),
                ),
              ),
            ),
          if (item.preview != null) const SizedBox(height: MindSpace.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.shopKind(item.kind.name),
                        style: MindType.overline
                            .copyWith(fontSize: 9.5, color: mode.accent)),
                    const SizedBox(height: 3),
                    Text(item.nameFor(t.isThai), style: MindType.title),
                    const SizedBox(height: 2),
                    Text(
                      item.sizeBytes > 0 ? item.sizeLabel : '',
                      style: MindType.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                item.owned ? t.shopOwned : price,
                style: MindType.title.copyWith(
                  color: item.owned ? mode.accent : MindColors.ink,
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: MindSpace.sm),
            Text(summary, style: MindType.caption),
          ],
          const SizedBox(height: MindSpace.md),
          action,
        ],
      ),
    );
  }

  Widget _avatarAction(BuildContext context, MindMode mode, S t, ShopItem item) {
    final packs = context.read<AvatarPacks>();
    final anyBusy = _installingId != null;

    // ป้ายบอกขั้นตอน ขึ้นเฉพาะการ์ดใบที่กดไป · ระหว่างรอลิงก์ที่มีลายเซ็น
    // ตัวติดตั้งยังไม่เริ่ม stage จึงยังเป็นค่าเดิม — ต้องมีป้ายให้ตรงนั้นด้วย
    // ไม่งั้นช่วงต้นจะยังนิ่งอยู่ดี
    final busyLabel = _installingId != item.id
        ? null
        : switch (packs.stage) {
            AvatarPackStage.downloading =>
              '${t.packDownloading} · ${packs.sizeLabel}',
            AvatarPackStage.verifying => t.packVerifying,
            AvatarPackStage.unpacking => t.packUnpacking,
            _ => t.packDownloading,
          };

    // ชิ้นที่กำลังติดตั้งอยู่ ให้แถบความคืบหน้าแทนปุ่ม — ปุ่มที่กดแล้ว
    // ไม่ขยับคืออาการเดียวกับปุ่มเสียในสายตาผู้ใช้
    if (busyLabel != null) {
      // ตอนแตกไฟล์ไม่รู้ความคืบหน้า ให้แถบวิ่งไปเรื่อย ๆ ดีกว่า
      // แถบ 0% ที่ค้างนิ่ง ซึ่งอ่านได้ว่าค้างจริง
      return _progress(busyLabel, packs.stage == AvatarPackStage.downloading ? packs.progress : null);
    }
    // ของแจกฟรีต้องโหลดได้เลย ไม่ใช่เด้งไปหน้าจ่ายเงินบนเว็บ
    // (`owned` มาจาก /api/packs/mine ซึ่งต้องมีไลเซนส์ เครื่องที่เพิ่งลง
    // ยังไม่มี ของฟรีจึงขึ้นเป็น owned=false เสมอ ถ้าดูแค่ owned
    // ผู้ใช้จะโดนพาไปจ่ายเงินค่าของที่ราคา 0)
    if (item.owned || item.price <= 0) {
      return MindButton(
        label: t.shopGet,
        kind: MindButtonKind.primary,
        icon: Icons.download_rounded,
        mode: mode,
        expand: true,
        // กำลังโหลดชิ้นอื่นอยู่ = กดชิ้นนี้ไม่ได้ · ตัวติดตั้งรับได้ทีละ
        // ชุด (install() คืน false ทันทีถ้าไม่ว่าง) ซึ่งถ้าปล่อยให้กดได้
        // จะเงียบเหมือนปุ่มเสียอีกแบบหนึ่ง
        onTap: anyBusy ? null : () => _install(context, item),
      );
    }
    // ปิดไว้ระหว่างติดตั้งด้วย — เด้งออกเบราว์เซอร์กลางคันแล้วกลับมา
    // เจอชุดติดตั้งค้างครึ่งทางเป็นทางที่ไม่ควรเปิดให้เดินตั้งแต่แรก
    return _buyButton(context, mode, t, item, enabled: !anyBusy);
  }

  Widget _progress(String label, double? value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, textAlign: TextAlign.center, style: MindType.caption),
          const SizedBox(height: MindSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: value),
          ),
        ],
      );

  Widget _buyButton(BuildContext context, MindMode mode, S t, ShopItem item, {required bool enabled}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MindButton(
            label: t.shopBuy,
            kind: MindButtonKind.primary,
            icon: Icons.open_in_new_rounded,
            mode: mode,
            expand: true,
            onTap: enabled ? () => _buy(context, item) : null,
          ),
          const SizedBox(height: MindSpace.xs),
          Text(t.shopBuyOnWeb,
              textAlign: TextAlign.center,
              style: MindType.caption.copyWith(fontSize: 10.5)),
        ],
      );

  /// พาไปหน้าซื้อบนเว็บ — จ่ายเสร็จแล้วกลับมากดรีเฟรช
  Future<void> _buy(BuildContext context, ShopItem item) async {
    final base = context.read<MindState>().storeBaseUrl.trim();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = S.of(context);
    var opened = false;
    if (base.isNotEmpty) {
      final url = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}'
          '/shop/${Uri.encodeComponent(item.id)}');
      try {
        opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('shop: เปิดหน้าซื้อไม่ได้ — $e');
      }
    }
    // 🔴 เปิดไม่ได้ต้องบอก · `launchUrl` คืน false เงียบ ๆ ได้ (ไม่มีเบราว์เซอร์
    // ที่รับลิงก์) แล้วผู้ใช้เห็นแค่ว่ากดซื้อแล้วไม่มีอะไรเกิดขึ้น
    if (!opened) {
      messenger?.showSnackBar(SnackBar(content: Text(t.shopBuyFailed)));
    }
  }

  /// ขอลิงก์ที่มีลายเซ็นแล้วส่งต่อให้ตัวติดตั้งชุดที่มีอยู่
  ///
  /// ตัวติดตั้งเดิมรับ url + sha256 อยู่แล้ว จึงไม่ต้องแก้อะไรฝั่งนั้นเลย
  ///
  /// 🔴 **ต้องมีสัญญาณตอบกลับทุกทางที่ออกจากเมธอดนี้** ของก้อนหนึ่งหนัก 18 MB
  /// ใช้เวลาเป็นนาทีบน 4G · เดิมกดแล้วไม่มีอะไรขยับเลยสักอย่าง เพราะหน้านี้
  /// ฟังแค่ `_shop` ไม่ได้ฟัง `AvatarPacks` ที่เป็นตัวรู้ความคืบหน้าจริง
  /// ผู้ใช้จึงอ่านได้ทางเดียวว่าปุ่มเสีย แล้วกดซ้ำ ๆ
  Future<void> _install(BuildContext context, ShopItem item) async {
    // อ่าน context ให้ครบก่อน await ตัวแรก — หลัง await หน้าอาจถูกปิดไปแล้ว
    final state = context.read<MindState>();
    final packs = context.read<AvatarPacks>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = S.of(context);

    setState(() => _installingId = item.id);
    try {
      final link = await _shop.downloadLink(
        state.storeBaseUrl,
        state.licenseKey,
        item.id,
      );
      if (link == null) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t.shopUnreachable)));
        return;
      }

      final ok = await packs.install(link.url, expectedSha256: link.sha256);

      // บอกผลเสมอ ทั้งสำเร็จและล้มเหลว · ล้มเหลวต้องบอกด้วยว่าเพราะอะไร
      // ไม่ใช่เงียบไปเฉย ๆ ให้เดาเอง
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(ok
              ? '${item.nameFor(t.isThai)} · ${t.packReady}'
              : _errorLabel(t, packs.error)),
        ));
    } finally {
      // หน้าอาจถูกปิดไปแล้วระหว่างโหลด — setState ตอนนั้นคือ crash
      if (mounted) setState(() => _installingId = null);
    }
  }

  String _errorLabel(S t, AvatarPackError? e) => switch (e) {
        AvatarPackError.noUrl => t.packErrNoUrl,
        AvatarPackError.network => t.packErrNetwork,
        AvatarPackError.hashMismatch => t.packErrHash,
        AvatarPackError.badPack => t.packErrBadPack,
        AvatarPackError.noServer => t.packErrServer,
        null => t.shopUnreachable,
      };

  // ═══ ความรู้ ═════════════════════════════════════════════
  //
  // 🔴 แพ็กที่ติดตั้งแล้วต้องเห็นและเปิดปิดได้แม้ร้านต่อไม่ติด · เดิมทั้งหน้าขึ้นกับสถานะร้าน
  // ถ้าทำตามนั้นที่นี่ เน็ตหลุด = ปิดแพ็กที่ตอบผิดเรื่องไม่ได้ และลบไม่ได้

  Widget _knowledge(BuildContext context, MindMode mode, S t, KnowledgePacks kp) {
    final store = [for (final i in _shop.items) if (i.kind == AvatarPackKind.knowledge) i];
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(MindSpace.lg, 0, MindSpace.lg, MindSpace.xxl),
        children: [
          Text(t.kpHowItWorks, style: MindType.caption),
          const SizedBox(height: MindSpace.md),
          _heading(t.kpInstalledTitle),
          if (kp.installed.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: MindSpace.md),
              child: Text(t.kpNoneInstalled, style: MindType.caption),
            ),
          for (final p in kp.installed) ...[
            _installedCard(context, mode, t, kp, p),
            const SizedBox(height: MindSpace.md),
          ],
          FutureBuilder<List<KnowledgeManifest>>(
            future: _bundled,
            builder: (context, snap) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in snap.data ?? const <KnowledgeManifest>[])
                  if (kp.byId(m.id) == null) ...[
                    _bundledCard(context, mode, t, kp, m),
                    const SizedBox(height: MindSpace.md),
                  ],
              ],
            ),
          ),
          const SizedBox(height: MindSpace.sm),
          _heading(t.kpStoreTitle),
          ..._storeList(context, mode, t, kp, store),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: MindSpace.sm),
        child: Text(text, style: MindType.overline.copyWith(fontSize: 10.5)),
      );

  List<Widget> _storeList(BuildContext context, MindMode mode, S t, KnowledgePacks kp, List<ShopItem> store) {
    if (_shop.stage == ShopStage.loading || _shop.stage == ShopStage.idle) {
      return const [Center(child: Padding(padding: EdgeInsets.all(MindSpace.lg), child: CircularProgressIndicator()))];
    }
    if (_shop.stage == ShopStage.failed) {
      final noUrl = _shop.error == ShopError.noUrl;
      return [
        Text(noUrl ? t.shopNoUrl : t.shopUnreachable, style: MindType.title),
        const SizedBox(height: MindSpace.xs),
        Text(t.shopUnreachableWhy, style: MindType.caption),
        const SizedBox(height: MindSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: MindButton(label: t.refresh, icon: Icons.refresh_rounded, mode: mode, onTap: _reload),
        ),
      ];
    }
    if (store.isEmpty) return [Text(t.kpStoreEmpty, style: MindType.caption)];
    return [
      for (final item in store) ...[
        _card(mode, t, item, _knowledgeAction(context, mode, t, kp, item)),
        const SizedBox(height: MindSpace.md),
      ],
    ];
  }

  Widget _knowledgeAction(BuildContext context, MindMode mode, S t, KnowledgePacks kp, ShopItem item) {
    if (_kpBusyId == item.id) return _kpProgress(t, kp);
    final busy = _kpBusyId != null || kp.busy;
    final have = kp.byId(item.id);
    // ติดตั้งแล้ว และร้านไม่มีรุ่นที่ใหม่กว่า = ไม่มีอะไรให้กด (สวิตช์อยู่ในการ์ดข้างบน) ·
    // เทียบว่า "ใหม่กว่า" ไม่ใช่ "ต่างกัน" · แพ็กฟรีในแอปอาจใหม่กว่าในร้าน กดแล้วได้รุ่นเก่ามาทับ
    final storeVersion = item.version;
    if (have != null && (storeVersion == null || !Updater.isNewer(storeVersion, have.manifest.version))) {
      return MindButton(label: t.kpInstalled, icon: Icons.check_rounded, mode: mode, expand: true, onTap: null);
    }
    if (item.owned || item.price <= 0) {
      return MindButton(
        label: have != null ? t.kpUpdate : t.shopGet,
        kind: MindButtonKind.primary,
        icon: have != null ? Icons.system_update_alt_rounded : Icons.download_rounded,
        mode: mode,
        expand: true,
        onTap: busy ? null : () => _installKnowledge(context, item),
      );
    }
    return _buyButton(context, mode, t, item, enabled: !busy);
  }

  Widget _kpProgress(S t, KnowledgePacks kp) => _progress(
        switch (kp.stage) {
          KnowledgeInstallStage.verifying => t.packVerifying,
          KnowledgeInstallStage.unpacking => t.packUnpacking,
          _ => t.packDownloading,
        },
        kp.stage == KnowledgeInstallStage.downloading ? kp.progress : null,
      );

  Widget _installedCard(BuildContext context, MindMode mode, S t, KnowledgePacks kp, KnowledgePack p) {
    final m = p.manifest;
    final starters = p.enabled ? m.starters.of(t.isThai) : const <String>[];
    final topics = p.sectionsFor(t.isThai).length;
    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(MindSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.kpCategory(m.category),
                        style: MindType.overline.copyWith(fontSize: 9.5, color: mode.accent)),
                    const SizedBox(height: 3),
                    Text(m.name.of(t.isThai), style: MindType.title),
                    const SizedBox(height: 2),
                    Text(t.kpTopics(topics, m.version), style: MindType.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              Semantics(
                label: t.kpUseInChat,
                child: Switch.adaptive(
                  value: p.enabled,
                  activeTrackColor: mode.accent,
                  onChanged: (v) => _toggle(context, kp, p.id, v),
                ),
              ),
            ],
          ),
          if (m.category == PackCategory.trading) ...[
            const SizedBox(height: MindSpace.sm),
            Text(t.kpTradingNote, style: MindType.caption.copyWith(fontSize: 11)),
          ],
          if (starters.isNotEmpty) ...[
            const SizedBox(height: MindSpace.sm),
            Text(t.kpTryAsking, style: MindType.caption.copyWith(fontSize: 11)),
            const SizedBox(height: MindSpace.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in starters)
                  GlassChip(label: q, onTap: widget.onAsk == null ? null : () => _ask(context, q)),
              ],
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: Text(t.kpRead),
                onPressed: () => _read(context, p.id),
              ),
              TextButton(
                onPressed: _kpBusyId != null ? null : () => _confirmRemove(context, kp, t, p),
                child: Text(t.packRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bundledCard(BuildContext context, MindMode mode, S t, KnowledgePacks kp, KnowledgeManifest m) {
    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(MindSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.kpBundledTitle, style: MindType.overline.copyWith(fontSize: 9.5, color: mode.accent)),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(child: Text(m.name.of(t.isThai), style: MindType.title)),
              Text(t.shopFree, style: MindType.title),
            ],
          ),
          const SizedBox(height: MindSpace.md),
          if (_kpBusyId == m.id)
            _kpProgress(t, kp)
          else
            MindButton(
              label: t.kpInstall,
              kind: MindButtonKind.primary,
              icon: Icons.download_rounded,
              mode: mode,
              expand: true,
              onTap: _kpBusyId != null || kp.busy ? null : () => _installBundled(context, m),
            ),
        ],
      ),
    );
  }

  /// ขอลิงก์ที่มีลายเซ็น → KnowledgePacks.install · บอกผลทุกทาง (สำเร็จ/ล้ม + เหตุผล)
  Future<void> _installKnowledge(BuildContext context, ShopItem item) async {
    final state = context.read<MindState>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = S.of(context);
    setState(() => _kpBusyId = item.id);
    try {
      final link = await _shop.downloadLink(state.storeBaseUrl, state.licenseKey, item.id);
      if (link == null) {
        _snack(messenger, t.shopUnreachable);
        return;
      }
      final pack = await state.knowledgePacks.install(link.url, sha256Hex: link.sha256, expectId: item.id);
      _snack(messenger, t.kpReady(pack.manifest.name.of(t.isThai)));
    } on KnowledgePackFailure catch (e) {
      debugPrint('shop: ติดตั้งแพ็กความรู้ไม่สำเร็จ — $e');
      _snack(messenger, t.kpError(e.error));
    } on Object catch (e) {
      // ดิสก์เต็ม / เขียนไฟล์ไม่ได้ · ต้องบอก ไม่ใช่แถบความคืบหน้าหายไปเงียบ ๆ
      debugPrint('shop: ติดตั้งแพ็กความรู้ไม่สำเร็จ — ${e.runtimeType}');
      _snack(messenger, t.kpSaveFailed);
    } finally {
      if (mounted) setState(() => _kpBusyId = null);
    }
  }

  Future<void> _installBundled(BuildContext context, KnowledgeManifest m) async {
    final kp = context.read<MindState>().knowledgePacks;
    final bundle = DefaultAssetBundle.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = S.of(context);
    setState(() => _kpBusyId = m.id);
    try {
      final pack = await kp.installBundled(bundle, m.id);
      _snack(messenger, t.kpReady(pack.manifest.name.of(t.isThai)));
    } on KnowledgePackFailure catch (e) {
      debugPrint('shop: ติดตั้งแพ็กฟรีไม่สำเร็จ — $e');
      _snack(messenger, t.kpError(e.error));
    } on Object catch (e) {
      // asset อ่านไม่ได้ / ดิสก์เต็ม · ต้องบอก ไม่ใช่ปุ่มที่กดแล้วเงียบ
      debugPrint('shop: ติดตั้งแพ็กฟรีไม่สำเร็จ — ${e.runtimeType}');
      _snack(messenger, t.kpError(KnowledgePackError.badPack));
    } finally {
      if (mounted) setState(() => _kpBusyId = null);
    }
  }

  Future<void> _toggle(BuildContext context, KnowledgePacks kp, String id, bool on) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = S.of(context);
    try {
      await kp.setEnabled(id, on);
    } on Object catch (e) {
      debugPrint('shop: เปิด/ปิดแพ็กไม่สำเร็จ — ${e.runtimeType}');
      _snack(messenger, t.kpSaveFailed);
    }
  }

  /// ลบต้องถามก่อนเสมอ · ของที่ซื้อแล้วโหลดใหม่ได้ แต่ของฟรีในแอปก็ต้องกดติดตั้งใหม่
  Future<void> _confirmRemove(BuildContext context, KnowledgePacks kp, S t, KnowledgePack p) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.kpRemoveConfirm(p.manifest.name.of(t.isThai))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t.packRemove)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await kp.remove(p.id);
    } on Object catch (e) {
      debugPrint('shop: ลบแพ็กไม่สำเร็จ — ${e.runtimeType}');
      _snack(messenger, t.kpSaveFailed);
    }
  }

  /// หน้าอ่านแพ็ก · "ถามมายด์เรื่องนี้" ในหน้านั้นปิดหน้าอ่านเอง แล้วร้านปิดตามแล้วถามในแชท
  void _read(BuildContext context, String id) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => KnowledgeReaderScreen(
        packId: id,
        onAsk: widget.onAsk == null ? null : (q) => _ask(context, q),
      ),
    ));
  }

  void _ask(BuildContext context, String q) {
    final ask = widget.onAsk;
    if (ask == null) return;
    Navigator.of(context).maybePop();
    ask(q);
  }

  void _snack(ScaffoldMessengerState? m, String text) => m
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
