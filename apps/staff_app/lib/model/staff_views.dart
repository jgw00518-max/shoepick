import 'package:flutter/material.dart';

enum StaffView {
  overview,
  inbound,
  pickup,
  returns,
  inventory,
  stockLookup,
  communication,
  orders,
  customers,
  shipping,
  requests,
  approvals,
  analytics,
}

class StaffMenu {
  const StaffMenu(this.view, this.label, this.icon);

  final StaffView view;
  final String label;
  final IconData icon;
}

List<StaffMenu> menusForRole(String role) => switch (role) {
  'branchStaff' => const [
    StaffMenu(StaffView.overview, '대시보드', Icons.dashboard_outlined),
    StaffMenu(StaffView.inbound, '입고', Icons.inventory_2_outlined),
    StaffMenu(StaffView.pickup, '픽업 코드 확인', Icons.pin_outlined),
    StaffMenu(StaffView.returns, '반품', Icons.assignment_return_outlined),
    StaffMenu(StaffView.stockLookup, '현재 재고', Icons.warehouse_outlined),
  ],
  'branchManager' => const [
    StaffMenu(StaffView.overview, '대시보드', Icons.dashboard_outlined),
    StaffMenu(StaffView.inventory, '대리점 보관 현황', Icons.warehouse_outlined),
    StaffMenu(StaffView.inbound, '입고', Icons.inventory_2_outlined),
    StaffMenu(StaffView.pickup, '픽업 코드 확인', Icons.pin_outlined),
    StaffMenu(StaffView.returns, '반품', Icons.assignment_return_outlined),
  ],
  'hqStaff' => const [
    StaffMenu(StaffView.overview, '대시보드', Icons.dashboard_outlined),
    StaffMenu(StaffView.orders, '주문', Icons.receipt_long_outlined),
    StaffMenu(StaffView.customers, '고객 관리', Icons.people_outline),
    StaffMenu(StaffView.returns, '반품 검수', Icons.assignment_return_outlined),
    StaffMenu(StaffView.shipping, '배송', Icons.local_shipping_outlined),
    StaffMenu(StaffView.inventory, '재고', Icons.warehouse_outlined),
    StaffMenu(StaffView.requests, '품의 작성', Icons.edit_note_outlined),
  ],
  'teamLeader' => const [
    StaffMenu(StaffView.overview, '대시보드', Icons.dashboard_outlined),
    StaffMenu(StaffView.approvals, '결재함', Icons.fact_check_outlined),
    StaffMenu(StaffView.inventory, '재고', Icons.warehouse_outlined),
  ],
  'director' => const [
    StaffMenu(StaffView.overview, '대시보드', Icons.dashboard_outlined),
    StaffMenu(StaffView.approvals, '결재함', Icons.fact_check_outlined),
    StaffMenu(StaffView.inventory, '재고', Icons.warehouse_outlined),
  ],
  _ => const [
    StaffMenu(StaffView.overview, '경영 대시보드', Icons.dashboard_outlined),
    StaffMenu(StaffView.analytics, '판매 분석', Icons.bar_chart_outlined),
    StaffMenu(StaffView.inventory, '재고·발주', Icons.warehouse_outlined),
    StaffMenu(StaffView.approvals, '결재 현황', Icons.fact_check_outlined),
  ],
};

String viewTitle(
  StaffView view, {
  required bool isBranch,
  required String role,
}) => switch (view) {
  StaffView.overview => role == 'executive' ? '판매·재고 현황' : '대시보드',
  StaffView.inbound => '입고 관리',
  StaffView.pickup => '고객 상품 수령',
  StaffView.returns => isBranch ? '반품 접수·현황' : '반품 검수',
  StaffView.inventory => isBranch ? '대리점 보관 현황' : '제품별 재고 현황',
  StaffView.stockLookup => '현재 재고 조회',
  StaffView.communication => '업무 소통',
  StaffView.orders => '고객 주문',
  StaffView.customers => '고객 관리',
  StaffView.shipping => '배송 현황',
  StaffView.requests => '제조사 구매 품의',
  StaffView.approvals => '결재함',
  StaffView.analytics => '판매 분석',
};

String viewDescription(
  StaffView view, {
  required bool isBranch,
  required String role,
}) => switch (view) {
  StaffView.overview => switch (role) {
    'branchStaff' => '입고·픽업 결제 코드 확인·반품 현황',
    'branchManager' => '지점 재고와 입고·픽업 업무',
    'hqStaff' => '주문·고객 문의·배송·구매 품의',
    'teamLeader' => '구매 품의 결재와 재고 조회',
    'director' => '구매 품의 최종 결재',
    _ => '판매·재고·발주 분석',
  },
  StaffView.inbound => '도착한 상품을 확인하고 지점 입고를 처리하세요.',
  StaffView.pickup => '고객의 픽업 결제 코드를 확인하고 실물 상품을 인도하세요.',
  StaffView.returns =>
    isBranch
        ? '방문 고객의 반품을 접수하고 소속 지점의 처리 상태를 확인하세요.'
        : '반품 상품을 검수하고 승인 또는 반려하세요.',
  StaffView.inventory =>
    isBranch ? '본사에서 받은 주문 상품의 보관 상태를 조회하세요.' : '본사의 실물·예약·불량·가용 재고를 조회하세요.',
  StaffView.stockLookup => '현장 처리에 필요한 현재 재고를 조회하세요.',
  StaffView.communication => '지점과 본사 담당자에게 업무를 전달하고 답변을 확인하세요.',
  StaffView.orders => '구매 신청과 희망 대리점을 확인하세요.',
  StaffView.customers =>
    role == 'hqStaff'
        ? '고객 목록·구매 이력과 문의를 확인하고 처리하세요.'
        : '고객 현황과 혜택 승인 요청을 검토하세요.',
  StaffView.shipping => '대리점으로 보낼 주문과 배송 단계를 관리하세요.',
  StaffView.requests => '재고 부족 상품의 제조사 구매 품의를 작성하세요.',
  StaffView.approvals => '담당 단계의 품의를 검토하고 결재하세요.',
  StaffView.analytics => '기간·제품·대리점별 판매 현황을 조회하세요.',
};
