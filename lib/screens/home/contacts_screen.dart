import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import '../../widgets/common_widgets.dart';

// Merged entry for a phone contact
class _PhoneContactEntry {
  final String name;
  final String phone;   // normalized phone number
  final UserModel? safepayUser; // non-null if they're on SafePay
  final bool isTrusted;

  _PhoneContactEntry({
    required this.name,
    required this.phone,
    this.safepayUser,
    this.isTrusted = false,
  });

  bool get isOnSafePay => safepayUser != null;
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _permissionDenied = false;
  bool _isLoading = true;

  List<_PhoneContactEntry> _safepayContacts = [];   // on SafePay
  List<_PhoneContactEntry> _nonSafepayContacts = []; // not on SafePay

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadContacts();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);

    // Request contacts permission
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _isLoading = false;
        });
      }
      return;
    }

    // Fetch device contacts with phone numbers
    final deviceContacts = await FlutterContacts.getContacts(
      withProperties: true,
      withThumbnail: false,
    );

    if (!mounted) return;

    final auth = context.read<AuthService>();
    final contactsService = context.read<ContactsService>();
    final currentUserId = auth.currentUser?.uid;

    // Get current user's trusted contacts
    final trusted = currentUserId != null
        ? await contactsService.watchTrustedContacts(currentUserId).first
        : <dynamic>[];
    if (!mounted) return;
    final trustedUids = {for (final t in trusted) t.contactUserId};

    // Collect all unique phone numbers first
    final phoneToName = <String, String>{};
    final seen = <String>{};
    for (final contact in deviceContacts) {
      final name = contact.displayName.trim();
      if (name.isEmpty || contact.phones.isEmpty) continue;
      for (final phone in contact.phones) {
        final raw = phone.number.replaceAll(RegExp(r'[^\d]'), '');
        final normalized = raw.length >= 10 ? raw.substring(raw.length - 10) : raw;
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        phoneToName[normalized] = name;
      }
    }

    // Batch getUserByPhone lookups in chunks of 10 for performance
    final phones = phoneToName.keys.toList();
    final phoneToUser = <String, UserModel?>{};
    const batchSize = 10;
    for (var i = 0; i < phones.length; i += batchSize) {
      if (!mounted) return; // Early abort if navigated away
      final batch = phones.sublist(i, (i + batchSize).clamp(0, phones.length));
      final results = await Future.wait(
        batch.map((p) => auth.getUserByPhone(p)),
      );
      for (var j = 0; j < batch.length; j++) {
        phoneToUser[batch[j]] = results[j];
      }
    }

    if (!mounted) return;

    final safepay = <_PhoneContactEntry>[];
    final nonSafepay = <_PhoneContactEntry>[];

    for (final entry in phoneToName.entries) {
      final normalized = entry.key;
      final name = entry.value;
      final safepayUser = phoneToUser[normalized];

      // Skip self
      if (safepayUser != null && safepayUser.uid == currentUserId) continue;

      final isTrusted = safepayUser != null && trustedUids.contains(safepayUser.uid);

      final contactEntry = _PhoneContactEntry(
        name: name,
        phone: normalized,
        safepayUser: safepayUser,
        isTrusted: isTrusted,
      );

      if (safepayUser != null) {
        safepay.add(contactEntry);
      } else {
        nonSafepay.add(contactEntry);
      }
    }

    // Sort: trusted first, then alphabetical
    safepay.sort((a, b) {
      if (a.isTrusted && !b.isTrusted) return -1;
      if (!a.isTrusted && b.isTrusted) return 1;
      return a.name.compareTo(b.name);
    });
    nonSafepay.sort((a, b) => a.name.compareTo(b.name));

    if (mounted) {
      setState(() {
        _safepayContacts = safepay;
        _nonSafepayContacts = nonSafepay;
        _isLoading = false;
      });
    }
  }

  Future<void> _addTrusted(_PhoneContactEntry entry) async {
    final auth = context.read<AuthService>();
    final contactsService = context.read<ContactsService>();
    if (auth.currentUser == null || entry.safepayUser == null) return;

    final error = await contactsService.addTrustedContact(
      ownerUserId: auth.currentUser!.uid,
      contact: entry.safepayUser!,
    );

    if (mounted) {
      if (error != null) {
        AppSnackBar.showError(context, error);
      } else {
        AppSnackBar.showSuccess(context, '${entry.name} added as trusted contact ✅');
        _loadContacts(); // refresh
      }
    }
  }

  Future<void> _removeTrusted(_PhoneContactEntry entry) async {
    final auth = context.read<AuthService>();
    final contactsService = context.read<ContactsService>();
    if (auth.currentUser == null || entry.safepayUser == null) return;

    // Find the trusted contact doc ID
    final trusted = await contactsService
        .watchTrustedContacts(auth.currentUser!.uid)
        .first;
    final match = trusted.where(
        (t) => t.contactUserId == entry.safepayUser!.uid).firstOrNull;
    if (match == null) return;

    await contactsService.removeTrustedContact(match.id, auth.currentUser!.uid);
    if (mounted) {
      AppSnackBar.showSuccess(context, '${entry.name} removed from trusted');
      _loadContacts();
    }
  }

  Future<void> _sendInvite(_PhoneContactEntry entry) async {
    final message = Uri.encodeComponent(
      'Hey ${entry.name.split(' ').first}! 👋 I use SafePay for safe, consent-based UPI payments. Join me! Download: https://safepay.app',
    );
    final uri = Uri.parse('sms:${entry.phone}?body=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) AppSnackBar.showError(context, 'Could not open SMS app');
    }
  }

  List<_PhoneContactEntry> _filter(List<_PhoneContactEntry> list) {
    if (_searchQuery.isEmpty) return list;
    return list.where((e) =>
        e.name.toLowerCase().contains(_searchQuery) ||
        e.phone.contains(_searchQuery)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Contacts'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadContacts,
            tooltip: 'Refresh',
          ),
        ],
        bottom: _permissionDenied || _isLoading
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primaryColor,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                tabs: [
                  Tab(text: 'On SafePay (${_safepayContacts.length})'),
                  Tab(text: 'Invite (${_nonSafepayContacts.length})'),
                ],
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_permissionDenied) return _buildPermissionDenied();
    if (_isLoading) return _buildLoading();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by name or number...',
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppTheme.textSecondary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSafepayTab(),
              _buildInviteTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          Text(
            'Loading contacts...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.contacts_outlined,
                  color: AppTheme.errorColor, size: 40),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            const Text(
              'Contacts Permission Required',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'SafePay needs access to your contacts to show which of your friends are on SafePay.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Grant Permission',
              onPressed: _loadContacts,
              icon: Icons.contacts_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafepayTab() {
    final filtered = _filter(_safepayContacts);
    if (filtered.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline_rounded,
        title: _searchQuery.isNotEmpty ? 'No match found' : 'No SafePay friends yet',
        subtitle: _searchQuery.isNotEmpty
            ? 'Try a different name or number'
            : 'Invite your friends to SafePay!',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final entry = filtered[i];
        return _SafepayContactTile(
          entry: entry,
          onSend: () => context.push('/send-money?upiId=${entry.safepayUser!.upiId}'),
          onTrust: () => _addTrusted(entry),
          onUntrust: () => _removeTrusted(entry),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
      },
    );
  }

  Widget _buildInviteTab() {
    final filtered = _filter(_nonSafepayContacts);
    if (filtered.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_add_outlined,
        title: _searchQuery.isNotEmpty ? 'No match found' : 'All contacts are on SafePay!',
        subtitle: '🎉 Wow, your whole contact list uses SafePay!',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final entry = filtered[i];
        return _InviteTile(
          entry: entry,
          onInvite: () => _sendInvite(entry),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 30));
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
        ],
      ),
    );
  }
}

// ── SafePay contact tile ──────────────────────────────────────────────────────
class _SafepayContactTile extends StatelessWidget {
  final _PhoneContactEntry entry;
  final VoidCallback onSend;
  final VoidCallback onTrust;
  final VoidCallback onUntrust;

  const _SafepayContactTile({
    required this.entry,
    required this.onSend,
    required this.onTrust,
    required this.onUntrust,
  });

  @override
  Widget build(BuildContext context) {
    final user = entry.safepayUser!;
    final color = entry.isTrusted ? AppTheme.successColor : AppTheme.primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.isTrusted
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : AppTheme.darkDivider,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Stack(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  entry.name[0].toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // SafePay badge
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 10),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text(
              entry.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (entry.isTrusted) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '✓ Trusted',
                  style: TextStyle(
                    color: AppTheme.successColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (user.isMerchant) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Merchant',
                  style: TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          user.upiId,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Send money
            IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, size: 20),
              color: AppTheme.primaryColor,
              tooltip: 'Send money',
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(width: 4),
            // Trust toggle
            IconButton(
              onPressed: entry.isTrusted ? onUntrust : onTrust,
              icon: Icon(
                entry.isTrusted
                    ? Icons.verified_user_rounded
                    : Icons.person_add_alt_1_rounded,
                size: 20,
              ),
              color: entry.isTrusted
                  ? AppTheme.successColor
                  : AppTheme.textSecondary,
              tooltip: entry.isTrusted ? 'Remove trusted' : 'Add trusted',
              style: IconButton.styleFrom(
                backgroundColor: (entry.isTrusted
                        ? AppTheme.successColor
                        : AppTheme.textSecondary)
                    .withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Non-SafePay invite tile ───────────────────────────────────────────────────
class _InviteTile extends StatelessWidget {
  final _PhoneContactEntry entry;
  final VoidCallback onInvite;

  const _InviteTile({required this.entry, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              entry.name[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        title: Text(
          entry.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          '+91 ${entry.phone}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: TextButton.icon(
          onPressed: onInvite,
          icon: const Icon(Icons.send_rounded, size: 14),
          label: const Text('Invite'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accentOrange,
            backgroundColor: AppTheme.accentOrange.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
