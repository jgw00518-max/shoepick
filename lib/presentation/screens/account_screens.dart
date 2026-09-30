import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../store_shell.dart';
import '../shared/store_widgets.dart';

/// 비회원은 홈을 둘러보고 마이페이지에서 로그인할 수 있습니다.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.onGo,
    required this.onLogout,
  });
  final StoreController store;
  final void Function(StorePage) onGo;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (!store.isLoggedIn) ...[
        const SectionTitle('마이페이지'),
        const LText('비회원으로 상품을 둘러보고 있어요.'),
        const SizedBox(height: 20),
        const SectionTitle('로그인하고 쇼핑을 이어가세요'),
        const LText('주문 내역과 쿠폰, 적립금을 한곳에서 확인할 수 있어요.'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => onGo(StorePage.auth),
          child: const LText('로그인 / 회원가입'),
        ),
      ] else ...[
        const SectionTitle('서준 님'),
        const LText('PLATINUM MEMBER · 다음 VIP까지 128,000원'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                LText(
                  'SJ',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
                LText('VIP 등급 78%'),
                LText('PLATINUM'),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => onGo(StorePage.coupons),
                child: const LText('쿠폰 4장'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => onGo(StorePage.points),
                child: const LText('적립금 32,500P'),
              ),
            ),
            const Expanded(
              child: TextButton(onPressed: null, child: LText('리뷰 12개')),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const LText('로그아웃'),
                  content: const LText('현재 계정에서 로그아웃하시겠어요?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const LText('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const LText('로그아웃'),
                    ),
                  ],
                ),
              );
              if (yes == true) onLogout();
            },
            child: const LText('로그아웃'),
          ),
        ),
      ],
      const Divider(height: 40),
      for (final item in [
        (
          '주문 내역',
          StorePage.orders,
          Icons.receipt_long_outlined,
          '배송, 교환, 반품 상태 확인',
        ),
        ('문의 사항', StorePage.inquiry, Icons.help_outline, '문의 내역과 답변 확인'),
        (
          '쿠폰과 적립금',
          StorePage.coupons,
          Icons.confirmation_num_outlined,
          '사용 가능한 혜택 모아보기',
        ),
        ('설정', StorePage.settings, Icons.settings_outlined, '테마, 언어, 알림 설정'),
      ].where((item) => store.isLoggedIn || item.$2 == StorePage.settings))
        ListTile(
          leading: Icon(item.$3),
          title: LText(item.$1),
          subtitle: LText(item.$4),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onGo(item.$2),
        ),
    ],
  );
}

/// 이메일 인증만 동작하는 목업 화면입니다.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.store,
    required this.onBack,
    required this.onDone,
    required this.onMessage,
  });
  final StoreController store;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final void Function(String) onMessage;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  String mode = 'login';
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  void change(String value) {
    formKey.currentState?.reset();
    password.clear();
    confirm.clear();
    setState(() => mode = value);
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (mode == 'login') {
        final ok = await widget.store.signIn(email.text.trim(), password.text);
        if (!ok) {
          widget.onMessage('이메일 또는 비밀번호가 올바르지 않습니다.');
          return;
        }
        widget.onDone();
      } else if (mode == 'signupEmail') {
        await widget.store.signUp(email.text.trim(), password.text);
        widget.onMessage('회원가입이 완료되었습니다. 입력한 계정으로 로그인해주세요.');
        change('login');
      } else {
        widget.onMessage('비밀번호 재설정 안내를 이메일로 보냈습니다.');
      }
    } on StateError catch (error) {
      widget.onMessage(error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (mode == 'login') {
              widget.onBack();
            } else if (mode == 'signupEmail') {
              change('signup');
            } else {
              change('login');
            }
          },
        ),
      ),
      const SizedBox(height: 24),
      const LText(
        'SOLE / SELECT',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 8),
      LText(switch (mode) {
        'signup' => '가입 방법 선택',
        'signupEmail' => '이메일로 가입',
        'reset' => '비밀번호 재설정',
        _ => '로그인',
      }, style: const TextStyle(fontSize: 22)),
      const SizedBox(height: 30),
      if (mode == 'signup') ...[
        for (final method in ['카카오', '네이버', 'Google'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () => widget.onMessage('$method 가입은 준비 중입니다.'),
              child: LText('$method로 가입 · 준비 중'),
            ),
          ),
        OutlinedButton(
          onPressed: () => change('signupEmail'),
          child: const LText('이메일로 가입'),
        ),
      ] else
        Form(
          key: formKey,
          child: Column(
            children: [
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(value?.trim() ?? '')
                    ? null
                    : '올바른 이메일 주소를 입력해주세요.',
              ),
              if (mode != 'reset') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value != null &&
                          value.length >= 8 &&
                          RegExp('[A-Za-z]').hasMatch(value) &&
                          RegExp('[0-9]').hasMatch(value)
                      ? null
                      : '영문과 숫자를 포함해 8자 이상 입력해주세요.',
                ),
              ],
              if (mode == 'signupEmail') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '비밀번호 확인',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == password.text ? null : '비밀번호가 일치하지 않습니다.',
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  child: LText(switch (mode) {
                    'signupEmail' => '가입하기',
                    'reset' => '재설정 안내',
                    _ => '로그인',
                  }),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (mode == 'login') ...[
        TextButton(
          onPressed: () => change('signup'),
          child: const LText('회원가입'),
        ),
        TextButton(
          onPressed: () => change('reset'),
          child: const LText('비밀번호를 잊으셨나요?'),
        ),
        const LText(
          '데모 계정: user@sole.kr / sole1234',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 32),
        const LText('간편 로그인', textAlign: TextAlign.center),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            IconButton(
              onPressed: null,
              tooltip: '카카오 로그인 준비 중',
              icon: LText('K'),
            ),
            IconButton(
              onPressed: null,
              tooltip: '네이버 로그인 준비 중',
              icon: LText('N'),
            ),
            IconButton(
              onPressed: null,
              tooltip: '구글 로그인 준비 중',
              icon: LText('G'),
            ),
          ],
        ),
      ] else
        TextButton(
          onPressed: () => change('login'),
          child: const LText('로그인으로 돌아가기'),
        ),
    ],
  );
}

class InfoScreen extends StatelessWidget {
  const InfoScreen({
    super.key,
    required this.title,
    required this.description,
    this.action,
    this.onAction,
  });
  final String title;
  final String description;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) =>
      EmptyState(description, action: action, onAction: onAction);
}
