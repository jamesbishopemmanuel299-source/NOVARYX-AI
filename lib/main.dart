import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_data_store.dart';
import 'package:url_launcher/url_launcher.dart';

const String _supabaseUrlFromBuild = String.fromEnvironment('SUPABASE_URL');
const String _supabaseKeyFromBuild = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

// Keep the project URL configurable at build time. Trim accidental whitespace
// from GitHub Actions secrets and reject malformed URLs before auth requests.
String get defaultSupabaseUrl {
  final configured = _supabaseUrlFromBuild.trim();
  final url = configured.isEmpty
      ? 'https://vihbsfrwnslnmheowkhy.supabase.co'
      : configured;
  final parsed = Uri.tryParse(url);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      parsed.host.isEmpty ||
      !parsed.host.endsWith('.supabase.co')) {
    throw StateError(
      'Invalid Supabase URL. Set SUPABASE_URL to the HTTPS Project URL '
      'copied from Supabase Dashboard → Project Settings → API.',
    );
  }
  return url;
}

String get defaultSupabasePublishableKey {
  final configured = _supabaseKeyFromBuild.trim();
  return configured.isEmpty
      ? 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz'
      : configured;
}

String? _supabaseStartupError;
Future<void>? _supabaseInitialization;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovaryxApp());
  _supabaseInitialization = _initializeSupabaseDirectly();
}

Future<void> _initializeSupabaseDirectly() async {
  try {
    final url = defaultSupabaseUrl;
    final key = defaultSupabasePublishableKey.trim();
    if (key.isEmpty) {
      throw StateError(
        'Supabase publishable key is missing. Set SUPABASE_PUBLISHABLE_KEY '
        'in the Flutter build environment.',
      );
    }
    await Supabase.initialize(url: url, anonKey: key);
    _supabaseStartupError = null;
    debugPrint('NOVARYX-AI Supabase initialized from Flutter build configuration.');
  } catch (error, stackTrace) {
    _supabaseStartupError = error.toString();
    debugPrint('NOVARYX-AI Supabase startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class NovaryxApp extends StatelessWidget {
  const NovaryxApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF176BFF);
    return MaterialApp(
      title: 'NOVARYX-AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF080D24),
          primary: const Color(0xFF00EFFF),
          secondary: const Color(0xFFB33CFF),
        ),
        scaffoldBackgroundColor: const Color(0xFF030716),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF05091B),
          foregroundColor: Color(0xFFF4FAFF),
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF05091B),
          indicatorColor: const Color(0xFF123C70),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected) ? const Color(0xFF00EFFF) : const Color(0xFF8493B8),
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          )),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0A1230),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF173568)),
          ),
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF080F28),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF244A82))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF244A82))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00EFFF), width: 1.5)),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}


class CreditsBalanceBadge extends StatefulWidget {
  const CreditsBalanceBadge({super.key});
  @override
  State<CreditsBalanceBadge> createState() => _CreditsBalanceBadgeState();
}
class _CreditsBalanceBadgeState extends State<CreditsBalanceBadge> {
  late Future<int?> _balance;
  @override
  void initState() { super.initState(); _balance = _load(); }
  Future<int?> _load() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await client.from('generation_credits').select('balance').eq('user_id', user.id).maybeSingle();
      return row == null ? null : (row['balance'] as num).toInt();
    } catch (_) { return null; }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<int?>(
    future: _balance,
    builder: (context, snapshot) => InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => setState(() => _balance = _load()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF092543),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF00EFFF).withValues(alpha: 0.65)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bolt, color: Color(0xFF00EFFF), size: 18),
          const SizedBox(width: 4),
          Text(snapshot.connectionState == ConnectionState.waiting ? '…' :
            snapshot.data == null ? 'Credits' : '${snapshot.data}',
            style: const TextStyle(color: Color(0xFFF4FAFF), fontWeight: FontWeight.w800)),
        ]),
      ),
    ),
  );
}


class CreditPackage {
  const CreditPackage(this.credits, this.priceNaira, this.label);
  final int credits;
  final int priceNaira;
  final String label;
}

class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key});
  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  static const packages = <CreditPackage>[
    CreditPackage(100, 1332, 'Starter'),
    CreditPackage(250, 3330, 'Mini'),
    CreditPackage(500, 6659, 'Plus'),
    CreditPackage(1000, 13318, 'Pro'),
    CreditPackage(2500, 33295, 'Creator'),
    CreditPackage(5000, 66590, 'Studio'),
    CreditPackage(10000, 133180, 'Max'),
  ];
  bool _busy = false;
  String _status = '';
  String? _pendingRef;
  int? _selectedCredits;

  Future<void> _buy(CreditPackage package) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.email == null) {
      setState(() => _status = 'Sign in with an email in Settings before buying credits.');
      return;
    }
    setState(() { _busy = true; _status = 'Creating secure checkout…'; _selectedCredits = package.credits; });
    try {
      final response = await client.functions.invoke('provider-gateway', body: {
        'action': 'credit-purchase-initialize', 'credits': package.credits,
        'email': user.email,
      });
      final data = _decodeBody(jsonEncode(response.data));
      if (response.status < 200 || response.status >= 300) throw Exception(_errorFrom(data, response.status));
      final link = data['checkout_url']?.toString() ?? '';
      final ref = data['tx_ref']?.toString() ?? '';
      if (!link.startsWith('https://') || ref.isEmpty) throw Exception('Checkout link was not returned.');
      _pendingRef = ref;
      final opened = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open checkout. Try again.');
      if (mounted) setState(() => _status = 'Complete payment in your browser, then return here and tap Verify payment.');
    } catch (e) {
      if (mounted) setState(() => _status = _cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final ref = _pendingRef;
    if (ref == null) { setState(() => _status = 'Choose a package and start checkout first.'); return; }
    final idController = TextEditingController();
    final transactionId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify payment'),
        content: TextField(controller: idController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Flutterwave transaction ID', hintText: 'Enter the ID from your payment receipt')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, idController.text.trim()), child: const Text('Verify')),
        ],
      ),
    );
    idController.dispose();
    if (transactionId == null || transactionId.isEmpty) return;
    setState(() { _busy = true; _status = 'Verifying payment with Flutterwave…'; });
    try {
      final response = await Supabase.instance.client.functions.invoke('provider-gateway', body: {
        'action': 'credit-purchase-verify', 'tx_ref': ref, 'transaction_id': transactionId,
      });
      final data = _decodeBody(jsonEncode(response.data));
      if (response.status < 200 || response.status >= 300) throw Exception(_errorFrom(data, response.status));
      if (mounted) setState(() { _status = 'Payment verified. ${data['credits_added'] ?? _selectedCredits} credits added.'; _pendingRef = null; });
    } catch (e) {
      if (mounted) setState(() => _status = _cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int?> _balance() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final row = await Supabase.instance.client.from('generation_credits').select('balance').eq('user_id', user.id).maybeSingle();
    return row == null ? null : (row['balance'] as num).toInt();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Top up credits')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your available credits', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 8),
        FutureBuilder<int?>(future: _balance(), builder: (context, snapshot) => Text(snapshot.data == null ? '— credits' : '${snapshot.data} credits', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF00EFFF)))),
        const SizedBox(height: 6),
        const Text('Secure checkout powered by Flutterwave.', style: TextStyle(color: Colors.white60)),
      ]))),
      const SizedBox(height: 12),
      for (final package in packages) Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFF123C70), child: Icon(Icons.bolt, color: Color(0xFF00EFFF))),
        title: Text('${package.credits} credits', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${package.label} package'),
        trailing: FilledButton(onPressed: _busy ? null : () => _buy(package), child: Text('₦${package.priceNaira}')),
      )),
      if (_pendingRef != null) ...[
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _busy ? null : _verify, icon: const Icon(Icons.verified_outlined), label: const Text('Verify payment')),
      ],
      if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(_status, style: const TextStyle(color: Color(0xFFB9ABFF)))),
    ]),
  );
}

class ProviderSettings {
  static const storage = FlutterSecureStorage();
  static const groqKey = 'groq_api_key';
  static const groqModel = 'groq_model';
  static const kieKey = 'kie_api_key';
  static const imageModel = 'kie_image_model';
  static const musicModel = 'kie_music_model';
  static const videoModel = 'kie_video_model';
  static const supabaseUrl = 'supabase_url';
  static const supabaseAnonKey = 'supabase_anon_key';

  static Future<String> read(String key, {String fallback = ''}) async =>
      await storage.read(key: key) ?? fallback;

  static Future<void> write(String key, String value) =>
      storage.write(key: key, value: value.trim());

  static bool get supabaseReady => Supabase.instance.isInitialized;
  static SupabaseClient? get supabase => supabaseReady ? Supabase.instance.client : null;

  static Future<void> connectSupabase(String url, String anonKey) async {
    final resolvedUrl = url.trim().isEmpty ? defaultSupabaseUrl : url.trim();
    final resolvedKey = anonKey.trim().isEmpty ? defaultSupabasePublishableKey : anonKey.trim();
    if (Supabase.instance.isInitialized) {
      final configuredUrl = await read(supabaseUrl, fallback: defaultSupabaseUrl);
      if (configuredUrl != resolvedUrl) {
        throw Exception('Supabase is already initialized with the app default project. To change projects, restart the app after updating settings.');
      }
      return;
    }
    await Supabase.initialize(url: resolvedUrl, anonKey: resolvedKey);
  }
}


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _busy = false;
  String? _exactError;
  String? _errorType;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorType = 'InputValidation';
        _exactError = 'Enter both your email address and password.';
      });
      return;
    }
    setState(() { _busy = true; _exactError = null; _errorType = null; });
    try {
      // Wait for the Render config endpoint and Supabase initialization before
      // attempting authentication, so a cold start cannot cause a false error.
      await _supabaseInitialization?.timeout(const Duration(seconds: 30));
      if (!Supabase.instance.isInitialized) {
        throw StateError(_supabaseStartupError ??
            'Supabase initialization has not completed. Check the Render service and /api/config endpoint.');
      }
      if (_creatingAccount) {
        await Supabase.instance.client.auth.signUp(email: email, password: password)
            .timeout(const Duration(seconds: 30));
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password)
            .timeout(const Duration(seconds: 30));
      }
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentSession != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully.')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        );
      } else if (_creatingAccount) {
        setState(() {
          _errorType = 'EmailConfirmationRequired';
          _exactError = 'Account creation returned no active session. Check your email for a confirmation link if email confirmation is enabled in Supabase.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('NOVARYX-AI login error type: ${error.runtimeType}');
      debugPrint('NOVARYX-AI login exact error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;

      // Give DNS/host-lookup failures a useful explanation without hiding the
      // original exception. Retrying credentials cannot fix a hostname that
      // the device cannot resolve.
      final rawError = error.toString();
      final lowerError = rawError.toLowerCase();
      final isHostLookupFailure =
          lowerError.contains('failed host lookup') ||
          lowerError.contains('no address associated with hostname') ||
          lowerError.contains('socketexception');
      setState(() {
        _errorType = error.runtimeType.toString();
        _exactError = isHostLookupFailure
            ? '$rawError\n\nConnection diagnosis: the device could not resolve the configured Supabase hostname. Verify the Project URL in Supabase Dashboard → Project Settings → API, confirm the project is active (not paused or deleted), and ensure the URL matches exactly. The app is using: ${defaultSupabaseUrl}. This is a server/DNS connection error, not an email or password error.'
            : rawError;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NOVARYX account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.lock_person_outlined, size: 56, color: Color(0xFF00EFFF)),
          const SizedBox(height: 14),
          Text(_creatingAccount ? 'Create your account' : 'Sign in',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('If authentication fails, the original exception details appear below.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 24),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _authenticate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_creatingAccount ? 'Create account' : 'Sign in'),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() {
              _creatingAccount = !_creatingAccount;
              _exactError = null;
              _errorType = null;
            }),
            child: Text(_creatingAccount ? 'Already have an account? Sign in' : 'New to NOVARYX? Create an account'),
          ),
          if (_exactError != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF35131D),
                border: Border.all(color: const Color(0xFFFF647C)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.error_outline, color: Color(0xFFFF647C)),
                    SizedBox(width: 8),
                    Expanded(child: Text('LOGIN ERROR — EXACT DETAILS',
                      style: TextStyle(color: Color(0xFFFF8798), fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 10),
                  Text('Error type: ${_errorType ?? 'Unknown'}'),
                  const SizedBox(height: 6),
                  SelectableText(_exactError!, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _authenticate,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final _messages = <ChatMessage>[];
  final _chatController = TextEditingController();
  bool _sending = false;
  String? _conversationId;
  bool _restoringChat = true;

  @override
  void initState() {
    super.initState();
    _restoreChat();
  }

  Future<void> _restoreChat() async {
    try {
      final conversationId = await NovaryxCloudStore.createOrGetLatestConversation();
      if (conversationId == null) {
        if (mounted) setState(() => _restoringChat = false);
        return;
      }
      final rows = await NovaryxCloudStore.loadChatMessages(conversationId);
      if (!mounted) return;
      setState(() {
        _conversationId = conversationId;
        _messages
          ..clear()
          ..addAll(rows.map((row) => ChatMessage(
            role: row['role']?.toString() ?? 'assistant',
            text: row['content']?.toString() ?? '',
          )));
        _restoringChat = false;
      });
    } catch (_) {
      if (mounted) setState(() => _restoringChat = false);
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final prompt = _chatController.text.trim();
    if (prompt.isEmpty || _sending) return;
    setState(() {
      _messages.add(ChatMessage(role: 'user', text: prompt));
      _sending = true;
    });
    _chatController.clear();
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Sign in to your Supabase account in Settings before using AI services.');
      }
      _conversationId ??= await NovaryxCloudStore.createOrGetLatestConversation();
      final conversationId = _conversationId;
      if (conversationId != null) {
        await NovaryxCloudStore.saveChatMessage(
          conversationId: conversationId,
          role: 'user',
          content: prompt,
        );
      }
      final model = await ProviderSettings.read(
        ProviderSettings.groqModel,
        fallback: 'llama-3.3-70b-versatile',
      );
      final history = _messages
          .map((m) => <String, dynamic>{'role': m.role, 'content': m.text})
          .toList();
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Sign in to your Supabase account in Settings before using AI services.');
      }
      final response = await Supabase.instance.client.functions
          .invoke(
            'provider-gateway',
            body: {'action': 'chat', 'model': model, 'messages': history},
          )
          .timeout(const Duration(seconds: 90));
      final body = _decodeBody(jsonEncode(response.data));
      if (response.status < 200 || response.status >= 300) {
        throw Exception(_errorFrom(body, response.status));
      }
      final choices = body['choices'];
      final answer = choices is List && choices.isNotEmpty
          ? (choices.first['message']?['content']?.toString() ?? '')
          : '';
      if (answer.isEmpty) throw Exception('The provider returned an empty answer.');
      if (mounted) setState(() => _messages.add(ChatMessage(role: 'assistant', text: answer)));
      if (conversationId != null) {
        await NovaryxCloudStore.saveChatMessage(
          conversationId: conversationId,
          role: 'assistant',
          content: answer,
          model: model,
        );
      }
      await GenerationHistory.save(
        kind: 'chat',
        prompt: prompt,
        resultText: answer,
        model: model,
      );
    } catch (e) {
      if (mounted) setState(() => _messages.add(ChatMessage(
        role: 'assistant',
        text: 'Could not get a response. ${_cleanError(e)}',
      )));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildChat(),
      const GenerationScreen(kind: GenerationKind.image),
      const GenerationScreen(kind: GenerationKind.music),
      const GenerationScreen(kind: GenerationKind.video),
      const GenerationHistoryScreen(),
      const TemplatesScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF00EFFF)),
            SizedBox(width: 10),
            Text('NOVARYX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.6, color: Color(0xFFF4FAFF))),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Sign in / account', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())), icon: const Icon(Icons.account_circle_outlined, color: Color(0xFF00EFFF))),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: CreditsBalanceBadge()),
          IconButton(tooltip: 'Top up credits', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TopUpScreen())), icon: const Icon(Icons.add_card_outlined, color: Color(0xFF00EFFF))),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.image_outlined), selectedIcon: Icon(Icons.image), label: 'Image'),
          NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Video'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: 'History'),
          NavigationDestination(icon: Icon(Icons.dashboard_customize_outlined), selectedIcon: Icon(Icons.dashboard_customize), label: 'Templates'),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 54, color: Color(0xFFAC9AFF)),
                        SizedBox(height: 18),
                        Text('What can I help you create?', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Ask questions, brainstorm ideas, or get help with a project.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_sending && index == _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Align(alignment: Alignment.centerLeft, child: SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    final message = _messages[index];
                    final isUser = message.role == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: isUser ? const Color(0xFF123D72) : const Color(0xFF0A1230),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(message.text),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message NOVARYX...',
                      filled: true,
                      fillColor: const Color(0xFF080F28),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _sendMessage,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Send message',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  ChatMessage({required this.role, required this.text});
  final String role;
  final String text;
}

enum GenerationKind { image, music, video }

extension GenerationKindInfo on GenerationKind {
  String get label => switch (this) {
        GenerationKind.image => 'Image',
        GenerationKind.music => 'Music',
        GenerationKind.video => 'Video',
      };
  String get description => switch (this) {
        GenerationKind.image => 'Create an image from a text prompt.',
        GenerationKind.music => 'Generate a music track from an idea or style.',
        GenerationKind.video => 'Turn a prompt into a video clip.',
      };
  IconData get icon => switch (this) {
        GenerationKind.image => Icons.image_outlined,
        GenerationKind.music => Icons.music_note_outlined,
        GenerationKind.video => Icons.movie_outlined,
      };
  String get modelKey => switch (this) {
        GenerationKind.image => ProviderSettings.imageModel,
        GenerationKind.music => ProviderSettings.musicModel,
        GenerationKind.video => ProviderSettings.videoModel,
      };
}


String _styleInstruction(GenerationKind kind, String style) {
  switch (kind) {
    case GenerationKind.image:
      const styles = <String, String>{
        'Cinematic': 'cinematic composition, dramatic lighting, rich color grading, professional visual storytelling',
        'Photorealistic': 'photorealistic, natural textures, realistic lighting, fine detail, physically plausible scene',
        'Anime': 'high-quality anime illustration, expressive shapes, polished linework, vibrant colors',
        '3D Animation': 'polished 3D animated film aesthetic, expressive forms, detailed materials, studio lighting',
        'Fantasy': 'epic fantasy concept art, magical atmosphere, intricate worldbuilding, luminous effects',
        'Cyberpunk': 'cyberpunk neon palette, futuristic architecture, atmospheric haze, high contrast',
        'Watercolor': 'traditional watercolor painting, pigment blooms, textured paper, soft edges',
        'Oil Painting': 'classical oil painting, visible brushwork, layered pigments, painterly lighting',
        'Pixel Art': 'intentional pixel art, limited palette, crisp pixel clusters, retro game composition',
        'Comic Book': 'graphic novel illustration, bold ink contours, dynamic framing, dramatic shading',
        'Minimalist': 'minimalist design, clean geometry, generous negative space, restrained palette',
        'Product Photography': 'premium commercial product photography, controlled studio reflections, clean background',
        'Portrait': 'editorial portrait photography, natural skin texture, flattering soft light, sharp eyes',
        'Architecture': 'architectural visualization, accurate perspective, material detail, balanced composition',
        'Logo Concept': 'simple memorable vector-style logo concept, clear silhouette, clean shapes, no mockup',
      };
      return styles[style] ?? styles['Cinematic']!;
    case GenerationKind.music:
      const styles = <String, String>{
        'Afrobeats': 'Afrobeats groove, syncopated percussion, warm guitar, deep bass, catchy melodic hooks',
        'Afro-piano': 'Afro-piano sound, log-drum-inspired bass, rolling percussion, bright keys, dance groove',
        'Pop': 'modern pop production, memorable chorus, polished arrangement, clear melodic hook',
        'Hip-Hop': 'hip-hop beat, strong rhythmic pocket, punchy drums, bass-forward production',
        'R&B / Soul': 'smooth R&B and soul, warm chords, expressive melody, relaxed pocket, rich harmonies',
        'Amapiano': 'Amapiano-inspired rhythm, rolling log drums, airy keys, layered percussion, spacious groove',
        'Gospel': 'uplifting gospel arrangement, hopeful harmony, expressive choir-like backing, dynamic build',
        'EDM / Dance': 'electronic dance production, driving pulse, layered synths, energetic drop',
        'Jazz': 'jazz-inspired harmony, expressive instrumentation, swing feel, warm organic tone',
        'Lo-fi': 'lo-fi chill beat, mellow chords, soft texture, relaxed drums, intimate atmosphere',
        'Cinematic Score': 'cinematic orchestral score, evolving dynamics, emotional motifs, spacious soundstage',
        'Rock': 'energetic rock arrangement, live drums, electric guitars, strong melodic structure',
        'Reggae': 'laid-back reggae groove, offbeat guitar or keyboard skank, rounded bass, relaxed percussion',
        'Classical': 'classical instrumental arrangement, expressive dynamics, nuanced orchestration',
        'Ambient': 'ambient soundscape, slow evolution, spacious textures, immersive atmosphere',
        'Acoustic': 'organic acoustic arrangement, natural instruments, intimate performance feel',
      };
      return styles[style] ?? styles['Afrobeats']!;
    case GenerationKind.video:
      const styles = <String, String>{
        'Cinematic': 'cinematic film look, deliberate camera movement, coherent action, dramatic lighting, smooth motion',
        'Photorealistic': 'photorealistic footage, natural motion, physically plausible lighting and materials',
        'Anime': 'anime animation style, expressive motion, designed backgrounds, consistent character appearance',
        '3D Animation': 'high-quality 3D animation, consistent models, polished materials, smooth character motion',
        'Fantasy': 'fantasy film atmosphere, magical visual effects, epic scale, coherent scene continuity',
        'Cyberpunk': 'neon cyberpunk atmosphere, futuristic city, reflective surfaces, atmospheric lighting',
        'Documentary': 'documentary visual language, natural camera work, observational realism',
        'Music Video': 'stylized music-video visuals, rhythmic edits, expressive camera moves, bold color grading',
        'Anime Action': 'dynamic anime action choreography, readable movement, dramatic framing, consistent characters',
        'Product Ad': 'premium product commercial, controlled camera orbit, clean lighting, clear product focus',
        'Nature': 'nature documentary aesthetic, realistic environments, organic camera movement',
        'Stop Motion': 'stop-motion animation aesthetic, tactile materials, handcrafted movement',
        'Vintage Film': 'vintage film texture, subtle grain, period-inspired color, natural motion',
        'Sci-Fi': 'science-fiction film aesthetic, futuristic technology, atmospheric scale, believable motion',
        'Horror': 'suspenseful horror atmosphere, restrained lighting, unsettling composition, no gratuitous gore',
        'Travel': 'travel-film aesthetic, immersive establishing shots, natural color, fluid camera movement',
      };
      return styles[style] ?? styles['Cinematic']!;
  }
}

List<String> _stylesFor(GenerationKind kind) => switch (kind) {
  GenerationKind.image => const ['Cinematic', 'Photorealistic', 'Anime', '3D Animation', 'Fantasy', 'Cyberpunk', 'Watercolor', 'Oil Painting', 'Pixel Art', 'Comic Book', 'Minimalist', 'Product Photography', 'Portrait', 'Architecture', 'Logo Concept'],
  GenerationKind.music => const ['Afrobeats', 'Afro-piano', 'Pop', 'Hip-Hop', 'R&B / Soul', 'Amapiano', 'Gospel', 'EDM / Dance', 'Jazz', 'Lo-fi', 'Cinematic Score', 'Rock', 'Reggae', 'Classical', 'Ambient', 'Acoustic'],
  GenerationKind.video => const ['Cinematic', 'Photorealistic', 'Anime', '3D Animation', 'Fantasy', 'Cyberpunk', 'Documentary', 'Music Video', 'Anime Action', 'Product Ad', 'Nature', 'Stop Motion', 'Vintage Film', 'Sci-Fi', 'Horror', 'Travel'],
};

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key, required this.kind, this.initialPrompt = '', this.initialStyle, this.initialMode});
  final GenerationKind kind;
  final String initialPrompt;
  final String? initialStyle;
  final String? initialMode;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final _promptController = TextEditingController();
  bool _working = false;
  String _status = '';
  String _selectedStyle = 'Cinematic';
  String _selectedRatio = '16:9';
  String _generationMode = 'Text to image';
  String? _referenceImagePath;
  String? _referenceImageName;
  String? _referenceVideoPath;
  String? _referenceVideoName;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  String _voiceMode = 'AI voice';
  String? _voiceFilePath;
  String? _voiceFileName;
  bool _recordingVoice = false;
  String? _resultUrl;

  @override
  void initState() {
    super.initState();
    _promptController.text = widget.initialPrompt;
    if (widget.initialStyle != null && _stylesFor(widget.kind).contains(widget.initialStyle)) _selectedStyle = widget.initialStyle!;
    if (widget.initialMode != null) _generationMode = widget.initialMode!;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  Future<void> _publishTemplate() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() => _status = 'Sign in before posting a template.');
      return;
    }
    final titleController = TextEditingController(text: _promptController.text.trim().split('\n').first);
    final descriptionController = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post to Templates'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Template title')),
          const SizedBox(height: 10),
          TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Description (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Post template')),
        ],
      ),
    );
    if (approved != true || titleController.text.trim().isEmpty || !mounted) {
      titleController.dispose();
      descriptionController.dispose();
      return;
    }
    try {
      await client.from('community_templates').insert({
        'user_id': user.id,
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'kind': widget.kind.name,
        'prompt': _promptController.text.trim(),
        'style': _selectedStyle,
        'generation_mode': _generationMode,
        'aspect_ratio': _selectedRatio,
        'result_url': _resultUrl,
      });
      if (mounted) setState(() => _status = 'Template posted. Other users can find it in Templates and use or edit it.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not post template: ${_cleanError(e)}. Apply the community_templates migration in Supabase first.');
    } finally {
      titleController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _pickVoiceFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac'],
        withData: false,
      );
      if (picked == null || picked.files.single.path == null) return;
      setState(() {
        _voiceFilePath = picked.files.single.path;
        _voiceFileName = picked.files.single.name;
        _voiceMode = 'Upload voice';
        _status = 'Voice file selected. It will be uploaded securely when you generate.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not select voice file: ${_cleanError(e)}');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recordingVoice) {
      try {
        final path = await _voiceRecorder.stop();
        if (path != null && mounted) {
          setState(() {
            _voiceFilePath = path;
            _voiceFileName = 'Recorded voice';
            _recordingVoice = false;
            _voiceMode = 'Record voice';
            _status = 'Voice recording saved. It will be uploaded securely when you generate.';
          });
        } else if (mounted) {
          setState(() => _recordingVoice = false);
        }
      } catch (e) {
        if (mounted) setState(() { _recordingVoice = false; _status = 'Could not stop recording: ${_cleanError(e)}'; });
      }
      return;
    }
    try {
      if (!await _voiceRecorder.hasPermission()) {
        setState(() => _status = 'Microphone permission is required to record your voice.');
        return;
      }
      final path = '${Directory.systemTemp.path}/novaryx_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (mounted) setState(() {
        _recordingVoice = true;
        _voiceMode = 'Record voice';
        _voiceFilePath = null;
        _voiceFileName = null;
        _status = 'Recording voice… tap Stop recording when finished.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not start recording: ${_cleanError(e)}');
    }
  }

  Future<String> _uploadVoiceAndGetUrl() async {
    final path = _voiceFilePath;
    final user = Supabase.instance.client.auth.currentUser;
    if (path == null || user == null) throw Exception('Select or record a voice sample and sign in first.');
    final file = File(path);
    if (!await file.exists()) throw Exception('The selected voice file is no longer available. Select it again.');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('The voice file is empty.');
    if (bytes.length > 25 * 1024 * 1024) throw Exception('Voice files must be 25 MB or smaller.');
    final ext = path.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final objectPath = '${user.id}/voice/${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'm4a' : ext}';
    final storage = Supabase.instance.client.storage.from('user-assets');
    await storage.uploadBinary(objectPath, bytes, fileOptions: const FileOptions(upsert: true));
    final signed = await storage.createSignedUrl(objectPath, 3600);
    return signed;
  }

  Future<void> _pickReferenceImage() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      if (picked == null || picked.files.single.path == null) return;
      setState(() {
        _referenceImagePath = picked.files.single.path;
        _referenceImageName = picked.files.single.name;
        _status = 'Reference image selected. It will upload when you generate.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not select image: ${_cleanError(e)}');
    }
  }

  Future<void> _pickReferenceVideo() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: false,
      );
      if (picked == null || picked.files.single.path == null) return;
      setState(() {
        _referenceVideoPath = picked.files.single.path;
        _referenceVideoName = picked.files.single.name;
        _status = 'Source video selected. It will upload when you generate.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not select video: ${_cleanError(e)}');
    }
  }

  Future<String> _uploadReferenceFile(String path, String mediaKind) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Sign in before uploading a reference file.');
    final file = File(path);
    if (!await file.exists()) throw Exception('The selected $mediaKind file is unavailable. Select it again.');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('The selected $mediaKind file is empty.');
    final maxBytes = mediaKind == 'video' ? 100 * 1024 * 1024 : 25 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw Exception('$mediaKind files must be ${mediaKind == 'video' ? '100 MB' : '25 MB'} or smaller.');
    }
    final extension = path.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final objectPath = '${user.id}/references/$mediaKind/${DateTime.now().millisecondsSinceEpoch}.${extension.isEmpty ? (mediaKind == 'video' ? 'mp4' : 'jpg') : extension}';
    final storage = Supabase.instance.client.storage.from('user-assets');
    await storage.uploadBinary(objectPath, bytes, fileOptions: const FileOptions(upsert: true));
    return storage.createSignedUrl(objectPath, 3600);
  }

  Future<void> _generate() async {
    final rawPrompt = _promptController.text.trim();
    if (rawPrompt.isEmpty || _working) return;
    final needsReferenceVideo = widget.kind == GenerationKind.video && _generationMode == 'Video to video';
    final needsReferenceImage = widget.kind != GenerationKind.music &&
        _generationMode != 'Text to image' &&
        _generationMode != 'Text to video' &&
        _generationMode != 'Video to video';
    if (needsReferenceVideo && _referenceVideoPath == null) {
      setState(() => _status = 'Choose a source video file for video-to-video generation.');
      return;
    }
    if (needsReferenceImage && _referenceImagePath == null) {
      setState(() => _status = 'Choose a reference image file for this generation mode.');
      return;
    }
    final ratioPrompt = widget.kind == GenerationKind.music ? '' : '\nAspect ratio: $_selectedRatio. Compose the scene for this frame shape; do not add borders or letterboxing.';
    if (widget.kind == GenerationKind.music && _voiceMode != 'AI voice' && _voiceFilePath == null) { setState(() => _status = 'Record or select a voice file first.'); return; }
    final prompt = 'Mode: ${widget.kind == GenerationKind.music ? _voiceMode : _generationMode}. Style: $_selectedStyle. ${_styleInstruction(widget.kind, _selectedStyle)}$ratioPrompt\n\nUser prompt: $rawPrompt${widget.kind == GenerationKind.music && _voiceMode == 'AI voice' ? '\nUse an AI-generated vocal performance if supported by the selected music model.' : widget.kind == GenerationKind.music ? '\nUse the supplied voice sample as the vocal reference if the selected music model supports audio input.' : ''}';
    setState(() {
      _working = true;
      _status = 'Submitting task to Kie.ai…';
      _resultUrl = null;
    });
    try {
      final model = await ProviderSettings.read(widget.kind.modelKey);
      if (model.isEmpty) throw Exception('Add a supported Kie.ai ${widget.kind.label.toLowerCase()} model ID in Settings.');
      if (Supabase.instance.client.auth.currentSession == null) {
        throw Exception('Sign in to your Supabase account in Settings before using AI services.');
      }
      final voiceUrl = widget.kind == GenerationKind.music && _voiceMode != 'AI voice' ? await _uploadVoiceAndGetUrl() : null;
      final referenceImageUrl = needsReferenceImage && _referenceImagePath != null
          ? await _uploadReferenceFile(_referenceImagePath!, 'image')
          : null;
      final referenceVideoUrl = needsReferenceVideo && _referenceVideoPath != null
          ? await _uploadReferenceFile(_referenceVideoPath!, 'video')
          : null;
      final createResponse = await Supabase.instance.client.functions
          .invoke('provider-gateway', body: {
            'action': 'kie-create',
            'generationKind': widget.kind.name,
            'model': model,
            'prompt': prompt,
            if (voiceUrl != null) 'audioUrl': voiceUrl,
            if (widget.kind == GenerationKind.image && _generationMode == 'Image to image' && referenceImageUrl != null) 'imageUrl': referenceImageUrl,
            if (widget.kind == GenerationKind.video && _generationMode == 'Image to video' && referenceImageUrl != null) 'imageUrl': referenceImageUrl,
            if (widget.kind == GenerationKind.video && _generationMode == 'Video to video' && referenceVideoUrl != null) 'videoUrl': referenceVideoUrl,
            if (widget.kind != GenerationKind.music) 'aspectRatio': _selectedRatio,
          })
          .timeout(const Duration(seconds: 60));
      final createBody = _decodeBody(jsonEncode(createResponse.data));
      if (createResponse.status < 200 || createResponse.status >= 300) {
        throw Exception(_errorFrom(createBody, createResponse.status));
      }
      final taskId = _findString(createBody, const ['taskId', 'task_id', 'id']);
      if (taskId == null) throw Exception('Kie.ai response did not contain a task ID: ${createResponse.data}');
      String? result;
      String lastState = 'queued';
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        final pollResponse = await Supabase.instance.client.functions
            .invoke('provider-gateway', body: {
              'action': 'kie-poll',
              'taskId': taskId,
            })
            .timeout(const Duration(seconds: 45));
        final pollBody = _decodeBody(jsonEncode(pollResponse.data));
        if (pollResponse.status < 200 || pollResponse.status >= 300) {
          throw Exception(_errorFrom(pollBody, pollResponse.status));
        }
        lastState = (_findString(pollBody, const ['state', 'status', 'taskStatus']) ?? 'processing').toLowerCase();
        result = _findResultUrl(pollBody);
        if (result != null) break;
        if (lastState.contains('fail') || lastState.contains('error')) {
          throw Exception(_findString(pollBody, const ['failMsg', 'error', 'message']) ?? 'Generation failed.');
        }
        if (mounted) setState(() => _status = 'Generation in progress… (${i + 1}/60)');
      }
      if (result == null) throw Exception('No result URL received yet. Last task state: $lastState. Check your Kie.ai task history.');
      try {
        await NovaryxCloudStore.archiveGeneratedMedia(
          kind: widget.kind.name,
          prompt: prompt,
          sourceUrl: result,
          model: model,
          provider: 'kie.ai',
          providerJobId: taskId,
        );
      } catch (_) {
        // Keep the successful generation visible even if archiving is temporarily unavailable.
      }
      await GenerationHistory.save(
        kind: widget.kind.label.toLowerCase(),
        prompt: prompt,
        resultUrl: result,
        model: model,
      );
      if (mounted) setState(() {
        _resultUrl = result;
        _status = 'Generation complete. Saved to History.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF064C75), Color(0xFF10215A), Color(0xFF34105D)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(kind.icon, size: 36, color: const Color(0xFF67EFFF)),
            const SizedBox(height: 16),
            Text('${kind.label} generation', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(kind.description, style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        if (kind != GenerationKind.music) ...[
          Text('Generation mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: (kind == GenerationKind.image
              ? const ['Text to image', 'Image to image']
              : const ['Text to video', 'Image to video', 'Video to video']).map((mode) => ChoiceChip(
            label: Text(mode),
            selected: _generationMode == mode,
            onSelected: _working ? null : (_) => setState(() => _generationMode = mode),
            selectedColor: const Color(0xFF123D72),
            side: BorderSide(color: _generationMode == mode ? const Color(0xFF00EFFF) : const Color(0xFF244A82)),
            labelStyle: TextStyle(color: _generationMode == mode ? const Color(0xFF00EFFF) : Colors.white70),
          )).toList()),
          if (_generationMode == 'Video to video') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _working ? null : _pickReferenceVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Choose source video'),
            ),
            if (_referenceVideoName != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.video_file_outlined, color: Color(0xFF00EFFF)),
                title: Text(_referenceVideoName!, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Remove selected video',
                  onPressed: _working ? null : () => setState(() { _referenceVideoPath = null; _referenceVideoName = null; }),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Text('Video files up to 100 MB. Upload happens securely when you generate.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ],
          if (_generationMode != 'Text to image' && _generationMode != 'Text to video' && _generationMode != 'Video to video') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _working ? null : _pickReferenceImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Choose reference image'),
            ),
            if (_referenceImageName != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined, color: Color(0xFF00EFFF)),
                title: Text(_referenceImageName!, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Remove selected image',
                  onPressed: _working ? null : () => setState(() { _referenceImagePath = null; _referenceImageName = null; }),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Text('Image files up to 25 MB. Upload happens securely when you generate.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ],
          const SizedBox(height: 22),
        ],
        if (kind != GenerationKind.music) ...[
          Text('Aspect ratio', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3', '21:9', '5:4'].map((ratio) => ChoiceChip(
              label: Text(ratio),
              selected: _selectedRatio == ratio,
              onSelected: _working ? null : (_) => setState(() => _selectedRatio = ratio),
              selectedColor: const Color(0xFF123D72),
              side: BorderSide(color: _selectedRatio == ratio ? const Color(0xFF00EFFF) : const Color(0xFF244A82)),
              labelStyle: TextStyle(color: _selectedRatio == ratio ? const Color(0xFF00EFFF) : Colors.white70),
            )).toList(),
          ),
          const SizedBox(height: 22),
        ],
        if (kind == GenerationKind.music) ...[
          Text('Vocal source', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: const ['AI voice', 'Record voice', 'Upload voice'].map((mode) => mode).map((mode) => ChoiceChip(
            label: Text(mode),
            selected: _voiceMode == mode,
            onSelected: _working || _recordingVoice ? null : (_) => setState(() => _voiceMode = mode),
            selectedColor: const Color(0xFF123D72),
            side: BorderSide(color: _voiceMode == mode ? const Color(0xFF00EFFF) : const Color(0xFF244A82)),
            labelStyle: TextStyle(color: _voiceMode == mode ? const Color(0xFF00EFFF) : Colors.white70),
          )).toList()),
          if (_voiceMode == 'Record voice') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working ? null : _toggleVoiceRecording,
              icon: Icon(_recordingVoice ? Icons.stop_circle_outlined : Icons.mic_none),
              label: Text(_recordingVoice ? 'Stop recording' : 'Record voice'),
            ),
          ],
          if (_voiceMode == 'Upload voice') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working ? null : _pickVoiceFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose audio file'),
            ),
          ],
          if (_voiceFileName != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.audio_file, color: Color(0xFF00EFFF), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_voiceFileName!, maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: _working ? null : () => setState(() { _voiceFilePath = null; _voiceFileName = null; }), icon: const Icon(Icons.close)),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 16),
            child: Text('Voice files are uploaded to your private Supabase storage. Voice-reference support depends on the Kie.ai music model you configure.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
        Text('Choose a style', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: _stylesFor(kind).map((style) => ChoiceChip(
          label: Text(style),
          selected: _selectedStyle == style,
          onSelected: _working ? null : (_) => setState(() => _selectedStyle = style),
          selectedColor: const Color(0xFF123D72),
          side: BorderSide(color: _selectedStyle == style ? const Color(0xFF00EFFF) : const Color(0xFF244A82)),
          labelStyle: TextStyle(color: _selectedStyle == style ? const Color(0xFF00EFFF) : Colors.white70),
        )).toList()),
        const SizedBox(height: 24),
        Text('Describe what you want', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        TextField(
          controller: _promptController,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: switch (kind) {
              GenerationKind.image => 'A cinematic futuristic city at night…',
              GenerationKind.music => 'Afrobeat instrumental, warm guitar, deep bass…',
              GenerationKind.video => 'A cinematic tracking shot of a futuristic city…',
            },
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _working ? null : _generate,
          icon: _working
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(_working ? 'Generating…' : 'Generate ${kind.label.toLowerCase()}'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF0A1230), borderRadius: BorderRadius.circular(14)),
            child: Text(_status),
          ),
        ],
        if (_resultUrl != null) ...[
          const SizedBox(height: 14),
          const Text('Result URL', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SelectableText(_resultUrl!, style: const TextStyle(color: Color(0xFFB9ABFF), decoration: TextDecoration.underline)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Long-press the result URL to select and copy it.')),
            ),
            icon: const Icon(Icons.link),
            label: const Text('View or copy result link'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _working ? null : _publishTemplate,
            icon: const Icon(Icons.publish_outlined),
            label: const Text('Post as template'),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Note: Kie.ai model IDs and input formats vary. Configure a model supported by your account. If a model requires extra input fields, its request format must be added to the app.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}



class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late Future<List<Map<String, dynamic>>> _templates;

  @override
  void initState() {
    super.initState();
    _templates = _loadTemplates();
  }

  Future<List<Map<String, dynamic>>> _loadTemplates() async {
    final rows = await Supabase.instance.client.from('community_templates')
        .select('id,title,description,kind,prompt,style,generation_mode,aspect_ratio,result_url,created_at')
        .order('created_at', ascending: false).limit(100);
    return (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _useTemplate(Map<String, dynamic> item) async {
    final kindName = item['kind']?.toString() ?? 'image';
    final kind = GenerationKind.values.firstWhere((k) => k.name == kindName, orElse: () => GenerationKind.image);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenerationScreen(
      kind: kind,
      initialPrompt: item['prompt']?.toString() ?? '',
      initialStyle: item['style']?.toString(),
      initialMode: item['generation_mode']?.toString(),
    )));
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => setState(() => _templates = _loadTemplates()),
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _templates,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Community templates are not available yet. Apply the Supabase migration community_templates.sql, then refresh.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => setState(() => _templates = _loadTemplates()), icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]);
        final items = snapshot.data ?? [];
        if (items.isEmpty) return ListView(padding: const EdgeInsets.all(24), children: const [
          Icon(Icons.dashboard_customize_outlined, size: 52, color: Color(0xFF00EFFF)),
          SizedBox(height: 14),
          Text('No templates yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Generate an image, video, or music track, then tap “Post as template” so others can reuse and edit your prompt.'),
        ]);
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Community Templates', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Use a template as-is or edit its prompt before generating.'),
          const SizedBox(height: 12),
          for (final item in items) Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(switch (item['kind']) { 'video' => Icons.movie_outlined, 'music' => Icons.music_note_outlined, _ => Icons.image_outlined }, color: const Color(0xFF00EFFF)),
                const SizedBox(width: 8),
                Expanded(child: Text(item['title']?.toString() ?? 'Untitled template', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                Text((item['kind']?.toString() ?? 'image').toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white60)),
              ]),
              if ((item['description']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(item['description'].toString())),
              const SizedBox(height: 8),
              Text(item['prompt']?.toString() ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text('Style: ${item['style'] ?? 'Cinematic'}  •  Mode: ${item['generation_mode'] ?? 'default'}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: () => _useTemplate(item), icon: const Icon(Icons.copy_all), label: const Text('Use template'))),
                if ((item['result_url']?.toString() ?? '').startsWith('http')) ...[
                  const SizedBox(width: 8),
                  IconButton(tooltip: 'Copy media URL', onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open the template to reuse its prompt; media URL is available in the original post.')));
                  }, icon: const Icon(Icons.link)),
                ],
              ]),
            ])),
          ),
        ]);
      },
    ),
  );
}


class GenerationHistory {
  static Future<void> save({
    required String kind,
    required String prompt,
    String? resultText,
    String? resultUrl,
    String? model,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await client.from('generation_history').insert({
        'user_id': user.id,
        'kind': kind,
        'prompt': prompt,
        'result_text': resultText,
        'result_url': resultUrl,
        'model': model,
      });
    } catch (_) {
      // History should never interrupt a successful generation.
    }
  }
}

class GenerationHistoryScreen extends StatefulWidget {
  const GenerationHistoryScreen({super.key});

  @override
  State<GenerationHistoryScreen> createState() => _GenerationHistoryScreenState();
}

class _GenerationHistoryScreenState extends State<GenerationHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return [];
    final rows = await client
        .from('generation_history')
        .select('id,kind,prompt,result_text,result_url,model,created_at')
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  void _refresh() {
    setState(() => _history = _loadHistory());
  }

  Future<void> _delete(String id) async {
    try {
      await Supabase.instance.client
          .from('generation_history')
          .delete()
          .eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History item deleted.')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete item: ${_cleanError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Supabase.instance.client.auth.currentUser == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sign in from Settings to save and view your generation history.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 100),
                const Icon(Icons.cloud_off, size: 42),
                const SizedBox(height: 12),
                const Center(child: Text('Could not load history.')),
                const SizedBox(height: 8),
                Center(child: Text(
                  'Apply the Supabase SQL migration in the repository, then try again.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60),
                )),
                Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
              ],
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.history, size: 52, color: Color(0xFFAC9AFF)),
                SizedBox(height: 16),
                Center(child: Text('No generation history yet.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                SizedBox(height: 8),
                Center(child: Text('Your successful chats, images, music, and videos will appear here.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final kind = (item['kind'] ?? 'generation').toString();
              final prompt = (item['prompt'] ?? '').toString();
              final resultText = (item['result_text'] ?? '').toString();
              final resultUrl = (item['result_url'] ?? '').toString();
              final created = DateTime.tryParse((item['created_at'] ?? '').toString())?.toLocal();
              final dateLabel = created == null ? '' :
                  '${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
              final icon = switch (kind) {
                'chat' => Icons.chat_bubble_outline,
                'image' => Icons.image_outlined,
                'music' => Icons.music_note_outlined,
                'video' => Icons.movie_outlined,
                _ => Icons.auto_awesome,
              };
              return Card(
                color: const Color(0xFF171A2B),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(icon, color: const Color(0xFF00EFFF)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(kind.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      IconButton(
                        tooltip: 'Delete history item',
                        onPressed: () => _delete(item['id'].toString()),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ]),
                    if (dateLabel.isNotEmpty)
                      Text(dateLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(prompt, maxLines: 4, overflow: TextOverflow.ellipsis),
                    if (resultText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('Response', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      SelectableText(resultText),
                    ],
                    if (resultUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('Result link', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      SelectableText(resultUrl,
                          style: const TextStyle(color: Color(0xFFB9ABFF), decoration: TextDecoration.underline)),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Map<String, dynamic> _decodeBody(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  } catch (_) {
    return {'raw': source};
  }
}

String _errorFrom(Map<String, dynamic> body, int status) {
  final error = body['error'];
  if (error is Map) {
    return error['message']?.toString() ?? 'Request failed (HTTP $status).';
  }
  return body['message']?.toString() ?? body['msg']?.toString() ?? 'Request failed (HTTP $status).';
}

String? _findString(dynamic value, List<String> keys) {
  if (value is Map) {
    for (final key in keys) {
      final candidate = value[key];
      if (candidate is String && candidate.isNotEmpty) return candidate;
      if (candidate is num) return candidate.toString();
    }
    for (final nested in value.values) {
      final found = _findString(nested, keys);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final nested in value) {
      final found = _findString(nested, keys);
      if (found != null) return found;
    }
  } else if (value is String && (value.startsWith('{') || value.startsWith('['))) {
    try {
      return _findString(jsonDecode(value), keys);
    } catch (_) {}
  }
  return null;
}

String? _findResultUrl(dynamic value) {
  if (value is Map) {
    for (final key in const ['resultUrls', 'resultUrl', 'videoUrl', 'imageUrl', 'audioUrl', 'url', 'outputUrl']) {
      final candidate = value[key];
      if (candidate is String && candidate.startsWith('http')) return candidate;
      if (candidate is List) {
        for (final item in candidate) {
          if (item is String && item.startsWith('http')) return item;
          if (item is Map) {
            final found = _findResultUrl(item);
            if (found != null) return found;
          }
        }
      }
    }
    for (final nested in value.values) {
      final found = _findResultUrl(nested);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final nested in value) {
      final found = _findResultUrl(nested);
      if (found != null) return found;
    }
  } else if (value is String && (value.startsWith('{') || value.startsWith('['))) {
    try {
      return _findResultUrl(jsonDecode(value));
    } catch (_) {}
  }
  return null;
}

String _cleanError(Object error) {
  return error.toString().replaceFirst(RegExp(r'^Exception: '), '');
}
