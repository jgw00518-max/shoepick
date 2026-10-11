import 'package:flutter/material.dart';
import 'dispatch_view.dart';
import 'package:shoepick_staff_app/model/staff_role.dart';
import 'package:shoepick_staff_app/model/staff_views.dart';
import 'package:shoepick_staff_app/view/staff_overview.dart';
import 'package:shoepick_staff_app/view/staff_pages.dart';
import 'package:shoepick_staff_app/vm/staff_order_api.dart';
import 'package:shoepick_staff_app/vm/staff_work_api.dart';
import 'manufacturer_view.dart';
import 'staff_product_view.dart';
import 'staff_payments_view.dart';

const _navy = Color(0xFF19324F);
const _blue = Color(0xFF2563C6);
const _ink = Color(0xFF1B2B40);
const _muted = Color(0xFF66768B);
const _line = Color(0xFFE2E8F0);
const _canvas = Color(0xFFF5F7FA);

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.initialRole,
    required this.availableRoles,
    required this.employeeName,
    required this.branch,
    required this.selectedBranchId,
    required this.availableBranches,
    required this.onSelectBranch,
    required this.onSignOut,
    this.orderRepository,
    this.workApi,
    this.dispatchRequest,
  });

  final StaffRole initialRole;
  final List<StaffRole> availableRoles;
  final String employeeName;
  final String branch;
  final int? selectedBranchId;
  final Map<int, String> availableBranches;
  final ValueChanged<int> onSelectBranch;
  final VoidCallback onSignOut;
  final StaffOrderRepository? orderRepository;
  final StaffWorkApi? workApi;
  final Future<Map<String, dynamic>> Function(String)? dispatchRequest;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late StaffRole role;
  StaffView selectedView = StaffView.overview;
  final ScrollController _contentScrollController = ScrollController();

  void _selectView(StaffView view) {
    if (selectedView == view) return;
    setState(() => selectedView = view);
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  void _selectRole(StaffRole value) {
    setState(() {
      role = value;
      selectedView = StaffView.overview;
    });
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    role = widget.initialRole;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < 700;
      final wide = constraints.maxWidth >= 1200;
      final short = constraints.maxHeight < 500;
      final navigation = _Sidebar(
        role: role,
        employeeName: widget.employeeName,
        branch: widget.branch,
        selectedView: selectedView,
        onSelect: _selectView,
        onSignOut: widget.onSignOut,
        inDrawer: mobile,
      );
      return Scaffold(
        backgroundColor: _canvas,
        drawer: mobile ? Drawer(width: 280, child: navigation) : null,
        body: SafeArea(
          child: Column(
            children: [
              _workspaceBar(mobile),
              if (!mobile && !wide)
                _TabletNavigation(
                  role: role,
                  selectedView: selectedView,
                  onSelect: _selectView,
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide) SizedBox(width: 220, child: navigation),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('workspace-scroll'),
                        controller: _contentScrollController,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                mobile ? 16 : 24,
                                short ? 16 : 24,
                                mobile ? 16 : 24,
                                32,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _pageHeading(mobile),
                                  const SizedBox(height: 20),
                                  if (selectedView == StaffView.overview)
                                    StaffOverview(
                                      key: ValueKey(
                                        '${role.name}-overview-${widget.selectedBranchId}',
                                      ),
                                      roleKey: role.name,
                                      selectedBranchId: widget.selectedBranchId,
                                      orderRepository: widget.orderRepository,
                                      workApi: widget.workApi,
                                      onOpenView: _selectView,
                                    )
                                  else if (
                                    selectedView == StaffView.manufacturers)
                                    const ManufacturerView()
                                  else if (selectedView == StaffView.products)
                                    const StaffProductView()
                                  else if (selectedView == StaffView.payments)
                                    const StaffPaymentsView()
                                  else if (selectedView == StaffView.shipping &&
                                      widget.dispatchRequest != null)
                                    DispatchView(
                                      key: ValueKey(
                                        '${role.name}-dispatch-${widget.selectedBranchId}',
                                      ),
                                      request: widget.dispatchRequest!,
                                      branchId: role.isBranch
                                          ? widget.selectedBranchId
                                          : null,
                                    )
                                  else
                                    StaffPage(
                                      key: ValueKey(
                                        '${role.name}-${selectedView.name}-${widget.selectedBranchId}',
                                      ),
                                      view: selectedView,
                                      roleKey: role.name,
                                      isBranch: role.isBranch,
                                      selectedBranchId: widget.selectedBranchId,
                                      orderRepository: widget.orderRepository,
                                      workApi: widget.workApi,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _workspaceBar(bool compact) {
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<StaffRole>(
          key: const Key('role-selector'),
          tooltip: '직책 선택',
          onSelected: _selectRole,
          itemBuilder: (context) => widget.availableRoles
              .map(
                (value) =>
                    PopupMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          child: _ChipLabel(
            label: role.label,
            highlighted: true,
            dropdown: true,
          ),
        ),
        if (role.isBranch && widget.availableBranches.isNotEmpty)
          widget.availableBranches.length == 1
              ? _ChipLabel(label: widget.branch)
              : PopupMenuButton<int>(
                  key: const Key('branch-selector'),
                  tooltip: '소속 지점 선택',
                  onSelected: widget.onSelectBranch,
                  itemBuilder: (context) => widget.availableBranches.entries
                      .map(
                        (entry) => PopupMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  child: _ChipLabel(label: widget.branch, dropdown: true),
                ),
        IconButton.outlined(
          onPressed: widget.onSignOut,
          tooltip: '로그아웃',
          icon: const Icon(Icons.logout_rounded, size: 19),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 32,
          vertical: 14,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;
            final identity = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (compact) ...[
                  Builder(
                    builder: (context) => IconButton(
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                      tooltip: '업무 메뉴',
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.grid_view_rounded, size: 20, color: _blue),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${widget.employeeName}님의 업무 공간',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [identity, const SizedBox(height: 10), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actions,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pageHeading(bool compact) {
    final now = DateTime.now();
    final date =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final heading = selectedView == StaffView.overview && role.isBranch
        ? (role == StaffRole.branchManager ? '지점 운영 대시보드' : '대리점 업무 대시보드')
        : viewTitle(selectedView, isBranch: role.isBranch, role: role.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${role.isBranch ? widget.branch : '본사'}  /  $date',
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          heading,
          style: TextStyle(
            color: _ink,
            fontSize: compact ? 27 : 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          viewDescription(
            selectedView,
            isBranch: role.isBranch,
            role: role.name,
          ),
          style: const TextStyle(color: _muted, fontSize: 14, height: 1.45),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.role,
    required this.employeeName,
    required this.branch,
    required this.selectedView,
    required this.onSelect,
    required this.onSignOut,
    this.inDrawer = false,
  });

  final StaffRole role;
  final String employeeName;
  final String branch;
  final StaffView selectedView;
  final ValueChanged<StaffView> onSelect;
  final VoidCallback onSignOut;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: _line)),
    ),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'SHOEPICK',
          style: TextStyle(
            color: _navy,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$employeeName · ${role.label}',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const Divider(height: 32),
        for (final menu in menusForRole(role.name))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _NavigationItem(
              menu: menu,
              selected: menu.view == selectedView,
              onTap: () {
                onSelect(menu.view);
                if (inDrawer) Navigator.of(context).pop();
              },
            ),
          ),
        const Divider(height: 32),
        TextButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('로그아웃'),
        ),
      ],
    ),
  );
}

class _TabletNavigation extends StatelessWidget {
  const _TabletNavigation({
    required this.role,
    required this.selectedView,
    required this.onSelect,
  });
  final StaffRole role;
  final StaffView selectedView;
  final ValueChanged<StaffView> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (final menu in menusForRole(role.name))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _NavigationItem(
                menu: menu,
                selected: menu.view == selectedView,
                onTap: () => onSelect(menu.view),
                horizontal: true,
              ),
            ),
        ],
      ),
    ),
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.menu,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });

  final StaffMenu menu;
  final bool selected;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      key: Key('menu-${menu.view.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(menu.icon, size: 20, color: selected ? _blue : _muted),
            const SizedBox(width: 10),
            if (horizontal)
              Text(menu.label, style: _labelStyle)
            else
              Expanded(child: Text(menu.label, style: _labelStyle)),
          ],
        ),
      ),
    ),
  );

  TextStyle get _labelStyle => TextStyle(
    color: selected ? _blue : _ink,
    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
    fontSize: 13,
  );
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({
    required this.label,
    this.highlighted = false,
    this.dropdown = false,
  });
  final String label;
  final bool highlighted;
  final bool dropdown;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFEAF2FF) : Colors.white,
        border: Border.all(
          color: highlighted ? const Color(0xFFC7DAF6) : _line,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted ? _blue : _muted,
                fontSize: 12,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (dropdown) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 16,
              color: highlighted ? _blue : _muted,
            ),
          ],
        ],
      ),
    ),
  );
}
