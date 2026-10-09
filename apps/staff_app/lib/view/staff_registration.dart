import 'package:flutter/material.dart';
import 'package:shupick_staff_mockup/model/staff_session.dart';
import 'package:shupick_staff_mockup/vm/staff_registration_service.dart';

class StaffRegistrationPage extends StatefulWidget {
  const StaffRegistrationPage({super.key, this.repository});

  final StaffRegistrationRepository? repository;

  @override
  State<StaffRegistrationPage> createState() => _StaffRegistrationPageState();
}

class _StaffRegistrationPageState extends State<StaffRegistrationPage> {
  static const _districtCodes = {
    '강남구': 'SEOUL-GANGNAM',
    '강동구': 'SEOUL-GANGDONG',
    '강북구': 'SEOUL-GANGBUK',
    '강서구': 'SEOUL-GANGSEO',
    '관악구': 'SEOUL-GWANAK',
    '광진구': 'SEOUL-GWANGJIN',
    '구로구': 'SEOUL-GURO',
    '금천구': 'SEOUL-GEUMCHEON',
    '노원구': 'SEOUL-NOWON',
    '도봉구': 'SEOUL-DOBONG',
    '동대문구': 'SEOUL-DONGDAEMUN',
    '동작구': 'SEOUL-DONGJAK',
    '마포구': 'SEOUL-MAPO',
    '서대문구': 'SEOUL-SEODAEMUN',
    '서초구': 'SEOUL-SEOCHO',
    '성동구': 'SEOUL-SEONGDONG',
    '성북구': 'SEOUL-SEONGBUK',
    '송파구': 'SEOUL-SONGPA',
    '양천구': 'SEOUL-YANGCHEON',
    '영등포구': 'SEOUL-YEONGDEUNGPO',
    '용산구': 'SEOUL-YONGSAN',
    '은평구': 'SEOUL-EUNPYEONG',
    '종로구': 'SEOUL-JONGNO',
    '중구': 'SEOUL-JUNG',
    '중랑구': 'SEOUL-JUNGNANG',
  };
  static const _branchRoles = ['대리점 직원', '대리점장'];
  static const _headOfficeRoles = ['본사 사원', '본사 팀장', '본사 이사', '본사 임원'];
  static const _roleCodes = {
    '대리점 직원': 'BRANCH_STAFF',
    '대리점장': 'BRANCH_MANAGER',
    '본사 사원': 'HQ_STAFF',
    '본사 팀장': 'TEAM_LEAD',
    '본사 이사': 'DIRECTOR',
    '본사 임원': 'EXECUTIVE',
  };

  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final nameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  late final StaffRegistrationRepository repository;

  String affiliation = '대리점';
  String? district;
  String? role;
  bool hidePassword = true;
  bool hideConfirmation = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? MockStaffRegistrationRepository();
  }

  @override
  void dispose() {
    emailController.dispose();
    nameController.dispose();
    passwordController.dispose();
    confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !_formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repository.register(
        email: emailController.text.trim(),
        password: passwordController.text,
        name: nameController.text.trim(),
        affiliation: affiliation == '대리점' ? 'BRANCH' : 'HQ',
        districtCode: affiliation == '대리점' ? _districtCodes[district] : null,
        roleCode: _roleCodes[role]!,
      );
      passwordController.clear();
      confirmationController.clear();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('직원 등록 완료'),
          content: const Text('직원 계정이 등록되었습니다. 바로 로그인할 수 있습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on StaffAuthException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) setState(() => error = '직원 등록 중 문제가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('직원 등록')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFDCE5F0)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '직원 정보 입력',
                      style: TextStyle(
                        color: Color(0xFF14243E),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '계정에 사용할 정보와 소속을 입력해주세요.',
                      style: TextStyle(color: Color(0xFF6F7E93)),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('registration-email'),
                      controller: emailController,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (value) =>
                          RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : '올바른 이메일을 입력해주세요.',
                      decoration: const InputDecoration(
                        labelText: '이메일',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('registration-name'),
                      controller: nameController,
                      enabled: !busy,
                      textInputAction: TextInputAction.next,
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? '이름을 입력해주세요.'
                          : null,
                      decoration: const InputDecoration(
                        labelText: '이름',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('registration-password'),
                      controller: passwordController,
                      enabled: !busy,
                      obscureText: hidePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      validator: (value) => (value?.length ?? 0) < 6
                          ? '비밀번호는 6자 이상 입력해주세요.'
                          : null,
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: hidePassword ? '비밀번호 표시' : '비밀번호 숨기기',
                          onPressed: () =>
                              setState(() => hidePassword = !hidePassword),
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('registration-password-confirmation'),
                      controller: confirmationController,
                      enabled: !busy,
                      obscureText: hideConfirmation,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      validator: (value) => value != passwordController.text
                          ? '비밀번호가 일치하지 않습니다.'
                          : null,
                      decoration: InputDecoration(
                        labelText: '비밀번호 확인',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: hideConfirmation ? '비밀번호 표시' : '비밀번호 숨기기',
                          onPressed: () => setState(
                            () => hideConfirmation = !hideConfirmation,
                          ),
                          icon: Icon(
                            hideConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: const Key('registration-affiliation'),
                            initialValue: affiliation,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '소속 구분',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '대리점',
                                child: Text('대리점'),
                              ),
                              DropdownMenuItem(value: '본사', child: Text('본사')),
                            ],
                            onChanged: busy
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        affiliation = value;
                                        district = null;
                                        role = null;
                                      });
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'registration-affiliation-detail-$affiliation',
                            ),
                            initialValue: district,
                            isExpanded: true,
                            hint: Text(
                              affiliation == '본사' ? '본사는 지점 없음' : '자치구 선택',
                            ),
                            decoration: const InputDecoration(
                              labelText: '소속 지점',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                affiliation == '대리점' && value == null
                                ? '지점을 선택해주세요.'
                                : null,
                            items: _districtCodes.keys
                                .map(
                                  (name) => DropdownMenuItem(
                                    value: name,
                                    child: Text(name),
                                  ),
                                )
                                .toList(),
                            onChanged: busy || affiliation == '본사'
                                ? null
                                : (value) => setState(() => district = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('registration-role-$affiliation'),
                      initialValue: role,
                      isExpanded: true,
                      hint: const Text('직책 선택'),
                      decoration: const InputDecoration(
                        labelText: '직책',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          (affiliation == '대리점'
                                  ? _branchRoles
                                  : _headOfficeRoles)
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                      validator: (value) =>
                          value == null ? '직책을 선택해주세요.' : null,
                      onChanged: busy
                          ? null
                          : (value) => setState(() => role = value),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFB52638)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('registration-submit'),
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('직원 등록'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '등록을 완료하면 바로 로그인할 수 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF6F7E93)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
