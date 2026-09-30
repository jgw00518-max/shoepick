import 'package:flutter/material.dart';
import '../localization.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';

/// 선택된 주문을 기준으로 픽업·배송 상태를 표시합니다.
class ShippingScreen extends StatefulWidget {
  const ShippingScreen({
    super.key,
    required this.store,
    required this.order,
    required this.onOrders,
  });
  final StoreController store;
  final StoreOrder? order;
  final VoidCallback onOrders;
  @override
  State<ShippingScreen> createState() => _ShippingScreenState();
}

class _ShippingScreenState extends State<ShippingScreen> {
  bool copied = false;
  static const tracking = '5012-8473-1190';

  Future<void> _call(String number) async {
    try {
      if (!await launchUrl(Uri(scheme: 'tel', path: number)) && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('전화 앱을 열 수 없습니다.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('전화 앱을 열 수 없습니다.')));
      }
    }
  }

  Future<void> _cancel(StoreOrder order) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('주문을 취소할까요?'),
        content: const LText('대리점에서 상품을 수령하기 전까지만 취소할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText('주문 취소'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.store.cancelOrder(order);
    widget.onOrders();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    if (order == null) return const EmptyState('조회할 주문이 없습니다.');
    const steps = [
      ('본사 출고 준비', '09.28 09:10', '상품 검수와 포장이 완료되었습니다.'),
      ('본사 출고', '09.28 14:25', 'SOLE 본사 물류센터에서 출발했습니다.'),
      ('대리점 이동 중', '09.29 08:40', '대리점으로 이동하고 있습니다.'),
      ('대리점 도착', '09.29 13:42', '픽업 장소에 상품이 준비되었습니다.'),
      ('고객 픽업 완료', '픽업 후 반영', '고객에게 상품 전달이 완료되었습니다.'),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle('픽업 배송 조회'),
        const LText('본사에서 대리점까지의 배송과 픽업 상태를 확인하세요.'),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText('픽업 가능'),
                LText(
                  '${order.district} 대리점에 도착했습니다',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const LText('영업시간 안에 방문하여 QR 코드를 보여주세요.'),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText('픽업 대리점'),
                LText(
                  'SOLE ${order.district}점',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const LText('서울 성동구 왕십리로 83, 1층'),
                const LText('오늘 10:30 - 20:00'),
                TextButton(
                  onPressed: () => _call('02-2299-0245'),
                  child: const LText('대리점 전화'),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText('운송사 · CJ대한통운 기업배송'),
                const LText('운송장 번호 · $tracking'),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: tracking),
                    );
                    if (mounted) setState(() => copied = true);
                  },
                  child: LText(copied ? '복사됨 ✓' : '번호 복사'),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            TextButton(
              onPressed: () => _call('1588-1255'),
              child: const LText('운송사 연결'),
            ),
            TextButton(
              onPressed: () => _call('02-2299-0245'),
              child: const LText('대리점 문의'),
            ),
          ],
        ),
        const SectionTitle('배송 현황'),
        for (var index = 0; index < steps.length; index++)
          ListTile(
            leading: Icon(
              index <= 3 ? Icons.check_circle : Icons.circle_outlined,
              color: index <= 3 ? brandBlue : Colors.grey,
            ),
            title: LText(steps[index].$1),
            subtitle: LText('${steps[index].$2} · ${steps[index].$3}'),
          ),
        if (!order.canceled)
          OutlinedButton(
            onPressed: () => _cancel(order),
            child: const LText('주문 취소'),
          ),
        OutlinedButton(
          onPressed: widget.onOrders,
          child: const LText('주문 내역으로 돌아가기'),
        ),
      ],
    );
  }
}

/// 목업 쿠폰의 수령 상태만 변경하며 실제 발급은 하지 않습니다.
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  final Set<int> received = {};
  @override
  Widget build(BuildContext context) {
    const coupons = [
      ('10%', '신규 회원 웰컴 쿠폰', '최소 50,000원 · 전 카테고리'),
      ('5,000원', '앱 첫 구매 할인', '최소 30,000원 · 전 카테고리'),
      ('무료 배송', 'VIP 무료 배송 쿠폰', '최소 금액 없음 · 전 카테고리'),
      ('15%', '운동화 기획전 쿠폰', '최소 100,000원 · 운동화 카테고리'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle('쿠폰'),
        const LText('사용 가능한 쿠폰 4장'),
        const SizedBox(height: 12),
        const Row(
          children: [LText('사용 가능'), SizedBox(width: 20), LText('사용 완료')],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < coupons.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  LText(
                    coupons[index].$1,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: brandBlue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          coupons[index].$2,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        LText(
                          '${coupons[index].$3}\n10월 31일까지',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: received.contains(index)
                        ? null
                        : () => setState(() => received.add(index)),
                    child: LText(received.contains(index) ? '받음' : '받기'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class PointsScreen extends StatelessWidget {
  const PointsScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SectionTitle('적립금'),
      const LText('쇼핑할수록 쌓이는 SOLE 포인트'),
      const SizedBox(height: 22),
      Card(
        color: brandBlue,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              LText('사용 가능 적립금', style: TextStyle(color: Colors.white70)),
              LText(
                '32,500P',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              LText(
                '30일 이내 소멸 예정 1,200P',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      const SectionTitle('적립 내역'),
      for (final item in [
        ('구매 적립', 'Aero Shift 01 구매', '+3,780P'),
        ('리뷰 적립', '포토 리뷰 작성', '+1,000P'),
        ('주문 사용', 'Silver Current 주문', '-12,000P'),
      ])
        ListTile(
          title: LText(item.$1),
          subtitle: LText(item.$2),
          trailing: LText(item.$3),
        ),
    ],
  );
}
