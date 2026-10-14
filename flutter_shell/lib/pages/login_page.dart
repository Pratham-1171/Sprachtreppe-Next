import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';

enum _AuthTab { student, admin }
enum _StudentMode { signIn, create }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService, required this.onSignedIn});
  final AuthService authService;
  final ValueChanged<AppUser> onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  _AuthTab _tab = _AuthTab.student;
  _StudentMode _studentMode = _StudentMode.signIn;
  bool _codeSent = false;
  bool _loading = false;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  bool get _creatingStudent => _tab == _AuthTab.student && _studentMode == _StudentMode.create;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await widget.authService.sendCode(
        email: _emailController.text,
        allowNewStudent: _creatingStudent,
      );
      if (!mounted) return;
      setState(() => _codeSent = true);
      _showMessage('A 6-digit code was sent to ${_emailController.text.trim()}.');
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, error: true);
    } catch (_) {
      if (mounted) _showMessage('Could not send the code. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showMessage('Enter the 6-digit code from your email.', error: true);
      return;
    }
    if (_creatingStudent && _nameController.text.trim().isEmpty) {
      _showMessage('Enter your full name.', error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      if (_creatingStudent) {
        await widget.authService.verifyOtpOnly(
          email: _emailController.text,
          code: code,
        );
        await widget.authService.completeStudentRegistration(
          fullName: _nameController.text,
        );
        await widget.authService.signOut();
        if (mounted) {
          setState(() {
            _codeSent = false;
            _codeController.clear();
            _studentMode = _StudentMode.signIn;
          });
          _showMessage('Account created. An administrator must approve it before you can sign in.');
        }
      } else {
        final user = await widget.authService.verifyCode(
          email: _emailController.text,
          code: code,
        );
        if (mounted) widget.onSignedIn(user);
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, error: true);
      try {
        await widget.authService.signOut();
      } catch (_) {}
    } catch (error) {
      if (mounted) _showMessage('Could not complete this request. Please try again.', error: true);
      try {
        await widget.authService.signOut();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchTab(_AuthTab tab) {
    setState(() {
      _tab = tab;
      _codeSent = false;
      _codeController.clear();
      if (tab == _AuthTab.admin) _studentMode = _StudentMode.signIn;
    });
  }

  void _switchStudentMode(_StudentMode mode) {
    setState(() {
      _studentMode = mode;
      _codeSent = false;
      _codeController.clear();
    });
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _tab == _AuthTab.admin
        ? 'Admin / teacher access'
        : _creatingStudent
            ? 'Create student account'
            : 'Student sign in';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.auto_stories_rounded, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 18),
                  Text('Sprachtreppe', textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('German A1–B1', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 28),
                  SegmentedButton<_AuthTab>(
                    segments: const [
                      ButtonSegment(value: _AuthTab.student, label: Text('Student'), icon: Icon(Icons.school_outlined)),
                      ButtonSegment(value: _AuthTab.admin, label: Text('Admin'), icon: Icon(Icons.admin_panel_settings_outlined)),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (value) => _switchTab(value.first),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == _AuthTab.student)
                    SegmentedButton<_StudentMode>(
                      segments: const [
                        ButtonSegment(value: _StudentMode.signIn, label: Text('Sign in')),
                        ButtonSegment(value: _StudentMode.create, label: Text('Create account')),
                      ],
                      selected: {_studentMode},
                      onSelectionChanged: (value) => _switchStudentMode(value.first),
                    ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(title, style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(
                              _tab == _AuthTab.admin
                                  ? 'Teachers and administrators sign in with their registered email. Only an approved account can enter this area.'
                                  : _creatingStudent
                                      ? 'Students can create their own account. It starts as pending until an administrator approves it.'
                                      : 'Enter your registered email. We will send a one-time 6-digit login code.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                            if (_creatingStudent) ...[
                              TextFormField(
                                controller: _nameController,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) => _creatingStudent && (value?.trim().isEmpty ?? true)
                                    ? 'Enter your full name'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              enabled: !_codeSent,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                return email.isEmpty || !email.contains('@') ? 'Enter a valid email address' : null;
                              },
                            ),
                            if (_codeSent) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _codeController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                maxLength: 6,
                                onFieldSubmitted: (_) => _verify(),
                                decoration: const InputDecoration(
                                  labelText: '6-digit code',
                                  prefixIcon: Icon(Icons.password_outlined),
                                  counterText: '',
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: _loading ? null : (_codeSent ? _verify : _sendCode),
                                child: _loading
                                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(_codeSent ? 'Verify code' : 'Send code'),
                              ),
                            ),
                            if (_codeSent) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => setState(() {
                                        _codeSent = false;
                                        _codeController.clear();
                                      }),
                                child: const Text('Use a different email'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _tab == _AuthTab.admin
                        ? 'Teachers are promoted by an administrator after their student account is created.'
                        : 'No passwords are stored or required. Login uses a one-time email code.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
