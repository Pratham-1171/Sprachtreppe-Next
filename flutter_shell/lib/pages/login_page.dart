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
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool get _creatingStudent => _tab == _AuthTab.student && _studentMode == _StudentMode.create;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_creatingStudent) {
        await widget.authService.createStudentAccount(
          fullName: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!mounted) return;
        _passwordController.clear();
        _confirmPasswordController.clear();
        setState(() => _studentMode = _StudentMode.signIn);
        _showMessage('Account created. An administrator must approve it before you can sign in.');
      } else {
        final user = await widget.authService.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (mounted) widget.onSignedIn(user);
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, error: true);
    } catch (_) {
      if (mounted) _showMessage('Could not complete this request. Please check your details and try again.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchTab(_AuthTab tab) {
    setState(() {
      _tab = tab;
      _studentMode = _StudentMode.signIn;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  void _switchStudentMode(_StudentMode mode) {
    setState(() {
      _studentMode = mode;
      _passwordController.clear();
      _confirmPasswordController.clear();
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

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Use at least 8 characters';
    return null;
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
                  Text(
                    'Sprachtreppe',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
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
                                  ? 'Approved teachers and administrators sign in with their registered email and password.'
                                  : _creatingStudent
                                      ? 'Create a student account with your email and a password. Your account starts as pending until an administrator approves it.'
                                      : 'Sign in with your registered email and password.',
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
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: _creatingStudent ? TextInputAction.next : TextInputAction.done,
                              autofillHints: _creatingStudent
                                  ? const [AutofillHints.newPassword]
                                  : const [AutofillHints.password],
                              onFieldSubmitted: _creatingStudent ? null : (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: _validatePassword,
                            ),
                            if (_creatingStudent) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.newPassword],
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                                  suffixIcon: IconButton(
                                    tooltip: _obscureConfirmPassword ? 'Show password' : 'Hide password',
                                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                ),
                                validator: (value) {
                                  if (value != _passwordController.text) return 'Passwords do not match';
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(_creatingStudent ? 'Create account' : 'Login'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _tab == _AuthTab.admin
                        ? 'Password recovery is not available. Contact the system administrator if access needs to be changed.'
                        : _creatingStudent
                            ? 'Use a strong password and keep it safe. An administrator must approve your account before login.'
                            : 'Password recovery is not available in Sprachtreppe.',
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
