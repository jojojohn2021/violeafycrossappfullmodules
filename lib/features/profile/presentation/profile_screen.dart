import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/app_providers.dart';
import '../../../core/services/storage_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isUploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      final storageService = FirebaseStorageService();
      final downloadUrl = await storageService.uploadBytes(
        fileBytes: bytes,
        storageFolder: 'users/${user.uid}',
        fileName: 'avatar.jpg',
      );

      await user.updatePhotoURL(downloadUrl);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to upload avatar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final walletAsync = ref.watch(walletProvider);
    final availableBalance = walletAsync.value?.availableBalance ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // User Info Card Header
              Container(
                color: AppColors.card,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
                          backgroundImage: (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                              ? NetworkImage(user.photoURL!)
                              : null,
                          child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                              ? const Icon(Icons.person, size: 36, color: AppColors.primaryGreen)
                              : null,
                        ),
                        if (_isUploadingAvatar)
                          const CircularProgressIndicator(color: AppColors.primaryGreen),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Leafy Shopper',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.phoneNumber ?? user?.email ?? '+91 98765 43210',
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Verified Customer',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primaryGreen),
                      tooltip: 'Upload Avatar',
                      onPressed: _pickAndUploadAvatar,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Wallet Quick Balance Bar
              GestureDetector(
                onTap: () => context.push('/wallet'),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Leafy Wallet', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                '₹${availableBalance.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Row(
                        children: [
                          Text('View Wallet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          Icon(Icons.chevron_right, color: Colors.white, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action Options List
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildListTile(
                      icon: Icons.local_shipping_outlined,
                      title: 'My Orders',
                      subtitle: 'Track, return or reorder items',
                      onTap: () => context.push('/orders'),
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildListTile(
                      icon: Icons.share_outlined,
                      title: 'Referral Hub',
                      subtitle: 'Invite friends & earn commission',
                      onTap: () => context.push('/referrals'),
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildListTile(
                      icon: Icons.location_on_outlined,
                      title: 'Delivery Addresses',
                      subtitle: 'Manage home & office addresses',
                      onTap: () => context.push('/addresses'),
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildListTile(
                      icon: Icons.support_agent_outlined,
                      title: 'Help & Support',
                      subtitle: 'FAQs, Live Chat, Call Us',
                      onTap: () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Logout Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await firebase_auth.FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.logout, color: AppColors.error, size: 18),
                    label: const Text('Log Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primaryGreen, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
      onTap: onTap,
    );
  }
}
