/// The key fields every dialog asking for a container key shares.
///
/// Creating an encrypted container, opening one and converting to one all ask
/// the same thing the same way: a passphrase, a key file, or both, and
/// whether to remember it for this file. One widget, so a key file can be
/// chosen wherever a passphrase can be typed, and "remember" means the same
/// per-file key everywhere.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tom_core_storage/settings.dart';

/// What a key prompt or a key step collected.
class TomKeyRequest {
  final TomKeyMaterial material;

  /// The "remember for this file" checkbox — keep it as this file's key.
  final bool remember;

  const TomKeyRequest({required this.material, required this.remember});
}

/// A key file the host read for a key dialog.
class TomKeyFile {
  /// Where it lives (a storage locator, a path on the desktop). A remembered
  /// key stores this, not the bytes, and reads it again next session.
  final String locator;

  final Uint8List bytes;

  const TomKeyFile({required this.locator, required this.bytes});

  /// The file's own name, for the field that shows it.
  String get name {
    final cut = locator.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? locator : locator.substring(cut + 1);
  }
}

/// The host's file picker for a key file.
///
/// Implemented by an application that can reach a local file — through the
/// platform's file dialog on the desktop. Without a picker the key-file row
/// is not shown.
abstract interface class TomKeyFilePicker {
  /// The chosen key file, read, or null when the user chose none.
  Future<TomKeyFile?> pickKeyFile(BuildContext context);
}

/// The state behind [TomKeyFields] and [TomKeyStep].
///
/// A controller rather than widget state, because the dialog that hosts the
/// fields owns the confirm button: it has to know whether the key is complete
/// ([ready]) and read it ([request]) when it is pressed.
class TomKeyStepController extends ChangeNotifier {
  /// Whether the default key can be chosen. A key step offers it and
  /// preselects it when there is one; the key prompt never does — it is shown
  /// because the default key did not open the file.
  final bool hasDefaultKey;

  late bool _useDefault = hasDefaultKey;
  final TextEditingController passphrase = TextEditingController();
  TomKeyFile? _keyFile;
  bool _remember = true;

  TomKeyStepController({this.hasDefaultKey = false}) {
    passphrase.addListener(notifyListeners);
  }

  bool get useDefault => _useDefault;
  set useDefault(bool value) {
    if (value && !hasDefaultKey) return;
    _useDefault = value;
    notifyListeners();
  }

  TomKeyFile? get keyFile => _keyFile;
  set keyFile(TomKeyFile? value) {
    _keyFile = value;
    notifyListeners();
  }

  bool get remember => _remember;
  set remember(bool value) {
    _remember = value;
    notifyListeners();
  }

  /// Whether [repeat] is what was typed as the passphrase — the check a
  /// dialog that asks for it twice makes. Answered here, against the typed
  /// text, so no surface has to read the material's secret to ask it. An empty
  /// passphrase matches anything: there is nothing to repeat.
  bool repeatMatches(String repeat) =>
      passphrase.text.isEmpty || passphrase.text == repeat;

  /// The key typed and chosen, whether or not it is complete.
  TomKeyMaterial get material => TomKeyMaterial(
    passphrase: passphrase.text.isEmpty ? null : passphrase.text,
    keyFileBytes: _keyFile?.bytes,
    keyFileLocator: _keyFile?.locator,
  );

  /// Whether the dialog may go on: the default key, or material that opens
  /// something — a passphrase, a key file, or both.
  bool get ready => _useDefault || material.isResolvable;

  /// The file's own key, or null for the default key.
  TomKeyRequest? get request => _useDefault
      ? null
      : TomKeyRequest(material: material, remember: _remember);

  @override
  void dispose() {
    passphrase.dispose();
    super.dispose();
  }
}

/// A key of this file's own: passphrase, key file, remember.
///
/// Widget keys are `<keyPrefix>-passphrase`, `<keyPrefix>-keyfile` (choose),
/// `<keyPrefix>-keyfile-name`, `<keyPrefix>-keyfile-clear` and
/// `<keyPrefix>-remember`.
class TomKeyFields extends StatefulWidget {
  final TomKeyStepController controller;
  final String keyPrefix;

  /// The host's picker; the key-file row is shown only with one.
  final TomKeyFilePicker? keyFiles;

  /// Runs the host's picker. A dialog's own context sits above whatever the
  /// application installed below its root, so the picker is handed the
  /// context the dialog was opened from.
  final BuildContext? pickerContext;

  /// Whether the "Remember for this file" row is shown. A settings editor
  /// leaves it out: what it sets is kept by definition, so the question would
  /// have one answer.
  final bool offersRemember;

  final bool autofocus;
  final VoidCallback? onSubmitted;

  const TomKeyFields({
    super.key,
    required this.controller,
    required this.keyPrefix,
    this.keyFiles,
    this.pickerContext,
    this.offersRemember = true,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  State<TomKeyFields> createState() => _TomKeyFieldsState();
}

class _TomKeyFieldsState extends State<TomKeyFields> {
  bool _obscure = true;

  Future<void> _chooseKeyFile() async {
    final picker = widget.keyFiles;
    if (picker == null) return;
    final pickerContext = widget.pickerContext ?? context;
    final file = await picker.pickKeyFile(pickerContext);
    if (file == null || !mounted) return;
    widget.controller.keyFile = file;
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.keyPrefix;
    final small = Theme.of(context).textTheme.bodySmall;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final keyFile = widget.controller.keyFile;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: Key('$prefix-passphrase'),
              controller: widget.controller.passphrase,
              obscureText: _obscure,
              autofocus: widget.autofocus,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show passphrase' : 'Hide passphrase',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => widget.onSubmitted?.call(),
            ),
            if (widget.keyFiles != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Text(
                      'Key file',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        keyFile?.name ?? 'none',
                        key: Key('$prefix-keyfile-name'),
                        style: small,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (keyFile != null)
                      IconButton(
                        key: Key('$prefix-keyfile-clear'),
                        tooltip: 'Use no key file',
                        icon: const Icon(Icons.close),
                        onPressed: () => widget.controller.keyFile = null,
                      ),
                    TextButton(
                      key: Key('$prefix-keyfile'),
                      onPressed: _chooseKeyFile,
                      child: const Text('Choose…'),
                    ),
                  ],
                ),
              ),
            if (widget.offersRemember)
              CheckboxListTile(
                key: Key('$prefix-remember'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: widget.controller.remember,
                onChanged: (v) => widget.controller.remember = v ?? false,
                title: const Text('Remember for this file'),
                subtitle: const Text(
                  'Kept as a per-file key in your settings.',
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The key step of creating or converting an encrypted container: the
/// default key, or a key for this file only ([TomKeyFields]).
///
/// Widget keys are `<keyPrefix>-key-default` and `<keyPrefix>-key-own`, plus
/// those of [TomKeyFields].
class TomKeyStep extends StatelessWidget {
  final TomKeyStepController controller;
  final String keyPrefix;
  final TomKeyFilePicker? keyFiles;
  final BuildContext? pickerContext;

  /// What the default key is called — "My default document key".
  final String defaultKeyLabel;

  /// What is said when there is no default key.
  final String noDefaultKeyLabel;

  const TomKeyStep({
    super.key,
    required this.controller,
    required this.keyPrefix,
    this.keyFiles,
    this.pickerContext,
    this.defaultKeyLabel = 'My default key',
    this.noDefaultKeyLabel = 'No default key is set.',
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('Key', style: Theme.of(context).textTheme.labelMedium),
        RadioGroup<bool>(
          groupValue: controller.useDefault,
          onChanged: (v) => controller.useDefault = v!,
          child: Column(
            children: [
              RadioListTile<bool>(
                key: Key('$keyPrefix-key-default'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: true,
                enabled: controller.hasDefaultKey,
                title: Text(defaultKeyLabel),
                subtitle: controller.hasDefaultKey
                    ? null
                    : Text(noDefaultKeyLabel),
              ),
              RadioListTile<bool>(
                key: Key('$keyPrefix-key-own'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: false,
                title: const Text('A key for this file only'),
              ),
            ],
          ),
        ),
        if (!controller.useDefault)
          TomKeyFields(
            controller: controller,
            keyPrefix: keyPrefix,
            keyFiles: keyFiles,
            pickerContext: pickerContext,
          ),
      ],
    ),
  );
}
