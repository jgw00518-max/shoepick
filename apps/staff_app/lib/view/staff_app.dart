import 'package:flutter/material.dart';
import 'package:shupick_staff_mockup/model/staff_role.dart';
import 'package:shupick_staff_mockup/model/staff_session.dart';
import 'package:shupick_staff_mockup/view/dashboard_page.dart';
import 'package:shupick_staff_mockup/view/login.dart';
import 'package:shupick_staff_mockup/vm/staff_session.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.authRepository});

  final StaffAuthRepository? authRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StaffAuthRepository authRepository;
  StaffProfile? profile;
  int? selectedBranchId;
  bool loading = true;
  String? initialError;

  @override
  void initState() {
    super.initState();
    authRepository = widget.authRepository ?? MockStaffAuthRepository();
    _restoreSession();
  }

  List<StaffRole> _rolesFor(StaffProfile staff) => [
    for (final role in staff.roles)
      if (StaffRole.fromCode(role.code) case final StaffRole mapped)
        if (!mapped.isBranch || staff.branches.isNotEmpty) mapped,
  ];

  void _validateProfile(StaffProfile staff) {
    if (_rolesFor(staff).isEmpty) {
      throw const StaffAuthException('사용 가능한 직책 또는 소속 지점이 없습니다. 관리자에게 문의해주세요.');
    }
  }

  Future<void> _restoreSession() async {
    try {
      final restored = await authRepository.restoreSession();
      if (restored != null) _validateProfile(restored);
      if (!mounted) return;
      setState(() {
        profile = restored;
        selectedBranchId = restored?.branches.firstOrNull?.id;
        initialError = null;
        loading = false;
      });
    } on StaffAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        initialError = error.message;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        initialError = '직원 로그인 상태를 확인하지 못했습니다.';
        loading = false;
      });
    }
  }

  Future<void> _signIn(String email, String password) async {
    final signedIn = await authRepository.signIn(email, password);
    try {
      _validateProfile(signedIn);
    } on StaffAuthException {
      await authRepository.signOut();
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      profile = signedIn;
      selectedBranchId = signedIn.branches.firstOrNull?.id;
      initialError = null;
    });
  }

  Future<void> _signOut() async {
    await authRepository.signOut();
    if (!mounted) return;
    setState(() {
      profile = null;
      selectedBranchId = null;
      initialError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final staff = profile;
    final branches = staff?.branches ?? const <StaffBranch>[];
    final branch = branches
        .where((item) => item.id == selectedBranchId)
        .firstOrNull;
    final allowedRoles = staff == null ? <StaffRole>[] : _rolesFor(staff);
    return MaterialApp(
      title: 'SHOEPICK | UI 목업',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Column(
        children: [
          Material(
            color: const Color(0xFFEAF2FF),
            child: SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'UI 목업 · 가상 데이터 · 실제 계정/업무에 반영되지 않습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563C6),
          surface: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : staff == null
          ? Login(onSignIn: _signIn, initialError: initialError)
          : DashboardPage(
              key: ValueKey(staff.id),
              initialRole: allowedRoles.first,
              availableRoles: allowedRoles,
              employeeName: staff.name,
              branch: branch?.name ?? '본사',
              selectedBranchId: selectedBranchId,
              availableBranches: {
                for (final item in branches) item.id: item.name,
              },
              onSelectBranch: (id) => setState(() => selectedBranchId = id),
              onSignOut: _signOut,
            ),
    );
  }
}
