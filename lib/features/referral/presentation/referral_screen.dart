import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pincode = TextEditingController();
  final _search = TextEditingController();
  final Map<String, String> _pending = {};
  String _source = 'WhatsApp';
  String _filter = 'All';
  bool _showForm = false;
  bool _saving = false;

  static const _statuses = ['New', 'Qualified', 'Unqualified'];
  static const _sources = ['Amazon', 'Flipkart', 'Meesho', 'VAMJO', 'WhatsApp', 'Counter Sale'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in [_name, _email, _phone, _pincode, _search]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(referralInfoProvider);
    ref.invalidate(commissionHistoryProvider);
    ref.invalidate(leadsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsProvider);
    final referralInfoAsync = ref.watch(referralInfoProvider);
    final commissionHistoryAsync = ref.watch(commissionHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: const Text('Referral & Commission Hub', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Referral & Commission Data',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryGreen,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.stars_outlined, size: 20), text: 'Commissions'),
            Tab(icon: Icon(Icons.people_alt_outlined, size: 20), text: 'Lead Pipeline'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          if (_tabController.index != 1) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => setState(() => _showForm = !_showForm),
            backgroundColor: AppColors.primaryGreen,
            icon: Icon(_showForm ? Icons.close : Icons.person_add_alt_1),
            label: Text(_showForm ? 'Close' : 'Add lead'),
          );
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Referral Info & 5-Level Commission Overview
          _buildCommissionsTab(referralInfoAsync, commissionHistoryAsync),

          // Tab 2: Existing Customer Lead Capture & Pipeline Tracking
          _buildLeadsTab(leadsAsync),
        ],
      ),
    );
  }

  // --- TAB 1: COMMISSIONS & REFERRAL INFO ---
  Widget _buildCommissionsTab(
    AsyncValue<ReferralInfo?> referralInfoAsync,
    AsyncValue<List<CommissionHistoryItem>> commissionHistoryAsync,
  ) {
    final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
    final customer = ref.watch(currentUserCustomerProvider).value;

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: () async => _refreshAll(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Partner Status, Level & Code Header Card
          referralInfoAsync.when(
            loading: () => const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)))),
            error: (err, _) => _buildReferralCardFallback(currentUser, customer),
            data: (info) => info != null ? _buildReferralInfoCard(info) : _buildReferralCardFallback(currentUser, customer),
          ),

          const SizedBox(height: 16),

          // 2. Direct Sponsor Info Card (Read-Only Display)
          referralInfoAsync.maybeWhen(
            data: (info) => info?.sponsor != null ? _buildSponsorCard(info!.sponsor!) : _buildSponsorCardFallback(customer),
            orElse: () => _buildSponsorCardFallback(customer),
          ),

          const SizedBox(height: 16),

          // 3. Commission Summary Card (Pending, Confirmed, Payable, Paid)
          referralInfoAsync.maybeWhen(
            data: (info) => _buildCommissionSummaryCard(info?.commissionSummary),
            orElse: () => _buildCommissionSummaryCard(null),
          ),

          const SizedBox(height: 20),

          // 4. Rolling 5-Level Commission History Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('5-Level Commission History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
              TextButton.icon(
                onPressed: () => ref.invalidate(commissionHistoryProvider),
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 5. Commission History List
          commissionHistoryAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))),
            error: (err, _) => _ErrorState(message: 'Unable to load commission history: $err', onRetry: () => ref.invalidate(commissionHistoryProvider)),
            data: (items) {
              if (items.isEmpty) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.history_outlined, size: 40, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No Commission Transactions Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                        SizedBox(height: 4),
                        Text('Commissions earned from your 5-level referral network orders will appear here automatically after server processing.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: items.map(_buildCommissionItemCard).toList(),
              );
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- REFERRAL INFO HEADER CARD ---
  Widget _buildReferralInfoCard(ReferralInfo info) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars, color: Colors.amber, size: 24),
                  const SizedBox(width: 8),
                  Text('Level: ${info.partnerLevel.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Status: ${info.partnerStatus}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Referral Code & Link Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Referral Code', style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.referralCode,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                      tooltip: 'Copy Referral Code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: info.referralCode));
                        _message('Referral code "${info.referralCode}" copied to clipboard!');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white, size: 20),
                      tooltip: 'Share Referral Link',
                      onPressed: () => _shareReferralLink(info.referralLink, info.referralCode),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 16),
                Text('Link: ${info.referralLink}', style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Summary Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildHeaderStat('Total Referrals', '${info.referralCount}', Icons.people_outline),
              Container(height: 24, width: 1, color: Colors.white30),
              _buildHeaderStat('Qualified Partners', '${info.qualifiedCount}', Icons.verified_user_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildReferralCardFallback(firebase_auth.User? user, CustomerPerformance? customer) {
    final code = customer?.referralCode ?? customer?.id ?? user?.uid ?? 'VIOLEAFY';
    final link = 'https://violeafy.com/ref/$code';
    final tier = customer?.tier ?? 'Bronze';

    return _buildReferralInfoCard(
      ReferralInfo(
        referralCode: code,
        referralLink: link,
        partnerStatus: 'Active',
        partnerLevel: tier,
        referralCount: customer?.dealsClosed ?? 0,
        qualifiedCount: 0,
        commissionSummary: CommissionSummary(pending: 0, confirmed: 0, payable: 0, paid: 0),
      ),
    );
  }

  // --- SPONSOR CARD (READ-ONLY) ---
  Widget _buildSponsorCard(SponsorInfo sponsor) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_pin_outlined, color: AppColors.primaryGreen, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Direct Sponsor', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(sponsor.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  if (sponsor.id.isNotEmpty)
                    Text('Partner ID: ${sponsor.id}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(sponsor.status, style: const TextStyle(color: AppColors.primaryGreen, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSponsorCardFallback(CustomerPerformance? customer) {
    if (customer?.partnerName != null && customer!.partnerName!.isNotEmpty) {
      return _buildSponsorCard(
        SponsorInfo(id: customer.referralCode ?? '', name: customer.partnerName!, status: 'Active'),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Direct Sponsor', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                  Text('Direct Registration (No Sponsor)', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- COMMISSION SUMMARY CARD ---
  Widget _buildCommissionSummaryCard(CommissionSummary? summary) {
    final pending = summary?.pending ?? 0.0;
    final confirmed = summary?.confirmed ?? 0.0;
    final payable = summary?.payable ?? 0.0;
    final paid = summary?.paid ?? 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Commission Balance Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildSummaryBox('Pending', '₹${pending.toStringAsFixed(0)}', Colors.orange)),
                const SizedBox(width: 8),
                Expanded(child: _buildSummaryBox('Confirmed', '₹${confirmed.toStringAsFixed(0)}', Colors.blue)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildSummaryBox('Payable', '₹${payable.toStringAsFixed(0)}', AppColors.primaryGreen)),
                const SizedBox(width: 8),
                Expanded(child: _buildSummaryBox('Paid Out', '₹${paid.toStringAsFixed(0)}', Colors.teal)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBox(String title, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(amount, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- COMMISSION ITEM CARD ---
  Widget _buildCommissionItemCard(CommissionHistoryItem item) {
    final statusColor = _getCommissionStatusColor(item.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #${item.orderNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(item.status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Level ${item.level}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryGreen)),
                ),
                const SizedBox(width: 12),
                Text('Base: ₹${item.commissionBaseAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (item.commissionRate > 0) ...[
                  const SizedBox(width: 12),
                  Text('Rate: ${item.commissionRate}%', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item.createdAt.isNotEmpty ? item.createdAt.split('T').first : 'Recent', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Row(
                  children: [
                    const Text('Earned: ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text('₹${item.commissionAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getCommissionStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.blue;
      case 'payable':
        return AppColors.primaryGreen;
      case 'paid':
        return Colors.teal;
      case 'reversed':
      case 'cancelled':
        return AppColors.error;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  void _shareReferralLink(String link, String code) async {
    final text = 'Join VioLeafy using my referral code $code to enjoy authentic farm produce and exclusive offers!\n$link';
    Clipboard.setData(ClipboardData(text: text));
    _message('Referral link and message copied to clipboard!');

    try {
      final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // --- TAB 2: LEADS & PIPELINE TRACKING ---
  Widget _buildLeadsTab(AsyncValue<List<Lead>> leadsAsync) {
    return leadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      error: (error, _) => _ErrorState(message: 'Unable to load leads: $error', onRetry: () => ref.invalidate(leadsProvider)),
      data: (leads) => RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () async => ref.invalidate(leadsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _summary(leads),
            const SizedBox(height: 16),
            if (_showForm) ...[_form(), const SizedBox(height: 16)],
            _filters(),
            const SizedBox(height: 12),
            ..._filtered(leads).map(_leadCard),
            if (_filtered(leads).isEmpty) const _EmptyState(),
          ],
        ),
      ),
    );
  }

  Widget _summary(List<Lead> leads) {
    final visibleLeads = leads.where((lead) => _statuses.contains(lead.status)).toList();
    final qualified = visibleLeads.where((lead) => lead.status == 'Qualified').length;
    final pipeline = visibleLeads.fold<double>(0, (sum, lead) => sum + lead.value);
    final customer = ref.watch(currentUserCustomerProvider).value;
    final customerId = customer?.id;
    final customerName = customer?.name;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(customerId == null && customerName == null ? 'Customer details unavailable' : '${customerId ?? ''}  ${customerName ?? ''}'.trim(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _summaryItem('Total leads', '${visibleLeads.length}', Icons.people_alt_outlined),
          _summaryItem('Qualified', '$qualified', Icons.verified_outlined),
          _summaryItem('Pipeline', '₹${pipeline.toStringAsFixed(0)}', Icons.trending_up),
        ]),
      ]),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: Colors.white70, size: 20),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );

  Widget _form() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Capture a lead', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _field(_name, 'Contact name or address', Icons.person_outline),
        Row(children: [Expanded(child: _field(_phone, 'WhatsApp mobile', Icons.phone_outlined, keyboardType: TextInputType.phone)), const SizedBox(width: 10), Expanded(child: _field(_email, 'Email (optional)', Icons.email_outlined, required: false, keyboardType: TextInputType.emailAddress))]),
        Row(children: [Expanded(child: _field(_pincode, 'Pincode (optional)', Icons.location_on_outlined, required: false, keyboardType: TextInputType.number)), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(initialValue: _source, decoration: const InputDecoration(labelText: 'Source', prefixIcon: Icon(Icons.campaign_outlined)), items: _sources.map((source) => DropdownMenuItem(value: source, child: Text(source))).toList(), onChanged: (value) => setState(() => _source = value ?? _source)))]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _createLead, icon: const Icon(Icons.add), label: Text(_saving ? 'Saving...' : 'Save lead'))),
      ]),
    ),
  );

  Widget _field(TextEditingController controller, String label, IconData icon, {bool required = true, TextInputType? keyboardType}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: label.startsWith('Pincode') ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)] : null,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), prefixText: label == 'WhatsApp mobile' ? '+91 ' : null),
      validator: required ? (value) => value == null || value.trim().isEmpty ? 'Required' : null : null,
    ),
  );

  Widget _filters() => Column(children: [
    TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or phone')),
    const SizedBox(height: 10),
    SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: ['All', ..._statuses].map((status) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(status), selected: _filter == status, onSelected: (_) => setState(() => _filter = status)))).toList())),
  ]);

  List<Lead> _filtered(List<Lead> leads) {
    final query = _search.text.trim().toLowerCase();
    return leads.where((lead) {
      final hasAllowedStatus = _statuses.contains(lead.status);
      final matchesStatus = _filter == 'All' || lead.status == _filter;
      final matchesQuery = query.isEmpty || [lead.name, lead.phone, lead.email].any((value) => value.toLowerCase().contains(query));
      return hasAllowedStatus && matchesStatus && matchesQuery;
    }).toList();
  }

  Widget _leadCard(Lead lead) {
    final status = _pending[lead.id] ?? lead.status;
    final canCommit = status != lead.status && lead.status != 'Qualified';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(lead.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary))), _score(lead.score), PopupMenuButton<String>(onSelected: (action) => _action(action, lead), itemBuilder: (_) => [const PopupMenuItem(value: 'whatsapp', child: Text('WhatsApp welcome')), const PopupMenuItem(value: 'score', child: Text('Increase score')), const PopupMenuItem(value: 'delete', child: Text('Delete lead'))])]),
        Text(lead.name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [_tag(lead.phone, Icons.phone_outlined), _tag(lead.source, Icons.campaign_outlined), _tag('₹${lead.value.toStringAsFixed(0)}', Icons.currency_rupee)]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Pipeline status', isDense: true), items: _statuses.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: lead.status == 'Qualified' ? null : (value) => setState(() => _pending[lead.id] = value ?? lead.status))), if (canCommit) ...[const SizedBox(width: 8), IconButton.filled(onPressed: () => _commit(lead, status), icon: const Icon(Icons.check), tooltip: 'Commit')]])
      ])),
    );
  }

  Widget _score(double score) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text('AI ${score.toInt()}', style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 12)));

  Widget _tag(String text, IconData icon) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: AppColors.secondaryBackground, borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: AppColors.textMuted), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))]));

  Future<void> _createLead() async {
    if (!_formKey.currentState!.validate()) return;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final phone = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    if (phone.length != 10) return _message('Validation Error: WhatsApp Mobile Phone is mandatory and must be exactly 10 digits.');
    final current = ref.read(leadsProvider).value ?? [];
    if (current.any((lead) => lead.phone.replaceAll(RegExp(r'\D'), '') == phone)) return _message('Mobile number is already reserved. Duplicate number is not allowed.');
    setState(() => _saving = true);
    final value = 10000.0;
    final score = ((value / 500) + (_source == 'Amazon' || _source == 'Flipkart' ? 25 : 15) + (DateTime.now().millisecond % 21)).clamp(0, 100).toDouble();
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final lead = Lead(id: 'lead_${DateTime.now().millisecondsSinceEpoch}', name: _name.text.trim(), email: _email.text.trim(), phone: phone, status: 'New', score: score, source: _source, assignedTo: 'Tony Stark', createdAt: DateTime.now().toIso8601String(), value: value, referralCode: user?.uid, referralPartner: user?.displayName, pincode: _pincode.text.trim().isEmpty ? null : _pincode.text.trim());
    final success = await ref.read(shoppingRepositoryProvider).saveLead(lead);
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) { _clearForm(); ref.invalidate(leadsProvider); _message('Lead saved successfully.'); } else { _message(ref.read(shoppingRepositoryProvider).lastLeadSaveError ?? 'Unable to save lead. Please try again.'); }
  }

  Future<void> _commit(Lead lead, String status) async {
    if (status == 'Qualified') {
      final location = await _location(lead.pincode);
      final customer = CustomerPerformance(id: 'customer_${lead.id}', name: lead.name, company: 'Individual', email: lead.email.isEmpty ? 'n/a' : lead.email, mobileNumber: lead.phone, address: lead.name, state: location.$1, district: location.$2, pincode: lead.pincode ?? '000000', totalSpent: lead.value, dealsClosed: 1, satisfactionScore: 5, lastOrderDate: DateTime.now().toIso8601String().split('T').first, tier: 'Silver', partnerName: lead.referralPartner, isFromLead: true, leadId: lead.id, referralCode: lead.referralCode);
      if (!await ref.read(shoppingRepositoryProvider).saveCustomer(customer)) return _message('Lead could not be converted to a customer.');
    }
    final updated = Lead(id: lead.id, name: lead.name, email: lead.email, phone: lead.phone, status: status, score: lead.score, source: lead.source, assignedTo: lead.assignedTo, createdAt: lead.createdAt, value: lead.value, referralCode: lead.referralCode, referralPartner: lead.referralPartner, referralmobileno: lead.referralmobileno, pincode: lead.pincode, productId: lead.productId);
    final saved = await ref.read(shoppingRepositoryProvider).saveLead(updated);
    if (saved) {
      _pending.remove(lead.id);
      ref.invalidate(leadsProvider);
      _message(status == 'Qualified' ? 'Lead converted and locked.' : 'Status committed.');
    } else {
      _message(ref.read(shoppingRepositoryProvider).lastLeadSaveError ?? 'Unable to save lead. Please try again.');
    }
  }

  Future<(String, String)> _location(String? pincode) async {
    const exact = {'110001': ('Delhi', 'New Delhi'), '400001': ('Maharashtra', 'Mumbai'), '682011': ('Kerala', 'Ernakulam'), '600001': ('Tamil Nadu', 'Chennai'), '560001': ('Karnataka', 'Bengaluru Urban')};
    const first = {'1': ('Delhi', 'New Delhi'), '2': ('Uttar Pradesh', 'Noida'), '3': ('Gujarat', 'Ahmedabad'), '4': ('Maharashtra', 'Mumbai'), '5': ('Karnataka', 'Bengaluru Urban'), '6': ('Kerala', 'Ernakulam'), '7': ('West Bengal', 'Kolkata'), '8': ('Bihar', 'Patna')};
    if (pincode != null && RegExp(r'^\d{6}$').hasMatch(pincode)) {
      try {
        final response = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pincode')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body);
          final offices = payload is List && payload.isNotEmpty ? payload.first['PostOffice'] : null;
          if (offices is List && offices.isNotEmpty) {
            final office = offices.first;
            return ('${office['State'] ?? ''}', '${office['District'] ?? ''}');
          }
        }
      } catch (e) {
        debugPrint('[ReferralScreen] Pincode lookup failed: $e');
      }
    }
    return exact[pincode] ?? first[pincode?.substring(0, 1)] ?? ('', '');
  }

  Future<void> _action(String action, Lead lead) async {
    if (action == 'score') {
      final updated = Lead(id: lead.id, name: lead.name, email: lead.email, phone: lead.phone, status: lead.status, score: (lead.score + 10).clamp(0, 100), source: lead.source, assignedTo: lead.assignedTo, createdAt: lead.createdAt, value: lead.value, referralCode: lead.referralCode, referralPartner: lead.referralPartner, referralmobileno: lead.referralmobileno, pincode: lead.pincode, productId: lead.productId);
      if (await ref.read(shoppingRepositoryProvider).saveLead(updated)) ref.invalidate(leadsProvider);
    } else if (action == 'delete') {
      if (await ref.read(shoppingRepositoryProvider).deleteLead(lead.id)) { ref.invalidate(leadsProvider); _message('Lead deleted.'); }
    } else {
      final text = 'Hello ${lead.name}, Natasha here from VioneX! I have customized a secure sales dashboard for you. Are you tomorrow at 10 AM free for a brief 10 min setup sync?';
      final phone = lead.phone.replaceAll(RegExp(r'\D'), '');
      await ref.read(shoppingRepositoryProvider).saveWhatsAppMessage(phone: lead.phone, text: text, leadId: lead.id);
      await launchUrl(Uri.parse('https://wa.me/91${phone.length > 10 ? phone.substring(phone.length - 10) : phone}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
    }
  }

  void _clearForm() { for (final controller in [_name, _email, _phone, _pincode]) { controller.clear(); } setState(() => _showForm = false); }
  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No leads match the current filters.', style: TextStyle(color: AppColors.textSecondary))));
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, child: const Text('Retry'))]));
}
