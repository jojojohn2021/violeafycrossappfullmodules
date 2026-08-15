import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../providers/app_providers.dart';

class OtpLoginScreen extends ConsumerStatefulWidget {
  final String redirectTo;

  const OtpLoginScreen({super.key, this.redirectTo = '/'});

  @override
  ConsumerState<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends ConsumerState<OtpLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill phone if it was already entered (state preservation across redirects)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(otpLoginProvider);
      if (state.phone.isNotEmpty) {
        _phoneController.text = state.phone;
      }
    });

    // Listen to auth state to navigate when signed in
    ref.listenManual(otpLoginProvider, (previous, next) {
      // Handle success navigation via global auth state or local success flag
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _verifyPhone() async {
    final phone = _phoneController.text.trim();
    final notifier = ref.read(otpLoginProvider.notifier);
    await notifier.sendOtp(phone);

    if (mounted) {
      final state = ref.read(otpLoginProvider);
      if (state.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
      } else if (state.codeSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP code sent successfully!')),
        );
      }
    }
  }

  void _signInWithOTP() async {
    final otp = _otpController.text.trim();
    final notifier = ref.read(otpLoginProvider.notifier);
    final success = await notifier.verifyOtp(otp);

    if (mounted) {
      final state = ref.read(otpLoginProvider);
      if (success) {
        context.go(widget.redirectTo);
      } else if (state.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(otpLoginProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (otpState.isLoading)
            TextButton(
              onPressed: () => ref.read(otpLoginProvider.notifier).reset(),
              child: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/Logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Leafy',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in with your mobile number to start shopping fresh fruits & vegetables.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 32),

              if (!otpState.codeSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixText: '+91 ',
                    prefixIcon: Icon(Icons.phone_android, color: AppColors.primaryGreen),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: otpState.isLoading ? null : _verifyPhone,
                    child: otpState.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('SEND OTP'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Enter 6-Digit OTP',
                    prefixIcon: Icon(Icons.lock_clock_outlined, color: AppColors.primaryGreen),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: otpState.isLoading ? null : _signInWithOTP,
                    child: otpState.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('VERIFY & CONTINUE'),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => ref.read(otpLoginProvider.notifier).reset(),
                    child: const Text('Change Phone Number'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
