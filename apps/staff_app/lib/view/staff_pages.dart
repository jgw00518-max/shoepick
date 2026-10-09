import 'package:shoepick_staff_app/view/branch_inventory.dart';
import 'package:flutter/material.dart';
import 'package:shoepick_staff_app/model/staff_analytics_data.dart';
import 'package:shoepick_staff_app/model/staff_order.dart';
import 'package:shoepick_staff_app/model/staff_session.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/branch_return_registration.dart';
import 'package:shoepick_staff_app/view/return_refund_panel.dart';
import 'package:shoepick_staff_app/vm/staff_order_api.dart';
import 'package:shoepick_staff_app/vm/staff_work_api.dart';
import 'package:shoepick_staff_app/vm/headquarters_inventory_api.dart';

const _blue = Color(0xFF2563C6);
const _ink = Color(0xFF1B2B40);
const _muted = Color(0xFF66768B);
const _line = Color(0xFFE2E8F0);
const _red = Color(0xFFCF3948);
const _green = Color(0xFF126D66);

class StaffPage extends StatefulWidget {
  const StaffPage({
    super.key,
    required this.view,
    required this.roleKey,
    required this.isBranch,
    this.selectedBranchId,
    this.orderRepository,
    this.workApi,
    this.headquartersInventoryApi,
  });

  final StaffView view;
  final String roleKey;
  final bool isBranch;
  final int? selectedBranchId;
  final StaffOrderRepository? orderRepository;
  final StaffWorkApi? workApi;
  final HeadquartersInventoryApi? headquartersInventoryApi;

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  final pickupCodeController = TextEditingController();
  String? verifiedPickupCode;
  StaffOrder? verifiedPickupOrder;
  String? pickupError;
  late final StaffOrderRepository orderRepository;
  late final StaffWorkApi workApi;
  Map<String, dynamic>? inventoryData;
  Map<String, dynamic>? analyticsData;
  List<Map<String, dynamic>> requisitionData = [];
  List<Map<String, dynamic>> inquiryData = [];
  List<Map<String, dynamic>> customerData = [];
  String customerSort = '최근 주문순';
  bool customerDetailLoading = false;
  List<Map<String, dynamic>> returnData = [];
  int? selectedReturnId;
  final returnNotesController = TextEditingController();
  bool returnWearMarks = false;
  bool returnProductDamage = false;
  bool returnCustomerFault = false;
  bool returnComponentsComplete = true;
  bool returnPackagingIntact = true;
  bool returnProductDefect = false;
  bool returnWrongItem = false;
  Map<String, dynamic>? customerDetail;
  int? selectedCustomerId;
  bool workLoading = false;
  String? workError;
  final inventorySearchController = TextEditingController();
  late final HeadquartersInventoryApi headquartersInventoryApi;
  int inventoryPage = 1;
  int inventoryTotalCount = 0;
  int inventoryRequestNumber = 0;
  String inventoryKeyword = '';
  String inventorySort = 'updated_at';
  int? selectedVariantId;
  final requestTitleController = TextEditingController();
  final requestQuantityController = TextEditingController();
  final requestReasonController = TextEditingController();
  final decisionCommentController = TextEditingController();
  final inquiryAnswerController = TextEditingController();
  int? selectedInquiryId;
  List<StaffOrder> liveOrders = [];
  bool ordersLoading = false;
  bool actionBusy = false;
  String? ordersError;
  String query = '';
  String sort = '최신 접수순';
  String period = '최근 28일';
  String selectedProduct = '전체 제품';
  String selectedBranch = '전체 대리점';

  @override
  void initState() {
    super.initState();
    orderRepository = widget.orderRepository ?? MockStaffOrderRepository();
    workApi = widget.workApi ?? StaffWorkApi();
    headquartersInventoryApi =
        widget.headquartersInventoryApi ?? HeadquartersInventoryApi();
    if ({
      StaffView.inbound,
      StaffView.pickup,
      StaffView.orders,
      StaffView.shipping,
    }.contains(widget.view)) {
      _loadOrders();
    }
    if ({
      StaffView.inventory,
      StaffView.stockLookup,
      StaffView.requests,
      StaffView.approvals,
      StaffView.customers,
      StaffView.returns,
      StaffView.analytics,
    }.contains(widget.view)) {
      _loadWork();
    }
  }

  Future<void> _loadWork() async {
    if (widget.isBranch &&
        {StaffView.inventory, StaffView.stockLookup}.contains(widget.view)) {
      return;
    }
    if (widget.view == StaffView.inventory && !widget.isBranch) {
      await _loadHeadquartersInventory();
      return;
    }
    setState(() {
      workLoading = true;
      workError = null;
    });
    try {
      if ({StaffView.inventory, StaffView.stockLookup}.contains(widget.view)) {
        inventoryData = await workApi.inventory(
          branchId: widget.isBranch ? widget.selectedBranchId : null,
        );
      } else if (widget.view == StaffView.requests) {
        final results = await Future.wait<dynamic>([
          workApi.inventory(),
          workApi.requisitions(),
        ]);
        inventoryData = results[0] as Map<String, dynamic>;
        requisitionData = results[1] as List<Map<String, dynamic>>;
      } else if (widget.view == StaffView.approvals) {
        requisitionData = await workApi.requisitions();
      } else if (widget.view == StaffView.customers &&
          widget.roleKey == 'hqStaff') {
        final results = await Future.wait<dynamic>([
          workApi.inquiries(),
          workApi.customers(),
        ]);
        inquiryData = results[0] as List<Map<String, dynamic>>;
        customerData = results[1] as List<Map<String, dynamic>>;
        if (selectedCustomerId != null) {
          customerDetail = await workApi.customerDetail(selectedCustomerId!);
        }
      } else if (widget.view == StaffView.returns) {
        returnData = await workApi.returns(
          branchId: widget.isBranch ? widget.selectedBranchId : null,
        );
      } else if (widget.view == StaffView.analytics) {
        final products = ((analyticsData?['products'] as List<dynamic>?) ?? []);
        final branches = ((analyticsData?['branches'] as List<dynamic>?) ?? []);
        final product = products
            .where((item) => item['name'] == selectedProduct)
            .firstOrNull;
        final branch = branches
            .where((item) => item['name'] == selectedBranch)
            .firstOrNull;
        analyticsData = normalizeStaffAnalytics(
          await workApi.analytics(
            days: int.parse(RegExp(r'\d+').firstMatch(period)!.group(0)!),
            productId: product?['id'] as int?,
            branchId: branch?['id'] as int?,
          ),
        );
      }
      if (mounted) setState(() {});
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => workError = error.message);
    } catch (_) {
      if (mounted) setState(() => workError = '업무 데이터를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => workLoading = false);
    }
  }

  List<Map<String, dynamic>> get inventoryRows =>
      ((inventoryData?['rows'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();

  Future<void> _loadHeadquartersInventory() async {
    final request = ++inventoryRequestNumber;
    setState(() {
      workLoading = true;
      workError = null;
      inventoryData = null;
    });
    try {
      final result = await headquartersInventoryApi.fetch(
        page: inventoryPage,
        keyword: inventoryKeyword,
        sort: inventorySort,
      );
      if (!mounted || request != inventoryRequestNumber) return;
      setState(() {
        inventoryData = {'rows': result.rows};
        inventoryTotalCount = result.totalCount;
      });
    } on StaffAuthException catch (error) {
      if (mounted && request == inventoryRequestNumber) {
        setState(() => workError = error.message);
      }
    } finally {
      if (mounted && request == inventoryRequestNumber) {
        setState(() => workLoading = false);
      }
    }
  }

  Widget _workState() => _stack([
    _action('새로고침', onPressed: _loadWork),
    if (workLoading) const Center(child: CircularProgressIndicator()),
    if (workError != null) _notice(workError!, warning: true),
  ]);

  Future<void> _inspectReturn(bool accepted) async {
    final id = selectedReturnId;
    final notes = returnNotesController.text.trim();
    if (id == null || notes.isEmpty) {
      setState(() => workError = '반품 요청을 선택하고 검수 메모를 입력해주세요.');
      return;
    }
    if (actionBusy) return;
    setState(() {
      actionBusy = true;
      workError = null;
    });
    try {
      await workApi.inspectReturn(id, {
        'accepted': accepted,
        'notes': notes,
        'hasWearMarks': returnWearMarks,
        'hasProductDamage': returnProductDamage,
        'hasCustomerFault': returnCustomerFault,
        'componentsComplete': returnComponentsComplete,
        'packagingIntact': returnPackagingIntact,
        'hasProductDefect': returnProductDefect,
        'isWrongItem': returnWrongItem,
      });
      if (mounted) {
        setState(() => selectedReturnId = null);
        returnNotesController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accepted ? '반품 검수를 승인했습니다.' : '반품 검수를 반려했습니다.'),
          ),
        );
        await _loadWork();
      }
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => workError = error.message);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _createAndSubmitRequisition() async {
    final variantId = selectedVariantId;
    final quantity = int.tryParse(requestQuantityController.text.trim());
    final title = requestTitleController.text.trim();
    final reason = requestReasonController.text.trim();
    if (variantId == null ||
        quantity == null ||
        quantity <= 0 ||
        title.isEmpty ||
        reason.isEmpty) {
      setState(() => workError = '제품, 수량, 제목, 사유를 모두 입력해주세요.');
      return;
    }
    if (actionBusy) return;
    setState(() {
      actionBusy = true;
      workError = null;
    });
    try {
      final created = await workApi.createRequisition(
        productVariantId: variantId,
        quantity: quantity,
        title: title,
        reason: reason,
      );
      await workApi.submitRequisition(created['purchaseRequisitionId'] as int);
      requestTitleController.clear();
      requestQuantityController.clear();
      requestReasonController.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('구매 품의를 상신했습니다.')));
        await _loadWork();
      }
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => workError = error.message);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _decideRequisition(int id, String decision) async {
    decisionCommentController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(decision == 'APPROVED' ? '품의 승인' : '품의 반려'),
        content: TextField(
          controller: decisionCommentController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '검토 의견',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || actionBusy) return;
    setState(() {
      actionBusy = true;
      workError = null;
    });
    try {
      await workApi.decideRequisition(
        id,
        decision,
        decisionCommentController.text.trim(),
      );
      if (mounted) await _loadWork();
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => workError = error.message);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _selectCustomer(int id) async {
    setState(() {
      selectedCustomerId = id;
      customerDetail = null;
      customerDetailLoading = true;
      workError = null;
    });
    try {
      final detail = await workApi.customerDetail(id);
      if (mounted && selectedCustomerId == id) {
        setState(() => customerDetail = detail);
      }
    } on StaffAuthException catch (error) {
      if (mounted && selectedCustomerId == id) {
        setState(() => workError = error.message);
      }
    } finally {
      if (mounted && selectedCustomerId == id) {
        setState(() => customerDetailLoading = false);
      }
    }
  }

  Future<void> _answerInquiry(int id) async {
    final answer = inquiryAnswerController.text.trim();
    if (answer.isEmpty) {
      setState(() => workError = '답변을 입력해주세요.');
      return;
    }
    if (actionBusy) return;
    setState(() {
      actionBusy = true;
      workError = null;
    });
    try {
      await workApi.answerInquiry(id, answer);
      inquiryAnswerController.clear();
      if (mounted) await _loadWork();
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => workError = error.message);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _loadOrders() async {
    setState(() {
      ordersLoading = true;
      ordersError = null;
    });
    try {
      final result = await orderRepository.listOrders(
        branchId: widget.isBranch ? widget.selectedBranchId : null,
      );
      if (mounted) setState(() => liveOrders = result);
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => ordersError = error.message);
    } catch (_) {
      if (mounted) setState(() => ordersError = '주문을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => ordersLoading = false);
    }
  }

  String _statusLabel(String status) => switch (status) {
    'PAID' => '결제 완료',
    'PREPARING' => '발송 대기',
    'IN_TRANSIT' => '배송 중',
    'READY_FOR_PICKUP' => '입고 완료',
    'COMPLETED' => '수령 완료',
    'CANCELED' => '취소',
    'REFUNDED' => '환불',
    _ => status,
  };

  Future<void> _markArrived(StaffOrder order) async {
    if (order.fulfillmentId == null || actionBusy) return;
    setState(() => actionBusy = true);
    try {
      await orderRepository.markArrived(order.fulfillmentId!);
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지점 입고를 완료했습니다.')));
      }
    } on StaffAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _ship(StaffOrder order) async {
    if (order.fulfillmentId == null || actionBusy) return;
    setState(() => actionBusy = true);
    try {
      await orderRepository.shipFulfillment(order.fulfillmentId!);
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('상품 발송을 완료했습니다.')));
      }
    } on StaffAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  @override
  void dispose() {
    inventorySearchController.dispose();
    if (widget.headquartersInventoryApi == null) {
      headquartersInventoryApi.close();
    }
    pickupCodeController.dispose();
    returnNotesController.dispose();
    requestTitleController.dispose();
    requestQuantityController.dispose();
    requestReasonController.dispose();
    decisionCommentController.dispose();
    inquiryAnswerController.dispose();
    super.dispose();
  }

  Future<void> _verifyPickupCode() async {
    final code = pickupCodeController.text.trim().toUpperCase();
    if (code.isEmpty || actionBusy) {
      setState(() => pickupError = '픽업 결제 코드를 입력해주세요.');
      return;
    }
    setState(() {
      actionBusy = true;
      verifiedPickupCode = null;
      verifiedPickupOrder = null;
      pickupError = null;
    });
    try {
      final order = await orderRepository.verifyPickup(code);
      if (mounted) {
        setState(() {
          verifiedPickupCode = code;
          verifiedPickupOrder = order;
        });
      }
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => pickupError = error.message);
    } catch (_) {
      if (mounted) setState(() => pickupError = '픽업 결제 코드를 확인하지 못했습니다.');
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _completePickup() async {
    final order = verifiedPickupOrder;
    final code = verifiedPickupCode;
    if (order == null || code == null || actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('고객 수령 완료'),
        content: Text(
          '${order.number}\n${order.customerName} · ${order.branchName}\n실물 상품을 인도했습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('인도 완료'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => actionBusy = true);
    try {
      await orderRepository.completePickup(order, code);
      pickupCodeController.clear();
      if (mounted) {
        setState(() {
          verifiedPickupCode = null;
          verifiedPickupOrder = null;
          pickupError = null;
        });
      }
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('고객 수령을 완료했습니다.')));
      }
    } on StaffAuthException catch (error) {
      if (mounted) setState(() => pickupError = error.message);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  void _clearPickupVerification() {
    setState(() {
      verifiedPickupCode = null;
      verifiedPickupOrder = null;
      pickupError = null;
    });
  }

  @override
  Widget build(BuildContext context) => switch (widget.view) {
    StaffView.inbound => _inbound(),
    StaffView.pickup => _pickup(),
    StaffView.returns => _returns(),
    StaffView.inventory =>
      widget.isBranch ? _branchInventory() : _hqInventory(),
    StaffView.stockLookup => _stockLookup(),
    StaffView.communication => _unavailable('직원 간 업무 소통'),
    StaffView.orders => _orders(),
    StaffView.customers => _customers(),
    StaffView.shipping => _shipping(),
    StaffView.requests => _requests(),
    StaffView.approvals => _approvals(),
    StaffView.analytics => _analytics(),
    StaffView.overview => const SizedBox.shrink(),
  };

  Widget _unavailable(String title) => _panel(
    title,
    '현재 서버에 처리 기록과 API가 없습니다.',
    _empty('기존 DB/API 범위에서 사용할 수 있는 업무가 없습니다.'),
  );

  Widget _inbound() {
    final arriving = liveOrders
        .where((order) => order.fulfillmentStatus == 'IN_TRANSIT')
        .toList();
    final ready = liveOrders
        .where((order) => order.status == 'READY_FOR_PICKUP')
        .length;
    return _stack([
      _metrics([
        ('배송 중', '${arriving.length}건', '입고 확인 필요'),
        ('입고 완료', '$ready건', '고객 수령 대기'),
      ]),
      _panel(
        '입고 대상 주문',
        '실물 상품을 확인한 뒤 입고 처리하세요.',
        _stack([
          _action('새로고침', onPressed: _loadOrders),
          if (ordersLoading) const Center(child: CircularProgressIndicator()),
          if (ordersError != null) _notice(ordersError!, warning: true),
          if (!ordersLoading && arriving.isEmpty) _empty('현재 배송 중인 주문이 없습니다.'),
          for (final order in arriving)
            _orderCard(
              order.number,
              order.productSummary,
              '${order.branchName} · ${order.customerName}',
              '배송 중',
              action: '입고 확인',
              onAction: () => _markArrived(order),
            ),
        ]),
      ),
    ]);
  }

  Widget _pickup() => _stack([
    _notice('고객 수령 절차 · 픽업 결제 코드 입력 → 주문·고객·상품·지점 확인 → 실물 인도'),
    _panel(
      '픽업 결제 코드 확인',
      '고객이 제시한 픽업 결제 코드를 입력하세요.',
      _stack([
        _field(
          '픽업 결제 코드',
          '고객이 제시한 코드를 입력하세요',
          controller: pickupCodeController,
          onChanged: (_) => _clearPickupVerification(),
        ),
        _action('코드 확인', primary: true, onPressed: _verifyPickupCode),
        if (pickupError != null) _notice(pickupError!, warning: true),
        if (verifiedPickupOrder != null) ...[
          _notice('코드 확인 완료 · 주문·고객·상품·지점을 실물과 대조한 뒤 인도하세요.'),
          _orderCard(
            verifiedPickupOrder!.number,
            verifiedPickupOrder!.productSummary,
            '${verifiedPickupOrder!.branchName} · ${verifiedPickupOrder!.customerName}',
            '입고 완료',
            action: '고객 수령 완료',
            onAction: _completePickup,
          ),
        ],
      ]),
    ),
    _panel(
      '수령 대기 주문',
      '현재 소속 지점의 주문입니다. 고객이 제시한 코드를 별도로 확인하세요.',
      _stack([
        _action('새로고침', onPressed: _loadOrders),
        if (ordersLoading) const Center(child: CircularProgressIndicator()),
        if (ordersError != null) _notice(ordersError!, warning: true),
        if (!ordersLoading &&
            liveOrders.every((order) => order.status != 'READY_FOR_PICKUP'))
          _empty('수령 대기 주문이 없습니다.'),
        for (final order in liveOrders.where(
          (order) => order.status == 'READY_FOR_PICKUP',
        ))
          _orderCard(
            order.number,
            order.productSummary,
            '${order.branchName} · ${order.customerName}',
            '입고 완료',
          ),
      ]),
    ),
  ]);

  Widget _returns() => _stack([
    _notice(
      widget.isBranch
          ? '고객이 방문하면 주문과 상품을 확인해 반품을 접수하세요. 접수 후 본사에서 검수합니다.'
          : '대리점에서 접수한 반품을 확인하고 실물 검수 후 승인 또는 반려합니다.',
    ),
    _workState(),
    if (widget.isBranch)
      _panel(
        '반품 접수',
        '고객의 주문번호로 소속 지점 주문을 조회합니다.',
        BranchReturnRegistration(
          branchId: widget.selectedBranchId,
          api: workApi,
          onRegistered: _loadWork,
        ),
      ),
    _panel(
      '반품 진행 현황',
      '현재 접수된 반품 요청',
      returnData.isEmpty
          ? _empty('반품 요청이 없습니다.')
          : _table(
              const ['반품번호', '주문번호', '고객', '지점', '상태'],
              [
                for (final row in returnData)
                  [
                    '${row['id']}',
                    row['orderNumber'].toString(),
                    row['customerName'].toString(),
                    row['branchName'].toString(),
                    row['status'].toString(),
                  ],
              ],
            ),
    ),
    if (!widget.isBranch)
      _panel(
        '본사 반품 검수',
        '접수 상태인 요청을 선택하고 실제 상품 상태를 확인하세요.',
        _stack([
          if (returnData.where((row) => row['status'] == 'REQUESTED').isEmpty)
            _empty('검수 대기 요청이 없습니다.'),
          for (final row in returnData.where(
            (row) => row['status'] == 'REQUESTED',
          ))
            _choiceTile(
              '반품 #${row['id']} · ${row['orderNumber']}',
              '${row['customerName']} · ${row['reason']}',
              selectedReturnId == row['id'],
              () => setState(() => selectedReturnId = row['id'] as int),
            ),
          if (selectedReturnId != null) ...[
            CheckboxListTile(
              value: returnWearMarks,
              title: const Text('착용 흔적 있음'),
              onChanged: (value) =>
                  setState(() => returnWearMarks = value ?? false),
            ),
            CheckboxListTile(
              value: returnProductDamage,
              title: const Text('상품 훼손 있음'),
              onChanged: (value) =>
                  setState(() => returnProductDamage = value ?? false),
            ),
            CheckboxListTile(
              value: returnCustomerFault,
              title: const Text('고객 과실 있음'),
              onChanged: (value) =>
                  setState(() => returnCustomerFault = value ?? false),
            ),
            CheckboxListTile(
              value: returnComponentsComplete,
              title: const Text('구성품 완비'),
              onChanged: (value) =>
                  setState(() => returnComponentsComplete = value ?? false),
            ),
            CheckboxListTile(
              value: returnPackagingIntact,
              title: const Text('포장 상태 양호'),
              onChanged: (value) =>
                  setState(() => returnPackagingIntact = value ?? false),
            ),
            CheckboxListTile(
              value: returnProductDefect,
              title: const Text('상품 자체 하자'),
              onChanged: (value) =>
                  setState(() => returnProductDefect = value ?? false),
            ),
            CheckboxListTile(
              value: returnWrongItem,
              title: const Text('다른 상품 배송'),
              onChanged: (value) =>
                  setState(() => returnWrongItem = value ?? false),
            ),
            _field(
              '검수 메모',
              '검수 결과와 판단 근거',
              controller: returnNotesController,
              lines: 3,
            ),
            Wrap(
              spacing: 8,
              children: [
                _action(
                  '반려',
                  onPressed: actionBusy ? null : () => _inspectReturn(false),
                ),
                _action(
                  '승인',
                  primary: true,
                  onPressed: actionBusy ? null : () => _inspectReturn(true),
                ),
              ],
            ),
          ],
        ]),
      ),
    if (!widget.isBranch)
      _panel(
        '반품 환불 처리',
        '본사 검수에서 승인된 반품의 환불 내역을 확인합니다.',
        ReturnRefundPanel(
          returns: returnData,
          api: workApi,
          onProcessed: _loadWork,
        ),
      ),
  ]);

  Widget _branchInventory() =>
      BranchInventoryView(branchId: widget.selectedBranchId);

  Widget _hqInventory() => _stack([
    TextField(
      key: const Key('hq-inventory-search'),
      controller: inventorySearchController,
      decoration: InputDecoration(
        labelText: '상품명 또는 상품 코드',
        suffixIcon: IconButton(
          tooltip: '검색',
          icon: const Icon(Icons.search),
          onPressed: workLoading ? null : _searchHeadquartersInventory,
        ),
      ),
      onSubmitted: (_) => _searchHeadquartersInventory(),
    ),
    DropdownButton<String>(
      value: inventorySort,
      items: const [
        DropdownMenuItem(value: 'updated_at', child: Text('최근 변경순')),
        DropdownMenuItem(value: 'product_name', child: Text('상품명순')),
        DropdownMenuItem(value: 'product_code', child: Text('상품 코드순')),
        DropdownMenuItem(value: 'available_quantity', child: Text('가용 재고 적은순')),
      ],
      onChanged: workLoading
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                inventorySort = value;
                inventoryPage = 1;
              });
              _loadWork();
            },
    ),
    _workState(),
    if (!workLoading && workError == null)
      Text('조회 결과 $inventoryTotalCount종 · $inventoryPage페이지'),
    _inventoryTable(),
    Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(
          onPressed: workLoading || inventoryPage <= 1
              ? null
              : () {
                  setState(() => inventoryPage--);
                  _loadWork();
                },
          child: const Text('이전'),
        ),
        OutlinedButton(
          onPressed:
              workLoading ||
                  workError != null ||
                  inventoryPage * 20 >= inventoryTotalCount
              ? null
              : () {
                  setState(() => inventoryPage++);
                  _loadWork();
                },
          child: const Text('다음'),
        ),
      ],
    ),
  ]);

  void _searchHeadquartersInventory() {
    setState(() {
      inventoryKeyword = inventorySearchController.text.trim();
      inventoryPage = 1;
    });
    _loadWork();
  }

  Widget _stockLookup() => widget.isBranch
      ? _branchInventory()
      : _stack([_workState(), _inventoryTable()]);

  Widget _inventoryTable() {
    final hq = !widget.isBranch;
    return _panel(
      hq ? '제품별 본사 재고' : '현재 지점 보관 상품',
      hq
          ? '현재 보유·예약·가용 수량'
          : (inventoryData?['branchName'] as String? ?? '소속 지점'),
      workError != null || workLoading
          ? const SizedBox.shrink()
          : inventoryRows.isEmpty
          ? _empty('표시할 재고가 없습니다.')
          : _table(
              hq
                  ? const ['제품', '옵션', '제품 코드', '보유', '예약', '불량', '가용']
                  : const ['제품', '옵션', '제품 코드', '보관 수량'],
              [
                for (final row in inventoryRows)
                  [
                    row['product_name'].toString(),
                    '${row['color_name']} / ${row['size_mm']}',
                    row['product_code'].toString(),
                    '${row['quantity']}',
                    if (hq) ...[
                      '${row['reserved_quantity']}',
                      '${row['defective_quantity'] ?? 0}',
                      '${row['available_quantity']}',
                    ],
                  ],
              ],
            ),
    );
  }

  Widget _orders() {
    final rows = [
      for (final order in liveOrders)
        [
          '${order.number} · ${order.customerName}',
          order.productSummary,
          order.branchName,
          _statusLabel(order.status),
          order.orderedAt == null
              ? '-'
              : '${order.orderedAt!.month.toString().padLeft(2, '0')}.${order.orderedAt!.day.toString().padLeft(2, '0')}',
        ],
    ];
    final filtered = rows
        .where((row) => row[0].toLowerCase().contains(query.toLowerCase()))
        .toList();
    if (sort == '오래된 접수순') {
      filtered.sort((a, b) => a[4].compareTo(b[4]));
    } else if (sort == '발송 대기 우선') {
      filtered.sort(
        (a, b) => (b[3] == '발송 대기' ? 1 : 0) - (a[3] == '발송 대기' ? 1 : 0),
      );
    } else if (sort == '대리점 가나다순') {
      filtered.sort((a, b) => a[2].compareTo(b[2]));
    }
    return _panel(
      '주문 조회',
      '고객이 선택한 대리점으로 발송됩니다.',
      _stack([
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 260,
              child: _field(
                '구매번호',
                '예: ORD-1042',
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            SizedBox(
              width: 190,
              child: _select(
                '정렬 기준',
                const ['최신 접수순', '오래된 접수순', '발송 대기 우선', '대리점 가나다순'],
                value: sort,
                onChanged: (value) => setState(() => sort = value),
              ),
            ),
            _action('새로고침', primary: true, onPressed: _loadOrders),
          ],
        ),
        if (ordersLoading) const Center(child: CircularProgressIndicator()),
        if (ordersError != null) _notice(ordersError!, warning: true),
        filtered.isEmpty
            ? _empty('검색 조건에 맞는 주문이 없습니다.')
            : _table(const [
                '구매번호 / 고객',
                '제품',
                '희망 대리점',
                '상태',
                '신청일',
              ], filtered),
      ]),
    );
  }

  Widget _shipping() {
    final preparing = liveOrders
        .where((order) => order.fulfillmentStatus == 'PREPARING')
        .toList();
    final inTransit = liveOrders
        .where((order) => order.fulfillmentStatus == 'IN_TRANSIT')
        .length;
    final ready = liveOrders
        .where((order) => order.status == 'READY_FOR_PICKUP')
        .length;
    final completed = liveOrders
        .where((order) => order.status == 'COMPLETED')
        .length;
    return _stack([
      _notice('결제 완료 주문의 예약 재고를 확인한 뒤 선택한 대리점으로 발송 처리합니다.'),
      _metrics([
        ('발송 대기', '${preparing.length}건', '처리 필요'),
        ('배송 중', '$inTransit건', '대리점 입고 대기'),
        ('대리점 도착', '$ready건', '고객 수령 대기'),
        ('수령 완료', '$completed건', '인도 처리 완료'),
      ]),
      _panel(
        '주문별 배송 단계',
        '본사 발송 후 대리점에서 입고를 확인합니다.',
        _stack([
          _action('새로고침', onPressed: _loadOrders),
          if (ordersLoading) const Center(child: CircularProgressIndicator()),
          if (ordersError != null) _notice(ordersError!, warning: true),
          if (!ordersLoading && preparing.isEmpty) _empty('발송 대기 주문이 없습니다.'),
          for (final order in preparing)
            _orderCard(
              order.number,
              order.productSummary,
              '${order.branchName} · ${order.customerName}',
              '발송 대기',
              action: '발송 처리',
              onAction: () => _ship(order),
            ),
        ]),
      ),
    ]);
  }

  Widget _requests() => _stack([
    _workState(),
    _pair(
      _panel(
        '제조사 구매 품의 작성',
        '등록한 품의는 팀장·이사 결재로 전달됩니다.',
        _stack([
          DropdownButtonFormField<int>(
            initialValue: selectedVariantId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '제품 선택',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final row in inventoryRows)
                DropdownMenuItem(
                  value: row['product_variant_id'] as int,
                  child: Text(
                    '${row['product_name']} · ${row['color_name']} / ${row['size_mm']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => selectedVariantId = value),
          ),
          _field(
            '요청 수량 (켤레)',
            '수량',
            controller: requestQuantityController,
            numeric: true,
          ),
          _field('품의 제목', '구매 품의 제목', controller: requestTitleController),
          _field(
            '요청 사유',
            '재고 부족 사유',
            controller: requestReasonController,
            lines: 3,
          ),
          _action(
            '품의 상신',
            primary: true,
            onPressed: _createAndSubmitRequisition,
          ),
        ]),
      ),
      _panel(
        '재고 경고',
        '목표 재고의 30% 미만',
        _stack([
          for (final row in inventoryRows.where(
            (row) =>
                (row['target_quantity'] as num? ?? 0) > 0 &&
                (row['quantity'] as num? ?? 0) /
                        (row['target_quantity'] as num) <
                    .3,
          ))
            _orderCard(
              row['product_name'].toString(),
              '${row['color_name']} / ${row['size_mm']}',
              '현재 ${row['quantity']} / 목표 ${row['target_quantity']}',
              '재고 부족',
            ),
          if (inventoryRows.isEmpty) _empty('재고 데이터가 없습니다.'),
        ]),
      ),
    ),
    _panel(
      '최근 품의',
      '상신 후 결재 단계를 확인하세요.',
      requisitionData.isEmpty
          ? _empty('품의 내역이 없습니다.')
          : _table(
              const ['번호', '제목', '상태'],
              [
                for (final row in requisitionData)
                  [
                    '${row['id']}',
                    row['title'].toString(),
                    row['status'].toString(),
                  ],
              ],
            ),
    ),
  ]);

  Widget _approvals() {
    final team = widget.roleKey == 'teamLeader';
    final director = widget.roleKey == 'director';
    final executive = widget.roleKey == 'executive';
    final pendingStatus = team ? 'PENDING_TEAM_LEAD' : 'PENDING_DIRECTOR';
    final pending = executive
        ? <Map<String, dynamic>>[]
        : requisitionData
              .where((row) => row['status'] == pendingStatus)
              .toList();
    return _stack([
      _notice(
        executive
            ? '전체 품의의 결재 단계와 자동 발주 결과를 조회합니다.'
            : director
            ? '팀장 1차 승인 후 넘어온 품의를 최종 검토합니다.'
            : '사원이 상신한 구매 품의를 1차 검토합니다.',
      ),
      _flow(),
      _workState(),
      _panel(
        executive
            ? '결재 현황'
            : team
            ? '1차 결재 대기'
            : '최종 결재 대기',
        '담당 단계의 품의 내용을 확인하세요.',
        pending.isEmpty
            ? _empty(executive ? '임원 화면은 결재 현황 조회 전용입니다.' : '결재 대기 품의가 없습니다.')
            : _stack([
                for (final row in pending)
                  _panel(
                    '품의 #${row['id']} · ${row['title']}',
                    '${row['employeeName']} · 본사 재고 보충',
                    _stack([
                      Text(row['reason'].toString()),
                      for (final item in row['items'] as List<dynamic>)
                        Text(
                          '${item['productName']} · ${item['colorName']} / ${item['sizeMm']} · ${item['quantity']}켤레',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          _action(
                            '반려',
                            onPressed: () => _decideRequisition(
                              row['id'] as int,
                              'REJECTED',
                            ),
                          ),
                          _action(
                            '승인',
                            primary: true,
                            onPressed: () => _decideRequisition(
                              row['id'] as int,
                              'APPROVED',
                            ),
                          ),
                        ],
                      ),
                    ]),
                  ),
              ]),
      ),
      _panel(
        director ? '최종 검토 이력' : '전체 품의 현황',
        '최근 품의부터 표시합니다.',
        requisitionData.isEmpty
            ? _empty('품의 내역이 없습니다.')
            : _table(
                const ['번호', '제목', '상태'],
                [
                  for (final row in requisitionData)
                    [
                      '${row['id']}',
                      row['title'].toString(),
                      row['status'].toString(),
                    ],
                ],
              ),
      ),
    ]);
  }

  Widget _analytics() => _stack([
    _workState(),
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 170,
          child: _select(
            '기간',
            const ['최근 7일', '최근 14일', '최근 28일'],
            value: period,
            onChanged: (value) {
              setState(() => period = value);
              _loadWork();
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: _select(
            '제품',
            [
              '전체 제품',
              for (final product
                  in (analyticsData?['products'] as List<dynamic>? ?? []))
                product['name'] as String,
            ],
            value: selectedProduct,
            onChanged: (value) {
              setState(() => selectedProduct = value);
              _loadWork();
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: _select(
            '대리점',
            [
              '전체 대리점',
              for (final branch
                  in (analyticsData?['branches'] as List<dynamic>? ?? []))
                branch['name'] as String,
            ],
            value: selectedBranch,
            onChanged: (value) {
              setState(() => selectedBranch = value);
              _loadWork();
            },
          ),
        ),
      ],
    ),
    _metrics([
      ('판매량', '${analyticsData?['quantity'] ?? 0}켤레', '선택한 조건'),
      ('매출', '${analyticsData?['revenue'] ?? 0}원', '해당 주문 결제액'),
      ('주문', '${analyticsData?['orderCount'] ?? 0}건', '선택한 조건'),
      ('조회 지점', selectedBranch == '전체 대리점' ? '전체' : selectedBranch, '서울 자치구'),
    ]),
    _pair(
      _panel(
        '일자별 판매량',
        '주문 상품 수량',
        _MiniChart(
          (analyticsData?['byDay'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        ),
      ),
      _panel(
        '제품별 판매량',
        '켤레',
        _stack([
          for (final row
              in (analyticsData?['byProduct'] as List<dynamic>? ?? []))
            _BarRow(
              row['productName'] as String,
              '${row['quantity']}',
              analyticsData?['quantity'] == 0
                  ? 0
                  : ((row['quantity'] as num) /
                            (analyticsData!['quantity'] as num))
                        .clamp(0.0, 1.0)
                        .toDouble(),
            ),
          if ((analyticsData?['byProduct'] as List<dynamic>? ?? []).isEmpty)
            _empty('판매 데이터가 없습니다.'),
        ]),
      ),
    ),
  ]);

  Widget _liveCustomers() {
    final visible = customerData
        .where(
          (row) =>
              row['name'].toString().contains(query) ||
              '${row['id']}'.contains(query),
        )
        .toList();
    visible.sort((a, b) {
      final comparison = switch (customerSort) {
        '이름순 (가나다)' => a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        ),
        '누적 결제액 높은순' => _customerNumber(
          b['paidTotal'],
        ).compareTo(_customerNumber(a['paidTotal'])),
        '주문 횟수 많은순' => _customerNumber(
          b['orderCount'],
        ).compareTo(_customerNumber(a['orderCount'])),
        _ =>
          (DateTime.tryParse('${b['lastOrderedAt']}')?.millisecondsSinceEpoch ??
                  -1)
              .compareTo(
                DateTime.tryParse(
                      '${a['lastOrderedAt']}',
                    )?.millisecondsSinceEpoch ??
                    -1,
              ),
      };
      return comparison != 0
          ? comparison
          : _customerNumber(b['id']).compareTo(_customerNumber(a['id']));
    });
    final selectedInquiry = inquiryData
        .where((row) => row['id'] == selectedInquiryId)
        .firstOrNull;
    return _stack([
      _workState(),
      _metrics([
        ('전체 고객', '${customerData.length}명', '최근 조회 범위'),
        (
          '미답변 문의',
          '${inquiryData.where((row) => row['status'] != 'ANSWERED').length}건',
          '답변 필요',
        ),
      ]),
      _pair(
        _panel(
          '고객 목록',
          '고객을 선택하면 구매·반품 내역을 확인합니다.',
          _stack([
            LayoutBuilder(
              builder: (context, constraints) {
                final search = _field(
                  '고객명 또는 고객 ID',
                  '검색어',
                  onChanged: (value) => setState(() => query = value),
                );
                final sorting = KeyedSubtree(
                  key: const Key('customer-sort'),
                  child: _select(
                    '정렬 기준',
                    const ['최근 주문순', '이름순 (가나다)', '누적 결제액 높은순', '주문 횟수 많은순'],
                    value: customerSort,
                    onChanged: (value) => setState(() => customerSort = value),
                  ),
                );
                return constraints.maxWidth < 560
                    ? _stack([search, sorting])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 12),
                          Expanded(child: sorting),
                        ],
                      );
              },
            ),
            Text(
              '검색 결과 ${visible.length}명 · 최근 조회 최대 200명',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            if (visible.isEmpty) _empty('고객이 없습니다.'),
            for (final row in visible)
              KeyedSubtree(
                key: Key('customer-${row['id']}'),
                child: _choiceTile(
                  '${row['name']} · #${row['id']}',
                  '주문 ${row['orderCount'] ?? 0}회 · 누적 ${_customerAmount(row['paidTotal'])}원',
                  selectedCustomerId == row['id'],
                  () => _selectCustomer(row['id'] as int),
                ),
              ),
          ]),
        ),
        _panel(
          '고객 상세',
          '기본 정보와 구매·반품 기록',
          customerDetailLoading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : customerDetail == null
              ? _empty(
                  selectedCustomerId == null
                      ? '목록에서 고객을 선택해주세요.'
                      : '상세 정보를 불러오지 못했습니다. 고객을 다시 선택해주세요.',
                )
              : _customerDetails(),
        ),
      ),
      _panel(
        '고객 문의',
        '문의 내용을 확인하고 답변합니다.',
        _stack([
          if (inquiryData.isEmpty) _empty('문의가 없습니다.'),
          for (final item in inquiryData)
            _choiceTile(
              '${item['customerName']} · ${item['title']}',
              '${item['type']} · ${item['status']}',
              selectedInquiryId == item['id'],
              () => setState(() {
                selectedInquiryId = item['id'] as int;
                inquiryAnswerController.clear();
              }),
            ),
          if (selectedInquiry != null) ...[
            _detailRow('문의', selectedInquiry['body'].toString()),
            if (selectedInquiry['answer'] != null)
              _detailRow('최근 답변', selectedInquiry['answer'].toString()),
            _field(
              '답변',
              '고객에게 안내할 내용을 입력하세요',
              controller: inquiryAnswerController,
              lines: 3,
            ),
            _action(
              '답변 보내기',
              primary: true,
              onPressed: () => _answerInquiry(selectedInquiry['id'] as int),
            ),
          ],
        ]),
      ),
    ]);
  }

  num _customerNumber(dynamic value) => num.tryParse('$value') ?? 0;

  String _customerAmount(dynamic value) => _customerNumber(value)
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  String _customerDate(dynamic value) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? '기록 없음'
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  Widget _customerDetails() {
    final detail = customerDetail!;
    final summary = customerData
        .where((row) => row['id'] == detail['id'])
        .firstOrNull;
    final orders = detail['orders'] as List<dynamic>? ?? [];
    final returns = detail['returns'] as List<dynamic>? ?? [];
    Widget contact(IconData icon, String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _muted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(color: _ink, fontSize: 13),
          ),
        ),
      ],
    );
    Widget section(String title, int count) => Text(
      '$title · $count건',
      style: const TextStyle(
        color: _ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
    Widget record(String title, String status, List<String> lines) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _status(switch (status) {
                'REQUESTED' => '반품 접수',
                'APPROVED' => '반품 승인',
                'REJECTED' => '반품 반려',
                _ => _statusLabel(status),
              }),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
    return _stack([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFFEAF2FF),
            child: Icon(Icons.person_outline, color: _blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail['name'].toString(),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '고객 ID #${detail['id']}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      contact(Icons.mail_outline, detail['email']?.toString() ?? '이메일 미등록'),
      contact(
        Icons.phone_outlined,
        (detail['phone']?.toString().trim().isEmpty ?? true)
            ? '연락처 미등록'
            : detail['phone'].toString(),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: _stack([
          Text(
            '주문 ${summary?['orderCount'] ?? '—'}회 · 누적 결제 ${summary == null ? '—' : _customerAmount(summary['paidTotal'])}원',
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          Text(
            '최근 주문 ${_customerDate(summary?['lastOrderedAt'])}  /  적립금 ${summary == null ? '—' : _customerAmount(summary['pointBalance'])}P',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ]),
      ),
      const Divider(height: 1),
      section('구매 내역', orders.length),
      const Text('최근 최대 50건', style: TextStyle(color: _muted, fontSize: 11)),
      if (orders.isEmpty) _empty('구매 내역이 없습니다.'),
      for (final order in orders)
        record(order['number'].toString(), order['status'].toString(), [
          '${_customerDate(order['orderedAt'])} · ${order['branchName'] ?? '지점 미지정'}',
          '결제 금액 ${_customerAmount(order['paidTotal'])}원',
        ]),
      const Divider(height: 1),
      section('반품 내역', returns.length),
      const Text('최근 최대 50건', style: TextStyle(color: _muted, fontSize: 11)),
      if (returns.isEmpty) _empty('반품 내역이 없습니다.'),
      for (final item in returns)
        record('반품 #${item['id']}', item['status'].toString(), [
          '주문 ID #${item['orderId']}',
          item['reason']?.toString() ?? '사유 미등록',
        ]),
    ]);
  }

  Widget _customers() =>
      widget.roleKey == 'hqStaff' ? _liveCustomers() : _unavailable('고객 혜택 승인');

  Widget _stack(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 16),
        children[i],
      ],
    ],
  );

  Widget _panel(String title, String subtitle, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );

  Widget _metrics(List<(String, String, String)> items) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width <= 0) return const SizedBox.shrink();
      final columns = width >= 1100
          ? 4
          : width >= 480
          ? 2
          : 1;
      final cardWidth = (width - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (label, value, caption) in items)
            SizedBox(
              width: cardWidth,
              child: Container(
                constraints: const BoxConstraints(minHeight: 120),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      caption,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _notice(String text, {bool warning = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF5E5) : const Color(0xFFEAF3FF),
      border: Border.all(
        color: warning ? const Color(0xFFF4D9A9) : const Color(0xFFCFE2FF),
      ),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: warning ? const Color(0xFF885E20) : const Color(0xFF315C94),
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );

  Widget _field(
    String label,
    String hint, {
    ValueChanged<String>? onChanged,
    TextEditingController? controller,
    bool numeric = false,
    bool isDate = false,
    int lines = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF596A82),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: lines,
        keyboardType: numeric
            ? TextInputType.number
            : isDate
            ? TextInputType.datetime
            : lines > 1
            ? TextInputType.multiline
            : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _line),
          ),
        ),
      ),
    ],
  );

  Widget _select(
    String label,
    List<String> options, {
    String? value,
    ValueChanged<String>? onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF596A82),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: value ?? options.first,
        isExpanded: true,
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged?.call(next);
        },
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    ],
  );

  Widget _action(
    String label, {
    bool primary = false,
    IconData? icon,
    VoidCallback? onPressed,
  }) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon ?? Icons.arrow_forward, size: 16),
          label: Text(label),
          style: FilledButton.styleFrom(backgroundColor: _blue),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon ?? Icons.arrow_forward, size: 16),
          label: Text(label),
        );

  Widget _empty(String label) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
  );

  Widget _table(List<String> headers, List<List<String>> rows) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF3F7FC)),
          dataRowMinHeight: 48,
          columns: [
            for (final header in headers)
              DataColumn(
                label: Text(
                  header,
                  style: const TextStyle(
                    color: Color(0xFF51637C),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (final value in row)
                    DataCell(
                      Text(
                        value,
                        style: const TextStyle(color: _ink, fontSize: 12),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );

  Widget _status(String value) {
    final tone = value.contains('완료') || value.contains('정상')
        ? _green
        : value.contains('대기') || value.contains('24%')
        ? _red
        : _blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: tone,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _orderCard(
    String id,
    String product,
    String detail,
    String status, {
    String? action,
    VoidCallback? onAction,
    int? steps,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE2E9F2)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: _stack([
      Row(
        children: [
          Expanded(
            child: Text(
              id,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _status(status),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
      if (steps != null) _steps(steps),
      if (action != null)
        Align(
          alignment: Alignment.centerRight,
          child: _action(action, primary: true, onPressed: onAction),
        ),
    ]),
  );

  Widget _steps(int progress) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < 4; i++)
        Chip(
          label: Text(
            const ['구매 신청', '본사 발송', '대리점 도착', '고객 수령'][i],
            style: TextStyle(
              fontSize: 11,
              color: i <= progress ? _blue : _muted,
            ),
          ),
          backgroundColor: i <= progress
              ? const Color(0xFFE8F1FF)
              : const Color(0xFFF3F6FA),
        ),
    ],
  );

  Widget _choiceTile(
    String title,
    String detail,
    bool selected,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? const Color(0xFFEEF5FF) : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? const Color(0xFF9BC0F4) : _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          detail,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ),
    ),
  );
  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 820
        ? _stack([first, second])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: first),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: second),
            ],
          ),
  );

  Widget _flow() => _panel(
    '구매 품의 결재 흐름',
    '사원 상신부터 제조사 발주까지',
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        Chip(label: Text('사원 품의 작성')),
        Icon(Icons.arrow_forward, size: 16, color: _muted),
        Chip(label: Text('팀장 1차 승인')),
        Icon(Icons.arrow_forward, size: 16, color: _muted),
        Chip(label: Text('이사 최종 승인')),
        Icon(Icons.arrow_forward, size: 16, color: _muted),
        Chip(label: Text('발주 진행')),
      ],
    ),
  );
}

class _BarRow extends StatelessWidget {
  const _BarRow(this.label, this.value, this.ratio);
  final String label;
  final String value;
  final double ratio;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: const Color(0xFFE7EFF9),
            valueColor: const AlwaysStoppedAnimation(_blue),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _MiniChart extends StatelessWidget {
  const _MiniChart(this.days);

  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Text('판매 데이터가 없습니다.');
    final maximum = days
        .map((row) => (row['quantity'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth = days.length * 44.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth < minimumWidth
                ? minimumWidth
                : constraints.maxWidth,
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                height: maximum == 0
                                    ? 2
                                    : 135 *
                                          ((days[i]['quantity'] as num)
                                                  .toDouble() /
                                              maximum),
                                decoration: BoxDecoration(
                                  color: i == days.length - 1
                                      ? _blue
                                      : const Color(0xFF8BB6F3),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            (days[i]['day'] as String).substring(5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
