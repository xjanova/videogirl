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
          // ของแจกฟรีต้องโหลดได้เลย ไม่ใช่เด้งไปหน้าจ่ายเงินบนเว็บ
          // (`owned` มาจาก /api/packs/mine ซึ่งต้องมีไลเซนส์ เครื่องที่เพิ่งลง
          // ยังไม่มี ของฟรีจึงขึ้นเป็น owned=false เสมอ ถ้าดูแค่ owned
          // ผู้ใช้จะโดนพาไปจ่ายเงินค่าของที่ราคา 0)
          if (item.owned || item.price <= 0)
            MindButton(
              label: t.shopGet,
              kind: MindButtonKind.primary,
              icon: Icons.download_rounded,
              mode: mode,
              expand: true,
              onTap: () => _install(context, item),
            )
          else ...[
            MindButton(
              label: t.shopBuy,
              kind: MindButtonKind.primary,
              icon: Icons.open_in_new_rounded,
              mode: mode,
              expand: true,
              onTap: () => _buy(context, item),
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
  Future<void> _install(BuildContext context, ShopItem item) async {
    final state = context.read<MindState>();
    final packs = context.read<AvatarPacks>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = S.of(context);

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
    await packs.install(link.url, expectedSha256: link.sha256);
  }
}
