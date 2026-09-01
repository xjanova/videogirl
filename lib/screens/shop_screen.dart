import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../avatar/avatar_pack.dart';
import '../i18n/strings.dart';
import '../state/mind_state.dart';
import '../store/pack_catalogue.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// ร้านของมายด์ — ซื้อชุด ตัวละครใหม่ และของประดับเวที
///
/// เป็นหน้าที่ push ทับ ไม่ใช่แท็บ เพราะแถบล่างมีห้าช่องและปุ่มกลางต้องอยู่
/// ช่องกลางพอดี (มี assert กันไว้) เพิ่มเป็นหกจะพังโครงนั้นทั้งหมด
/// และร้านไม่ใช่ของที่คนเปิดวันละหลายรอบเหมือนสี่แท็บที่มีอยู่
///
/// **จ่ายเงินบนเว็บ ไม่ใช่ในแอป** — ทำได้เพราะแอปนี้แจกผ่าน GitHub Releases
/// ไม่ได้อยู่บน Play (กฎ Play billing บังคับเฉพาะแอปบน Play)
/// ดู `docs/pack-store.md`
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final PackCatalogue _shop = PackCatalogue();

  /// ชิ้นที่กำลังติดตั้งอยู่ — null = ไม่ได้ติดตั้งอะไรอยู่
  ///
  /// `AvatarPacks` บอกได้แค่ว่า "กำลังโหลดอยู่" ไม่ได้บอกว่าโหลดของชิ้นไหน
  /// หน้านี้มีหลายการ์ด จึงต้องจำเองว่ากดของชิ้นไหนไป ไม่งั้นแถบความคืบหน้า
  /// จะขึ้นพร้อมกันทุกใบ
  String? _installingId;

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

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final mode = context.select<MindState, MindMode>((s) => s.mode);

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
            listenable: _shop,
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
                Expanded(child: _body(context, mode, t)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MindMode mode, S t) {
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

    if (_shop.items.isEmpty) {
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
        itemCount: _shop.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: MindSpace.md),
        itemBuilder: (_, i) => _card(context, mode, t, _shop.items[i]),
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

  Widget _card(BuildContext context, MindMode mode, S t, ShopItem item) {
    final price = item.price <= 0
        ? t.shopFree
        : t.shopPrice(item.price.toStringAsFixed(0), item.currency);

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
          const SizedBox(height: MindSpace.md),
          // ชิ้นที่กำลังติดตั้งอยู่ ให้แถบความคืบหน้าแทนปุ่ม — ปุ่มที่กดแล้ว
          // ไม่ขยับคืออาการเดียวกับปุ่มเสียในสายตาผู้ใช้
          if (busyLabel != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(busyLabel,
                    textAlign: TextAlign.center, style: MindType.caption),
                const SizedBox(height: MindSpace.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  // ตอนแตกไฟล์ไม่รู้ความคืบหน้า ให้แถบวิ่งไปเรื่อย ๆ ดีกว่า
                  // แถบ 0% ที่ค้างนิ่ง ซึ่งอ่านได้ว่าค้างจริง
                  child: LinearProgressIndicator(
                    value: packs.stage == AvatarPackStage.downloading
                        ? packs.progress
                        : null,
                  ),
                ),
              ],
            )
          // ของแจกฟรีต้องโหลดได้เลย ไม่ใช่เด้งไปหน้าจ่ายเงินบนเว็บ
          // (`owned` มาจาก /api/packs/mine ซึ่งต้องมีไลเซนส์ เครื่องที่เพิ่งลง
          // ยังไม่มี ของฟรีจึงขึ้นเป็น owned=false เสมอ ถ้าดูแค่ owned
          // ผู้ใช้จะโดนพาไปจ่ายเงินค่าของที่ราคา 0)
          else if (item.owned || item.price <= 0)
            MindButton(
              label: t.shopGet,
              kind: MindButtonKind.primary,
              icon: Icons.download_rounded,
              mode: mode,
              expand: true,
              // กำลังโหลดชิ้นอื่นอยู่ = กดชิ้นนี้ไม่ได้ · ตัวติดตั้งรับได้ทีละ
              // ชุด (install() คืน false ทันทีถ้าไม่ว่าง) ซึ่งถ้าปล่อยให้กดได้
              // จะเงียบเหมือนปุ่มเสียอีกแบบหนึ่ง
              onTap: anyBusy ? null : () => _install(context, item),
            )
          else ...[
            MindButton(
              label: t.shopBuy,
              kind: MindButtonKind.primary,
              icon: Icons.open_in_new_rounded,
              mode: mode,
              expand: true,
              // ปิดไว้ระหว่างติดตั้งด้วย — เด้งออกเบราว์เซอร์กลางคันแล้วกลับมา
              // เจอชุดติดตั้งค้างครึ่งทางเป็นทางที่ไม่ควรเปิดให้เดินตั้งแต่แรก
              onTap: anyBusy ? null : () => _buy(context, item),
            ),
            const SizedBox(height: MindSpace.xs),
            Text(t.shopBuyOnWeb,
                textAlign: TextAlign.center,
                style: MindType.caption.copyWith(fontSize: 10.5)),
          ],
        ],
      ),
    );
  }

  /// พาไปหน้าซื้อบนเว็บ — จ่ายเสร็จแล้วกลับมากดรีเฟรช
  Future<void> _buy(BuildContext context, ShopItem item) async {
    final base = context.read<MindState>().storeBaseUrl.trim();
    if (base.isEmpty) return;
    final url = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}'
        '/shop/${Uri.encodeComponent(item.id)}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('shop: เปิดหน้าซื้อไม่ได้ — $e');
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
}
