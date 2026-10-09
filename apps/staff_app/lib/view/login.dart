import 'package:flutter/material.dart';
import 'package:shupick_staff_mockup/auth/staff_session.dart';
import 'package:shupick_staff_mockup/view/staff_registration.dart';

class Login extends StatefulWidget {
  const Login({super.key, required this.onSignIn, this.initialError});

  final Future<void> Function(String email, String password) onSignIn;
  final String? initialError;

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool busy = false;
  bool hidePassword = true;
  String? error;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy) return;
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => error = '이메일과 비밀번호를 입력해주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSignIn(email, password);
    } on StaffAuthException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) setState(() => error = '로그인 중 문제가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 13,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3175EE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'S',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SHOEPICK',
                          style: TextStyle(
                            color: Color(0xFF12315E),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '직원 태블릿',
                          style: TextStyle(color: Color(0xFF5F7495)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFDCE5F0)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '직원 로그인',
                        style: TextStyle(
                          color: Color(0xFF14243E),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '등록된 직원 계정으로 로그인하면 소속 지점과 업무 권한을 불러옵니다.',
                        style: TextStyle(color: Color(0xFF6F7E93)),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        key: const Key('staff-email'),
                        controller: emailController,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '직원 이메일',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('staff-password'),
                        controller: passwordController,
                        enabled: !busy,
                        obscureText: hidePassword,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
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
                      if ((error ?? widget.initialError) != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          (error ?? widget.initialError)!,
                          style: const TextStyle(color: Color(0xFFB52638)),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('staff-sign-in'),
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('로그인'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('staff-register'),
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const StaffRegistrationPage(),
                                ),
                              ),
                        child: const Text('직원 등록'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        key: const Key('mock-quick-login'),
                        onPressed: busy
                            ? null
                            : () {
                                emailController.text = 'demo@example.com';
                                passwordController.text = 'mock1234';
                                _submit();
                              },
                        child: const Text('목업 바로 보기'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
