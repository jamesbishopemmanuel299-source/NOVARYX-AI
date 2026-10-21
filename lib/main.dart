import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const String defaultSupabaseUrl = 'https://vihbsfrwnslnmheowkhy.supabase.co';
const String defaultSupabasePublishableKey = 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: defaultSupabaseUrl,
    anonKey: defaultSupabasePublishableKey,
  );
  runApp(const NovaryxApp());
}

class NovaryxApp extends StatelessWidget {
  const NovaryxApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C5CFF);
    return MaterialApp(
      title: 'NOVARYX-AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF121426),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0D19),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const HomeScreen(),
    );
  }
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
      final key = await ProviderSettings.read(ProviderSettings.groqKey);
      final model = await ProviderSettings.read(
        ProviderSettings.groqModel,
        fallback: 'llama-3.3-70b-versatile',
      );
      if (key.isEmpty) {
        throw Exception('Add your Groq API key in Settings first.');
      }
      final history = _messages
          .map((m) => <String, dynamic>{'role': m.role, 'content': m.text})
          .toList();
      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': history,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 90));
      final body = _decodeBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_errorFrom(body, response.statusCode));
      }
      final choices = body['choices'];
      final answer = choices is List && choices.isNotEmpty
          ? (choices.first['message']?['content']?.toString() ?? '')
          : '';
      if (answer.isEmpty) throw Exception('The provider returned an empty answer.');
      if (mounted) setState(() => _messages.add(ChatMessage(role: 'assistant', text: answer)));
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
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFAC9AFF)),
            SizedBox(width: 10),
            Text('NOVARYX-AI', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
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
                          color: isUser ? const Color(0xFF5140A8) : const Color(0xFF1A1D31),
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
                      fillColor: const Color(0xFF171A2B),
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

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key, required this.kind});
  final GenerationKind kind;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final _promptController = TextEditingController();
  bool _working = false;
  String _status = '';
  String? _resultUrl;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _working) return;
    setState(() {
      _working = true;
      _status = 'Submitting task to Kie.ai…';
      _resultUrl = null;
    });
    try {
      final key = await ProviderSettings.read(ProviderSettings.kieKey);
      final model = await ProviderSettings.read(widget.kind.modelKey);
      if (key.isEmpty) throw Exception('Add your Kie.ai API key in Settings first.');
      if (model.isEmpty) throw Exception('Add a supported Kie.ai ${widget.kind.label.toLowerCase()} model ID in Settings.');
      final createResponse = await http.post(
        Uri.parse('https://api.kie.ai/api/v1/jobs/createTask'),
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'input': {'prompt': prompt}}),
      ).timeout(const Duration(seconds: 60));
      final createBody = _decodeBody(createResponse.body);
      if (createResponse.statusCode < 200 || createResponse.statusCode >= 300) {
        throw Exception(_errorFrom(createBody, createResponse.statusCode));
      }
      final taskId = _findString(createBody, const ['taskId', 'task_id', 'id']);
      if (taskId == null) throw Exception('Kie.ai response did not contain a task ID: ${createResponse.body}');
      String? result;
      String lastState = 'queued';
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        final pollResponse = await http.get(
          Uri.parse('https://api.kie.ai/api/v1/jobs/recordInfo?taskId=${Uri.encodeQueryComponent(taskId)}'),
          headers: {'Authorization': 'Bearer $key'},
        ).timeout(const Duration(seconds: 45));
        final pollBody = _decodeBody(pollResponse.body);
        if (pollResponse.statusCode < 200 || pollResponse.statusCode >= 300) {
          throw Exception(_errorFrom(pollBody, pollResponse.statusCode));
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
      if (mounted) setState(() {
        _resultUrl = result;
        _status = 'Generation complete. Open the result link below.';
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
            gradient: const LinearGradient(colors: [Color(0xFF342568), Color(0xFF171A32)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(kind.icon, size: 36, color: const Color(0xFFC4B6FF)),
            const SizedBox(height: 16),
            Text('${kind.label} generation', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(kind.description, style: const TextStyle(color: Colors.white70)),
          ]),
        ),
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
            decoration: BoxDecoration(color: const Color(0xFF171A2B), borderRadius: BorderRadius.circular(14)),
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  bool _saving = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _authStatus = '';
  bool _authWorking = false;

  static const _fields = <(String, String, bool, String)>[
    (ProviderSettings.groqKey, 'Groq API key', true, ''),
    (ProviderSettings.groqModel, 'Groq chat model', false, 'llama-3.3-70b-versatile'),
    (ProviderSettings.kieKey, 'Kie.ai API key', true, ''),
    (ProviderSettings.imageModel, 'Kie.ai image model ID', false, ''),
    (ProviderSettings.musicModel, 'Kie.ai music model ID', false, ''),
    (ProviderSettings.videoModel, 'Kie.ai video model ID', false, ''),
    (ProviderSettings.supabaseUrl, 'Supabase Project URL', false, ''),
    (ProviderSettings.supabaseAnonKey, 'Supabase anon/public key', true, ''),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final field in _fields) {
      final defaultValue = field.$1 == ProviderSettings.supabaseUrl
          ? defaultSupabaseUrl
          : field.$1 == ProviderSettings.supabaseAnonKey
              ? defaultSupabasePublishableKey
              : field.$4;
      final value = await ProviderSettings.read(field.$1, fallback: defaultValue);
      _controllers[field.$1] = TextEditingController(text: value);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connectSupabase() async {
    setState(() { _authWorking = true; _authStatus = 'Connecting to Supabase…'; });
    try {
      await ProviderSettings.connectSupabase(
        _controllers[ProviderSettings.supabaseUrl]?.text ?? '',
        _controllers[ProviderSettings.supabaseAnonKey]?.text ?? '',
      );
      if (mounted) setState(() => _authStatus = 'Supabase connected. You can now create an account or sign in.');
    } catch (e) {
      if (mounted) setState(() => _authStatus = 'Connection failed: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _authWorking = false);
    }
  }

  Future<void> _authenticate({required bool signUp}) async {
    final client = ProviderSettings.supabase;
    if (client == null) {
      setState(() => _authStatus = 'Connect Supabase first.');
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _authStatus = 'Enter a valid email and a password with at least 6 characters.');
      return;
    }
    setState(() { _authWorking = true; _authStatus = signUp ? 'Creating account…' : 'Signing in…'; });
    try {
      if (signUp) {
        final result = await client.auth.signUp(email: email, password: password);
        if (mounted) setState(() => _authStatus = result.session == null
            ? 'Account request sent. Check your email if confirmation is enabled.'
            : 'Account created and signed in.');
      } else {
        await client.auth.signInWithPassword(email: email, password: password);
        if (mounted) setState(() => _authStatus = 'Signed in as ${client.auth.currentUser?.email ?? email}.');
      }
    } catch (e) {
      if (mounted) setState(() => _authStatus = 'Authentication failed: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _authWorking = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ProviderSettings.supabase?.auth.signOut();
      if (mounted) setState(() => _authStatus = 'Signed out.');
    } catch (e) {
      if (mounted) setState(() => _authStatus = 'Sign-out failed: ${_cleanError(e)}');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final field in _fields) {
        await ProviderSettings.write(field.$1, _controllers[field.$1]?.text ?? '');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved securely on this device.')));
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provider settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text('Connect your AI providers', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Keys are stored in Android secure storage on this device. Do not share your keys or commit them to GitHub.',
                  style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 22),
                for (final field in _fields) ...[
                  Text(field.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _controllers[field.$1],
                    obscureText: field.$3,
                    autocorrect: false,
                    enableSuggestions: !field.$3,
                    decoration: InputDecoration(
                      hintText: field.$4.isEmpty ? 'Paste your key' : field.$4,
                      suffixIcon: field.$3 ? const Icon(Icons.lock_outline) : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: _authWorking ? null : _connectSupabase,
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_authWorking ? 'Connecting…' : 'Connect Supabase')),
                ),
                const SizedBox(height: 10),
                const Divider(height: 28),
                const Text('Supabase account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Current user: ${ProviderSettings.supabase?.auth.currentUser?.email ?? 'Not signed in'}', style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 12),
                TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password (minimum 6 characters)')),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton(onPressed: _authWorking ? null : () => _authenticate(signUp: true), child: const Text('Create account')),
                  OutlinedButton(onPressed: _authWorking ? null : () => _authenticate(signUp: false), child: const Text('Sign in')),
                  TextButton(onPressed: _authWorking ? null : _signOut, child: const Text('Sign out')),
                ]),
                if (_authStatus.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SelectableText(_authStatus, style: const TextStyle(color: Color(0xFFC4B6FF))),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_saving ? 'Saving…' : 'Save settings'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Security: storing keys on a device does not make them impossible to extract from a distributed app. For a public app, move provider calls to an authenticated backend with rate limits.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
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
