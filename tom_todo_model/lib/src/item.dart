/// The single item model: one record for whatever can have a status, a
/// reminder or a repetition — a workspace todo, a reminder, a journal entry, a
/// mindmap node, an email, a document section (D1 §3, D2 §2.1 of the Webwork
/// specifications).
///
/// Every item has the same **base fields**, the todo fields among them, so any
/// item can be a todo and any item can ring. What an item *is* in the areas is
/// its item types ([TomItemType]): `todo` and `reminder` are stored, the
/// others are computed from its memberships and extensions ([TomItem.types]).
/// Fields only one use needs live in the four **extensions** — [container],
/// [people], [mail], [workflow] — each present only when used.
///
/// `*.todo.yaml` files hold items in their flat form ([TomItem.toMap],
/// [TomItem.fromMap], [TomItem.fields]): the todo schema's keys, `title` for
/// [TomItem.headline] and `references` for the external links.
library;

import 'todo.dart';
import 'todo_repeat.dart';

/// What an item is in the areas (D1 §3.1 field 2).
///
/// The **stored** types are the user's choice and are written into the
/// files ([TomItem.itemTypes]); the **computed** ones are facts about the
/// item, answered by [TomItem.types] from what they are computed from and
/// never written.
enum TomItemType {
  /// Stored: listed in Todos.
  todo('todo', stored: true),

  /// Stored: listed in Reminders.
  reminder('reminder', stored: true),

  /// Computed: the item is a member of a journal.
  journalEntry('journal-entry', stored: false),

  /// Computed: the item is at home in or a member of a mindmap.
  mindmapNode('mindmap-node', stored: false),

  /// Computed: the item has the [TomItem.mail] extension.
  email('email', stored: false);

  const TomItemType(this.wire, {required this.stored});

  /// The name in the files and the specifications.
  final String wire;

  /// True for `todo` and `reminder`, the types written into the files.
  final bool stored;

  /// True for the types answered from memberships and extensions.
  bool get computed => !stored;

  /// The type [value] names, or null for a name this version does not know
  /// (a later format's type, kept verbatim in [TomItem.itemTypes]).
  static TomItemType? tryWire(String value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// The kind of a container an item lives in or belongs to — what the
/// computed item types are read from.
enum TomContainerKind { list, journal, mindmap, smartlist, document, other }

/// What [TomItem.types] needs to know beyond the record: a membership names
/// its container by reference only, so the kind of each container comes from
/// whoever reads the item (the index, a store).
class TomItemTypeContext {
  const TomItemTypeContext({this.home, this.kindOf, this.listedIn = const []});

  /// The kind of the container the item is at home in, when known.
  final TomContainerKind? home;

  /// The kind of the container a membership reference names; null when not
  /// known.
  final TomContainerKind? Function(String ref)? kindOf;

  /// The kinds of the containers that list the item in their own `members`
  /// (D1 §3.8: where the item's home cannot hold memberships).
  final Iterable<TomContainerKind> listedIn;
}

/// When an item rings (D1 §3.5.1): exactly one of [at] and [before]. Every
/// value is kept as written.
class TomItemReminder {
  TomItemReminder({
    this.at,
    this.before,
    this.time,
    this.snoozedUntil,
    this.acknowledged,
  }) {
    if ((at == null) == (before == null)) {
      throw const FormatException(
        'A reminder has exactly one of "at" and "before"',
      );
    }
    if (time != null && before == null) {
      throw const FormatException('A reminder\'s "time" goes with "before"');
    }
  }

  /// An absolute instant with its offset (`2026-11-20T09:00+01:00`).
  final String? at;

  /// An ISO-8601 duration before `due` at [time].
  final String? before;

  /// `HH:MM` on the `due` day; with [before] only.
  final String? time;

  final String? snoozedUntil;
  final String? acknowledged;

  static const List<String> fields = [
    'at',
    'before',
    'time',
    'snoozed_until',
    'acknowledged',
  ];

  Map<String, Object?> toMap() => {
    if (at != null) 'at': at,
    if (before != null) 'before': before,
    if (time != null) 'time': time,
    if (snoozedUntil != null) 'snoozed_until': snoozedUntil,
    if (acknowledged != null) 'acknowledged': acknowledged,
  };

  static TomItemReminder fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'reminder');
    return TomItemReminder(
      at: map['at']?.toString(),
      before: map['before']?.toString(),
      time: map['time']?.toString(),
      snoozedUntil: map['snoozed_until']?.toString(),
      acknowledged: map['acknowledged']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TomItemReminder && _deepEquals(other.toMap(), toMap());

  @override
  int get hashCode => Object.hash(at, before, time);
}

/// An email address or messaging handle, with an optional display name and
/// contact reference (D1 §3.5.4).
class TomItemAddress {
  const TomItemAddress({required this.address, this.name, this.contact});

  final String address;
  final String? name;

  /// `[<contacts document>]#<UID>`, when the contact is known.
  final String? contact;

  static const List<String> fields = ['address', 'name', 'contact'];

  Map<String, Object?> toMap() => {
    'address': address,
    if (name != null) 'name': name,
    if (contact != null) 'contact': contact,
  };

  static TomItemAddress fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'address');
    final address = map['address'];
    if (address == null) {
      throw const FormatException('An address needs "address"');
    }
    return TomItemAddress(
      address: '$address',
      name: map['name']?.toString(),
      contact: map['contact']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TomItemAddress &&
      other.address == address &&
      other.name == name &&
      other.contact == contact;

  @override
  int get hashCode => Object.hash(address, name, contact);
}

/// A list, journal or mindmap the item appears in besides its home (D1 §3.8).
class TomItemMembership {
  const TomItemMembership({required this.ref, this.order});

  /// `[<document>]#<id>` on the item; an item reference on a container.
  final String ref;

  /// The order key, compared as a string (a journal's entry date).
  final String? order;

  static const List<String> fields = [r'$ref', 'order'];

  Map<String, Object?> toMap() => {r'$ref': ref, 'order': ?order};

  static TomItemMembership fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'membership');
    final ref = map[r'$ref'];
    if (ref == null) throw const FormatException(r'A membership needs "$ref"');
    return TomItemMembership(ref: '$ref', order: map['order']?.toString());
  }

  @override
  bool operator ==(Object other) =>
      other is TomItemMembership && other.ref == ref && other.order == order;

  @override
  int get hashCode => Object.hash(ref, order);
}

/// A cross reference to another item that is not structure (D1 §3.5.3).
class TomItemRelated {
  const TomItemRelated({required this.ref, this.label});

  final String ref;
  final String? label;

  static const List<String> fields = [r'$ref', 'label'];

  Map<String, Object?> toMap() => {r'$ref': ref, 'label': ?label};

  static TomItemRelated fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'related link');
    final ref = map[r'$ref'];
    if (ref == null) {
      throw const FormatException(r'A related link needs "$ref"');
    }
    return TomItemRelated(ref: '$ref', label: map['label']?.toString());
  }

  @override
  bool operator ==(Object other) =>
      other is TomItemRelated && other.ref == ref && other.label == label;

  @override
  int get hashCode => Object.hash(ref, label);
}

/// External links and related items (D1 §3.5.3). [external] is the workspace
/// todo schema's `references`.
class TomItemLinks {
  TomItemLinks({
    List<TomTodoReference> external = const [],
    List<TomItemRelated> related = const [],
  }) : external = List.of(external),
       related = List.of(related);

  List<TomTodoReference> external;
  List<TomItemRelated> related;

  static const List<String> fields = ['external', 'related'];

  bool get isEmpty => external.isEmpty && related.isEmpty;

  TomItemLinks copy() => TomItemLinks(external: external, related: related);
}

/// One entry of [TomItemContainer.children] (D1 §3.2): a reference slot or an
/// inline item.
sealed class TomItemChild {
  const TomItemChild();

  Map<String, Object?> toMap();

  TomItemChild copy();

  static TomItemChild fromMap(Map<dynamic, dynamic> map) {
    final hasRef = map.containsKey(r'$ref');
    final hasId = map.containsKey('id');
    if (hasRef == hasId) {
      throw const FormatException(
        r'A child is either a slot ("$ref") or an inline item ("id")',
      );
    }
    return hasRef
        ? TomItemSlot.fromMap(map)
        : TomItemInline(TomItem.fromMap(map));
  }
}

/// A child reference slot: `{$ref, embedded, alias}`.
class TomItemSlot extends TomItemChild {
  const TomItemSlot({required this.ref, this.embedded = false, this.alias});

  final String ref;
  final bool embedded;
  final String? alias;

  static const List<String> fields = [r'$ref', 'embedded', 'alias'];

  @override
  Map<String, Object?> toMap() => {
    r'$ref': ref,
    if (embedded) 'embedded': true,
    'alias': ?alias,
  };

  @override
  TomItemSlot copy() => this;

  static TomItemSlot fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'child slot');
    return TomItemSlot(
      ref: '${map[r'$ref']}',
      embedded: _flag(map['embedded'], 'embedded'),
      alias: map['alias']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TomItemSlot &&
      other.ref == ref &&
      other.embedded == embedded &&
      other.alias == alias;

  @override
  int get hashCode => Object.hash(ref, embedded, alias);
}

/// A light item at home in its container, inline in its `children`.
class TomItemInline extends TomItemChild {
  const TomItemInline(this.item);

  final TomItem item;

  @override
  Map<String, Object?> toMap() => item.toMap();

  @override
  TomItemInline copy() => TomItemInline(item.copy());

  @override
  bool operator ==(Object other) =>
      other is TomItemInline && other.item == item;

  @override
  int get hashCode => item.hashCode;
}

/// The container extension: ordered children (D1 §3.2).
class TomItemContainer {
  TomItemContainer({List<TomItemChild> children = const []})
    : children = List.of(children);

  List<TomItemChild> children;

  static const List<String> fields = ['children'];

  bool get isEmpty => children.isEmpty;

  TomItemContainer copy() =>
      TomItemContainer(children: [for (final c in children) c.copy()]);
}

/// The people extension: `from`, `to`, `cc`, `bcc` (D1 §3.5.4).
class TomItemPeople {
  TomItemPeople({
    this.from,
    List<TomItemAddress> to = const [],
    List<TomItemAddress> cc = const [],
    List<TomItemAddress> bcc = const [],
  }) : to = List.of(to),
       cc = List.of(cc),
       bcc = List.of(bcc);

  TomItemAddress? from;
  List<TomItemAddress> to;
  List<TomItemAddress> cc;
  List<TomItemAddress> bcc;

  static const List<String> fields = ['from', 'to', 'cc', 'bcc'];

  bool get isEmpty => from == null && to.isEmpty && cc.isEmpty && bcc.isEmpty;

  TomItemPeople copy() => TomItemPeople(from: from, to: to, cc: cc, bcc: bcc);

  Map<String, Object?> toMap() => {
    if (from != null) 'from': from!.toMap(),
    if (to.isNotEmpty) 'to': [for (final a in to) a.toMap()],
    if (cc.isNotEmpty) 'cc': [for (final a in cc) a.toMap()],
    if (bcc.isNotEmpty) 'bcc': [for (final a in bcc) a.toMap()],
  };

  static TomItemPeople fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'people');
    List<TomItemAddress> list(String key) => [
      for (final a in (map[key] as List? ?? const []))
        TomItemAddress.fromMap(a as Map),
    ];
    return TomItemPeople(
      from: map['from'] == null
          ? null
          : TomItemAddress.fromMap(map['from'] as Map),
      to: list('to'),
      cc: list('cc'),
      bcc: list('bcc'),
    );
  }
}

/// The mail extension (D1 §3.5.5). An item with it is an email. Every value
/// is kept as written.
class TomItemMail {
  TomItemMail({
    this.messageId,
    this.threadId,
    this.inReplyTo,
    List<String> mailReferences = const [],
    this.sent,
    this.received,
    this.mailbox,
    List<String> mailFlags = const [],
  }) : mailReferences = List.of(mailReferences),
       mailFlags = List.of(mailFlags);

  String? messageId;
  String? threadId;
  String? inReplyTo;
  List<String> mailReferences;
  String? sent;
  String? received;
  String? mailbox;
  List<String> mailFlags;

  static const List<String> fields = [
    'message_id',
    'thread_id',
    'in_reply_to',
    'mail_references',
    'sent',
    'received',
    'mailbox',
    'mail_flags',
  ];

  bool get isEmpty => toMap().isEmpty;

  TomItemMail copy() => TomItemMail(
    messageId: messageId,
    threadId: threadId,
    inReplyTo: inReplyTo,
    mailReferences: mailReferences,
    sent: sent,
    received: received,
    mailbox: mailbox,
    mailFlags: mailFlags,
  );

  Map<String, Object?> toMap() => {
    'message_id': ?messageId,
    'thread_id': ?threadId,
    'in_reply_to': ?inReplyTo,
    if (mailReferences.isNotEmpty) 'mail_references': List.of(mailReferences),
    'sent': ?sent,
    'received': ?received,
    'mailbox': ?mailbox,
    if (mailFlags.isNotEmpty) 'mail_flags': List.of(mailFlags),
  };

  static TomItemMail fromMap(Map<dynamic, dynamic> map) {
    _known(map, fields, 'mail');
    return TomItemMail(
      messageId: map['message_id']?.toString(),
      threadId: map['thread_id']?.toString(),
      inReplyTo: map['in_reply_to']?.toString(),
      mailReferences: _strings(map['mail_references']),
      sent: map['sent']?.toString(),
      received: map['received']?.toString(),
      mailbox: map['mailbox']?.toString(),
      mailFlags: _strings(map['mail_flags']),
    );
  }
}

/// The quest workflow extension (D1 §3.5.6): the fields the workspace's quest
/// tooling keeps on a todo and no other use has, with the workspace todo
/// schema's names and shapes.
class TomItemWorkflow {
  TomItemWorkflow({
    List<TomTodoDecision> decisions = const [],
    this.userAction = false,
    this.scope,
    this.executionRole,
    this.qaRole,
    this.orchestrationRole,
    this.bundleId,
    this.role,
    Map<String, List<String>> guidelines = const {},
    this.derivedFrom,
    this.feedbackSource,
    this.filedBy,
    this.onDone,
    this.lastAnswer,
    List<String>? resources,
    this.claimHold = false,
    this.claimFree = false,
    this.dueReminded,
    DateTime? archived,
    DateTime? deleted,
  }) : decisions = [for (final d in decisions) d.copy()],
       guidelines = {
         for (final MapEntry(:key, :value) in guidelines.entries)
           key: List.of(value),
       },
       resources = resources == null ? null : List.of(resources),
       _archived = tomCanonicalDate(archived),
       _deleted = tomCanonicalDate(deleted) {
    check();
  }

  /// Open and answered questions; an open one makes a todo
  /// `decision-needed` ([tomApplyDecisionRule]).
  List<TomTodoDecision> decisions;

  /// The todo is the user's to do: a queue walk passes it by.
  bool userAction;

  /// Where the todo applies.
  TomTodoScope? scope;

  /// The role that carries the todo out, the one that checks it, and the one
  /// that orchestrates its bundle.
  String? executionRole;
  String? qaRole;
  String? orchestrationRole;

  /// The execution bundle the todo is grouped into.
  String? bundleId;

  /// The role the todo runs in: a folder name under `_ai/roles/`. A queued
  /// prompt for the todo runs as this role, before its queue item's role,
  /// the queuing process step's role and the chat variable `role`.
  String? role;

  /// The guideline aspects the todo chooses: an aspect (a folder name under
  /// `_ai/aspect_guidelines/`) to its choices. The choices **replace** those
  /// of the levels below; when every entry starts with [addGuidelinePrefix]
  /// they are **added** to them; `[`[removeGuideline]`]` sends nothing for the
  /// aspect, whatever a higher level chose. An aspect the todo does not
  /// choose has no entry and inherits.
  ///
  /// In the file a single choice is a string (`night: on`, `night: remove`,
  /// `js_ts: +react`), several a list (`js_ts: [vscode_extension, react]`,
  /// `js_ts: [+react]`); both are read into the list form here, and one
  /// entry is written back as a string.
  Map<String, List<String>> guidelines;

  /// The value of a [guidelines] entry that sends nothing for its aspect.
  static const String removeGuideline = 'remove';

  /// The prefix of a [guidelines] choice added to the levels below.
  static const String addGuidelinePrefix = '+';

  /// The todo this one was derived from, and the feedback that raised it.
  String? derivedFrom;
  String? feedbackSource;

  /// Who filed the todo.
  TomTodoFiledBy? filedBy;

  /// What happens when the todo is completed.
  TomTodoOnDone? onDone;

  /// The final answer of the queue run that executed the todo. Markdown.
  String? lastAnswer;

  /// The resources the todo claims. Null: not given; an empty list: it
  /// claims nothing (kept as `resources: []`).
  List<String>? resources;

  /// The queue holds the todo's claims for its group / completing it frees
  /// them.
  bool claimHold;
  bool claimFree;

  /// When the one reminder for `due` was sent, `yyyy-MM-ddTHH:MM` with `Z` or
  /// an offset, kept verbatim. Cleared when `due` changes.
  String? dueReminded;

  DateTime? _archived;
  DateTime? _deleted;

  /// When the todo was moved to the `-archived` / `-deleted` sibling;
  /// date-only.
  DateTime? get archived => _archived;
  set archived(DateTime? value) => _archived = tomCanonicalDate(value);
  DateTime? get deleted => _deleted;
  set deleted(DateTime? value) => _deleted = tomCanonicalDate(value);

  /// The keys in D1 §3.5.6's order; in the flat todo-file form they are
  /// top-level keys of the item.
  static const List<String> fields = [
    'decisions',
    'user_action',
    'scope',
    'execution_role',
    'qa_role',
    'orchestration_role',
    'bundle_id',
    'role',
    'guidelines',
    'derived_from',
    'feedback_source',
    'filed_by',
    'on_done',
    'last_answer',
    'resources',
    'claim_hold',
    'claim_free',
    'due_reminded',
    'archived',
    'deleted',
  ];

  /// Rejects a [dueReminded] that is not `yyyy-MM-ddTHH:MM` with an offset,
  /// a [filedBy] with a malformed `at`, a [role] that is no role folder name
  /// (`[A-Za-z0-9][A-Za-z0-9_-]*`) and a [guidelines] section or option that
  /// cannot be a folder or file name (empty, a `/`, a line break, or space
  /// at either end).
  void check() {
    if (role != null && !_roleRe.hasMatch(role!)) {
      throw FormatException('Todo "role" must be a role folder name: "$role"');
    }
    for (final MapEntry(:key, :value) in guidelines.entries) {
      if (!_nameOk(key) || !_choicesOk(value)) {
        throw FormatException(
          'Todo "guidelines" entry must map an aspect name to a choice, a list of choices (all with "+" to add) or "remove": "$key": $value',
        );
      }
    }
    if (dueReminded != null &&
        !TomTodoRepeat.nextRepeatRe.hasMatch(dueReminded!)) {
      throw FormatException(
        'Todo "due_reminded" must read yyyy-MM-ddTHH:MM with Z or an offset: "$dueReminded"',
      );
    }
    filedBy?.check();
  }

  static final RegExp _roleRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

  /// One entry's choices: names (each with `+` or none with it), or `[remove]`.
  static bool _choicesOk(List<String> choices) {
    if (choices.length == 1 && choices.first == removeGuideline) return true;
    final adds = choices.where((c) => c.startsWith(addGuidelinePrefix)).length;
    if (adds != 0 && adds != choices.length) return false;
    return choices.every((c) {
      final name = adds != 0 ? c.substring(addGuidelinePrefix.length) : c;
      return _nameOk(name) &&
          name != removeGuideline &&
          !name.startsWith(addGuidelinePrefix);
    });
  }

  static bool _nameOk(String name) =>
      name.isNotEmpty &&
      name.trim() == name &&
      !name.contains('/') &&
      !name.contains('\n') &&
      !name.contains('\r');

  /// True when no field holds anything: the extension is then absent.
  bool get isEmpty => toMap().isEmpty;

  TomItemWorkflow copy() => TomItemWorkflow(
    decisions: decisions,
    userAction: userAction,
    scope: scope?.copy(),
    executionRole: executionRole,
    qaRole: qaRole,
    orchestrationRole: orchestrationRole,
    bundleId: bundleId,
    role: role,
    guidelines: guidelines,
    derivedFrom: derivedFrom,
    feedbackSource: feedbackSource,
    filedBy: filedBy?.copy(),
    onDone: onDone?.copy(),
    lastAnswer: lastAnswer,
    resources: resources,
    claimHold: claimHold,
    claimFree: claimFree,
    dueReminded: dueReminded,
    archived: _archived,
    deleted: _deleted,
  );

  /// The extension's keys and values, set ones only, in [fields] order.
  Map<String, Object?> toMap() => {
    if (decisions.isNotEmpty)
      'decisions': [for (final d in decisions) d.toMap()],
    if (userAction) 'user_action': true,
    if (scope != null && !scope!.isEmpty) 'scope': scope!.toMap(),
    'execution_role': ?executionRole,
    'qa_role': ?qaRole,
    'orchestration_role': ?orchestrationRole,
    'bundle_id': ?bundleId,
    'role': ?role,
    if (guidelines.isNotEmpty)
      'guidelines': {
        for (final MapEntry(:key, :value) in guidelines.entries)
          key: value.length == 1 ? value.first : List.of(value),
      },
    'derived_from': ?derivedFrom,
    'feedback_source': ?feedbackSource,
    if (filedBy != null) 'filed_by': filedBy!.toMap(),
    if (onDone != null) 'on_done': onDone!.toMap(),
    'last_answer': ?lastAnswer,
    if (resources != null) 'resources': List.of(resources!),
    if (claimHold) 'claim_hold': true,
    if (claimFree) 'claim_free': true,
    'due_reminded': ?dueReminded,
    if (_archived != null) 'archived': TomItem.encodeDate(_archived!),
    if (_deleted != null) 'deleted': TomItem.encodeDate(_deleted!),
  };

  /// Reads the extension's keys out of [map] (the flat item or the
  /// `workflow:` mapping); other keys are not its business.
  static TomItemWorkflow fromMap(Map<dynamic, dynamic> map) {
    final onDone = map['on_done'];
    final filedBy = map['filed_by'];
    final scope = map['scope'];
    return TomItemWorkflow(
      decisions: [
        for (final d in (map['decisions'] as List? ?? const []))
          TomTodoDecision.fromMap(d as Map),
      ],
      userAction: _flag(map['user_action'], 'user_action'),
      scope: scope == null ? null : TomTodoScope.fromMap(scope as Map),
      executionRole: map['execution_role'] as String?,
      qaRole: map['qa_role'] as String?,
      orchestrationRole: map['orchestration_role'] as String?,
      bundleId: map['bundle_id'] as String?,
      role: map['role'] as String?,
      guidelines: _guidelineMap(map['guidelines']),
      derivedFrom: map['derived_from'] as String?,
      feedbackSource: map['feedback_source'] as String?,
      filedBy: filedBy == null ? null : TomTodoFiledBy.fromMap(filedBy as Map),
      onDone: onDone == null ? null : TomTodoOnDone.fromMap(onDone as Map),
      lastAnswer: map['last_answer'] as String?,
      resources: map['resources'] == null ? null : _strings(map['resources']),
      claimHold: _flag(map['claim_hold'], 'claim_hold'),
      claimFree: _flag(map['claim_free'], 'claim_free'),
      dueReminded: map['due_reminded']?.toString(),
      archived: TomItem._date(map, 'archived'),
      deleted: TomItem._date(map, 'deleted'),
    );
  }

  /// The `guidelines` mapping: aspect names to a choice (a string) or a list
  /// of choices, read into the list form.
  static Map<String, List<String>> _guidelineMap(Object? value) {
    if (value == null) return const {};
    if (value is! Map) {
      throw FormatException('Todo "guidelines" must be a mapping: $value');
    }
    final out = <String, List<String>>{};
    for (final MapEntry(:key, :value) in value.entries) {
      final choices = value is String
          ? [value]
          : value is List && value.every((v) => v is String)
          ? [for (final v in value) v as String]
          : null;
      if (key is! String || choices == null) {
        throw FormatException(
          'Todo "guidelines" entry must map an aspect name to a choice or a list of choices: $key: $value',
        );
      }
      out[key] = choices;
    }
    return out;
  }
}

/// The calendar day [value] names, held as UTC midnight of that day. The day
/// is read from the value's own fields: a local `DateTime` gives its local
/// day, a UTC one its UTC day.
DateTime? tomCanonicalDate(DateTime? value) {
  if (value == null) return null;
  return DateTime.utc(value.year, value.month, value.day);
}

/// One item: the record of D1 §3.1.
///
/// Mutable, like the 3.x `TomTodo` it replaces ([copy] for a detached
/// value, [copyWith] for a changed one); equal when every field is equal.
/// `WebworkSection` extends it inside Webwork.
///
/// [due], [start] and [completedDate] are **date-only** (UTC midnight of the
/// day). [created] and [updated] keep what they are given: a value with no
/// time of day is a date and is written as one, any other value is written
/// as a UTC timestamp. [estimate] is a verbatim ISO-8601 duration.
///
/// Members marked deprecated are the 3.x `TomTodo` names; each says what
/// replaces it.
class TomItem {
  TomItem({
    required this.id,
    String? headline,
    @Deprecated('Use headline') String? title,
    List<String> itemTypes = const [TomTodoItemTypes.todo],
    this.summary,
    this.description,
    List<String> categories = const [],
    List<String> tags = const [],
    this.status = TomTodoStatus.notStarted,
    this.priority,
    this.flag = false,
    DateTime? start,
    DateTime? due,
    this.estimate,
    List<TomItemReminder> reminders = const [],
    this.repeat,
    this.nextRepeat,
    this.repeatCount,
    this.remind,
    this.nextRemind,
    this.remindCount,
    DateTime? completedDate,
    this.completedBy,
    List<String> dependencies = const [],
    List<String> blockedBy = const [],
    List<String> blocking = const [],
    List<String> blockedUntil = const [],
    List<String> comprisedOf = const [],
    List<TomItemAddress> assignees = const [],
    List<TomItemMembership> memberships = const [],
    TomItemLinks? links,
    @Deprecated('Use links.external') List<TomTodoReference>? references,
    this.source,
    this.notes,
    this.created,
    this.updated,
    this.author,
    this.editedBy,
    this.bodyType,
    Object? body,
    Map<String, Object?>? presentation,
    this.template = false,
    TomItemContainer? container,
    TomItemPeople? people,
    TomItemMail? mail,
    TomItemWorkflow? workflow,
    @Deprecated('Use workflow.decisions') List<TomTodoDecision>? decisions,
    @Deprecated('Use workflow.userAction') bool? userAction,
    @Deprecated('Use workflow.scope') TomTodoScope? scope,
    @Deprecated('Use workflow.executionRole') String? executionRole,
    @Deprecated('Use workflow.qaRole') String? qaRole,
    @Deprecated('Use workflow.orchestrationRole') String? orchestrationRole,
    @Deprecated('Use workflow.bundleId') String? bundleId,
    @Deprecated('Use workflow.derivedFrom') String? derivedFrom,
    @Deprecated('Use workflow.feedbackSource') String? feedbackSource,
    @Deprecated('Use workflow.filedBy') TomTodoFiledBy? filedBy,
    @Deprecated('Use workflow.onDone') TomTodoOnDone? onDone,
    @Deprecated('Use workflow.lastAnswer') String? lastAnswer,
    @Deprecated('Use workflow.resources') List<String>? resources,
    @Deprecated('Use workflow.claimHold') bool? claimHold,
    @Deprecated('Use workflow.claimFree') bool? claimFree,
    @Deprecated('Use workflow.dueReminded') String? dueReminded,
    @Deprecated('Use workflow.archived') DateTime? archived,
    @Deprecated('Use workflow.deleted') DateTime? deleted,
  }) : headline = headline ?? title ?? '',
       itemTypes = List.of(itemTypes),
       categories = List.of(categories),
       tags = List.of(tags),
       reminders = List.of(reminders),
       dependencies = List.of(dependencies),
       blockedBy = List.of(blockedBy),
       blocking = List.of(blocking),
       blockedUntil = List.of(blockedUntil),
       comprisedOf = List.of(comprisedOf),
       assignees = List.of(assignees),
       memberships = List.of(memberships),
       links = links?.copy() ?? TomItemLinks(external: references ?? const []),
       body = _deepCopy(body),
       presentation = presentation == null
           ? null
           : _deepCopy(presentation) as Map<String, Object?>,
       container = container?.copy(),
       people = people?.copy(),
       mail = mail?.copy(),
       workflow = workflow?.copy(),
       _start = tomCanonicalDate(start),
       _due = tomCanonicalDate(due),
       _completedDate = tomCanonicalDate(completedDate) {
    if (headline != null && title != null && headline != title) {
      throw ArgumentError('Give headline or title, not two different ones');
    }
    if (links != null && references != null) {
      throw ArgumentError('Give links or references, not both');
    }
    final flat = <String, Object?>{
      'decisions': ?decisions,
      'userAction': ?userAction,
      'scope': ?scope,
      'executionRole': ?executionRole,
      'qaRole': ?qaRole,
      'orchestrationRole': ?orchestrationRole,
      'bundleId': ?bundleId,
      'derivedFrom': ?derivedFrom,
      'feedbackSource': ?feedbackSource,
      'filedBy': ?filedBy,
      'onDone': ?onDone,
      'lastAnswer': ?lastAnswer,
      'resources': ?resources,
      'claimHold': ?claimHold,
      'claimFree': ?claimFree,
      'dueReminded': ?dueReminded,
      'archived': ?archived,
      'deleted': ?deleted,
    };
    if (flat.isNotEmpty) {
      if (this.workflow != null) {
        throw ArgumentError(
          'Give the workflow fields in workflow or one by one, not both',
        );
      }
      this.workflow = TomItemWorkflow(
        decisions: decisions ?? const [],
        userAction: userAction ?? false,
        scope: scope?.copy(),
        executionRole: executionRole,
        qaRole: qaRole,
        orchestrationRole: orchestrationRole,
        bundleId: bundleId,
        derivedFrom: derivedFrom,
        feedbackSource: feedbackSource,
        filedBy: filedBy?.copy(),
        onDone: onDone?.copy(),
        lastAnswer: lastAnswer,
        resources: resources,
        claimHold: claimHold ?? false,
        claimFree: claimFree ?? false,
        dueReminded: dueReminded,
        archived: archived,
        deleted: deleted,
      );
    }
    check();
  }

  // ── Identity, types and text ───────────────────────────────────────────

  /// The item's identity: a UUID for items born in Webwork, the date-code id
  /// for workspace todos (D1 §2.3).
  final String id;

  /// The stored item types, as wire names (unknown ones kept verbatim): see
  /// [TomTodoItemTypes]. [types] answers the computed ones too.
  List<String> itemTypes;

  /// The one-line title (a todo file's `title`).
  String headline;

  /// The 3.x name of [headline].
  @Deprecated('Use headline')
  String get title => headline;
  @Deprecated('Use headline')
  set title(String value) => headline = value;

  /// An optional one-line abstract.
  String? summary;

  /// Markdown text (CommonMark with GitHub extensions).
  String? description;

  // ── Classification ─────────────────────────────────────────────────────

  /// Hierarchical, inherited along the tree.
  List<String> categories;

  /// Flat labels, not inherited.
  List<String> tags;

  // ── planning: the todo fields ──────────────────────────────────────────

  /// The status: a todo status, `group`, or [TomTodoStatus.none] for an item
  /// that is currently not treated as a todo.
  TomTodoStatus status;

  TomTodoPriority? priority;

  /// Flagged by the user.
  bool flag;

  DateTime? _start;
  DateTime? _due;
  DateTime? _completedDate;

  /// The day the item may be begun; date-only.
  DateTime? get start => _start;
  set start(DateTime? value) => _start = tomCanonicalDate(value);

  /// The due day, always UTC midnight. Setting another day clears the
  /// workflow's `due_reminded`, so the new day gets its own reminder.
  DateTime? get due => _due;
  set due(DateTime? value) {
    final next = tomCanonicalDate(value);
    if (next != _due) workflow?.dueReminded = null;
    _due = next;
  }

  /// A verbatim ISO-8601 duration.
  String? estimate;

  /// When the item rings, in the order they were added.
  List<TomItemReminder> reminders;

  /// The rule a repeated item comes back by.
  TomTodoRepeat? repeat;

  /// When a `waiting-for-repeat` item is due again, verbatim.
  String? nextRepeat;

  /// How many times it has been done and repeated.
  int? repeatCount;

  /// The rule an open item keeps reminding by (the [repeat] rule forms but
  /// `manual`); it rings at each moment the rule names until it is done,
  /// cancelled or the rule ends. Independent of [repeat].
  TomTodoRepeat? remind;

  /// When the [remind] rule rings next, `yyyy-MM-ddTHH:MM` with `Z` or an
  /// offset, verbatim; absent once the rule has ended. Written before the
  /// reminder is sent, so it rings once across devices.
  String? nextRemind;

  /// How many reminders the [remind] rule has sent.
  int? remindCount;

  /// When it was done; date-only.
  DateTime? get completedDate => _completedDate;
  set completedDate(DateTime? value) =>
      _completedDate = tomCanonicalDate(value);

  /// Who did it.
  String? completedBy;

  // ── dependencies ───────────────────────────────────────────────────────

  /// What must finish first (an ordering).
  List<String> dependencies;

  /// What it waits for: todo ids or `<quest>/<todo>` / D1 references.
  List<String> blockedBy;

  /// The reverse of [blockedBy]. Derived: in todo files the VS Code
  /// extension keeps it in step; elsewhere it is computed and never written.
  List<String> blocking;

  /// Publish conditions `<package> >= <x.y.z>`.
  List<String> blockedUntil;

  /// A group's members, in order.
  List<String> comprisedOf;

  // ── people, memberships, links ─────────────────────────────────────────

  /// Who is to do it.
  List<TomItemAddress> assignees;

  /// The lists, journals and mindmaps it appears in besides its home.
  List<TomItemMembership> memberships;

  /// External links and related items.
  TomItemLinks links;

  /// The 3.x name of [TomItemLinks.external].
  @Deprecated('Use links.external')
  List<TomTodoReference> get references => links.external;
  @Deprecated('Use links.external')
  set references(List<TomTodoReference> value) =>
      links.external = List.of(value);

  /// The external anchor `<scheme>:<rest>`.
  String? source;

  /// Free-form context.
  String? notes;

  // ── provenance ─────────────────────────────────────────────────────────

  /// Created / last changed. A value with no time of day is a date.
  DateTime? created;
  DateTime? updated;

  /// Who created it, who edited it last.
  String? author;
  String? editedBy;

  // ── body ───────────────────────────────────────────────────────────────

  /// The MIME type of [body] (D1 §3.6); null on a light item.
  String? bodyType;

  /// The content beyond the description: a map for a Webwork vendor type, a
  /// string for a text type or base64 text.
  Object? body;

  /// How the body is shown (D22); null when absent.
  Map<String, Object?>? presentation;

  /// This item is a template.
  bool template;

  // ── extensions ─────────────────────────────────────────────────────────

  TomItemContainer? container;
  TomItemPeople? people;
  TomItemMail? mail;
  TomItemWorkflow? workflow;

  /// [workflow], created when absent: where the 3.x forwarders write.
  TomItemWorkflow get _wf => workflow ??= TomItemWorkflow();

  // ── 3.x forwarders into [workflow] ─────────────────────────────────────

  @Deprecated('Use workflow.decisions')
  List<TomTodoDecision> get decisions => _wf.decisions;
  @Deprecated('Use workflow.decisions')
  set decisions(List<TomTodoDecision> v) => _wf.decisions = v;
  @Deprecated('Use workflow.userAction')
  bool get userAction => workflow?.userAction ?? false;
  @Deprecated('Use workflow.userAction')
  set userAction(bool v) => _wf.userAction = v;
  @Deprecated('Use workflow.scope')
  TomTodoScope? get scope => workflow?.scope;
  @Deprecated('Use workflow.scope')
  set scope(TomTodoScope? v) => _wf.scope = v;
  @Deprecated('Use workflow.executionRole')
  String? get executionRole => workflow?.executionRole;
  @Deprecated('Use workflow.executionRole')
  set executionRole(String? v) => _wf.executionRole = v;
  @Deprecated('Use workflow.qaRole')
  String? get qaRole => workflow?.qaRole;
  @Deprecated('Use workflow.qaRole')
  set qaRole(String? v) => _wf.qaRole = v;
  @Deprecated('Use workflow.orchestrationRole')
  String? get orchestrationRole => workflow?.orchestrationRole;
  @Deprecated('Use workflow.orchestrationRole')
  set orchestrationRole(String? v) => _wf.orchestrationRole = v;
  @Deprecated('Use workflow.bundleId')
  String? get bundleId => workflow?.bundleId;
  @Deprecated('Use workflow.bundleId')
  set bundleId(String? v) => _wf.bundleId = v;
  @Deprecated('Use workflow.derivedFrom')
  String? get derivedFrom => workflow?.derivedFrom;
  @Deprecated('Use workflow.derivedFrom')
  set derivedFrom(String? v) => _wf.derivedFrom = v;
  @Deprecated('Use workflow.feedbackSource')
  String? get feedbackSource => workflow?.feedbackSource;
  @Deprecated('Use workflow.feedbackSource')
  set feedbackSource(String? v) => _wf.feedbackSource = v;
  @Deprecated('Use workflow.filedBy')
  TomTodoFiledBy? get filedBy => workflow?.filedBy;
  @Deprecated('Use workflow.filedBy')
  set filedBy(TomTodoFiledBy? v) => _wf.filedBy = v;
  @Deprecated('Use workflow.onDone')
  TomTodoOnDone? get onDone => workflow?.onDone;
  @Deprecated('Use workflow.onDone')
  set onDone(TomTodoOnDone? v) => _wf.onDone = v;
  @Deprecated('Use workflow.lastAnswer')
  String? get lastAnswer => workflow?.lastAnswer;
  @Deprecated('Use workflow.lastAnswer')
  set lastAnswer(String? v) => _wf.lastAnswer = v;
  @Deprecated('Use workflow.resources')
  List<String>? get resources => workflow?.resources;
  @Deprecated('Use workflow.resources')
  set resources(List<String>? v) => _wf.resources = v;
  @Deprecated('Use workflow.claimHold')
  bool get claimHold => workflow?.claimHold ?? false;
  @Deprecated('Use workflow.claimHold')
  set claimHold(bool v) => _wf.claimHold = v;
  @Deprecated('Use workflow.claimFree')
  bool get claimFree => workflow?.claimFree ?? false;
  @Deprecated('Use workflow.claimFree')
  set claimFree(bool v) => _wf.claimFree = v;
  @Deprecated('Use workflow.dueReminded')
  String? get dueReminded => workflow?.dueReminded;
  @Deprecated('Use workflow.dueReminded')
  set dueReminded(String? v) {
    _wf.dueReminded = v;
    _wf.check();
  }

  @Deprecated('Use workflow.archived')
  DateTime? get archived => workflow?.archived;
  @Deprecated('Use workflow.archived')
  set archived(DateTime? v) => _wf.archived = v;
  @Deprecated('Use workflow.deleted')
  DateTime? get deleted => workflow?.deleted;
  @Deprecated('Use workflow.deleted')
  set deleted(DateTime? v) => _wf.deleted = v;

  // ── types ──────────────────────────────────────────────────────────────

  /// Whether the stored type [type] is set.
  bool hasStoredType(TomItemType type) =>
      type.stored && itemTypes.contains(type.wire);

  /// Adds the stored type [type]. A computed type cannot be added: it follows
  /// from the field named in the error.
  void addType(TomItemType type) {
    _refuseComputed(type);
    if (!itemTypes.contains(type.wire)) itemTypes = [...itemTypes, type.wire];
  }

  /// Removes the stored type [type]; a computed type is refused.
  void removeType(TomItemType type) {
    _refuseComputed(type);
    itemTypes = [
      for (final t in itemTypes)
        if (t != type.wire) t,
    ];
  }

  static void _refuseComputed(TomItemType type) {
    if (type.stored) return;
    final from = switch (type) {
      TomItemType.journalEntry => 'a membership in a journal',
      TomItemType.mindmapNode => 'a home in or a membership of a mindmap',
      TomItemType.email => 'the mail extension',
      _ => 'its source',
    };
    throw ArgumentError.value(
      type.wire,
      'type',
      'A computed type follows from $from and cannot be set',
    );
  }

  /// Every type of the item: the stored ones in [itemTypes] (in
  /// [TomItemType] order) and the computed ones — `journal-entry` from a
  /// membership in a journal, `mindmap-node` from a home in or a membership
  /// of a mindmap, `email` from the [mail] extension. A membership's
  /// container kind comes from [context]; without it, only `email` can be
  /// computed. Read-only: the set is a fresh value.
  Set<TomItemType> types([
    TomItemTypeContext context = const TomItemTypeContext(),
  ]) {
    final kinds = <TomContainerKind>{
      ...context.listedIn,
      if (context.kindOf != null)
        for (final m in memberships) ?context.kindOf!(m.ref),
    };
    return {
      for (final type in TomItemType.values)
        if (switch (type) {
          TomItemType.todo || TomItemType.reminder => hasStoredType(type),
          TomItemType.journalEntry => kinds.contains(TomContainerKind.journal),
          TomItemType.mindmapNode =>
            context.home == TomContainerKind.mindmap ||
                kinds.contains(TomContainerKind.mindmap),
          TomItemType.email => mail != null && !mail!.isEmpty,
        })
          type,
    };
  }

  // ── 3.x behaviour ──────────────────────────────────────────────────────

  /// True for an item with a repeat rule.
  bool get isRepeated => repeat != null;

  /// True for the **done group**: `completed` and `cancelled`.
  bool get isDone =>
      status == TomTodoStatus.completed || status == TomTodoStatus.cancelled;

  /// True for a todo group.
  bool get isGroup => status == TomTodoStatus.group;

  /// True while at least one decision has no answer.
  bool get hasOpenDecision => workflow?.decisions.any((d) => d.isOpen) ?? false;

  /// True when a blocker is recorded — an item reference or a publish
  /// condition.
  bool get hasBlocker => blockedBy.isNotEmpty || blockedUntil.isNotEmpty;

  /// Records that this item was written on the day of [on] by [author] (a
  /// null [author] leaves `author` absent).
  ///
  /// Records the **day**, as 3.x did: the workspace's todo files hold dates.
  void recordCreation({required DateTime on, String? author}) {
    created = tomCanonicalDate(on);
    if (author != null) this.author = author;
  }

  /// Moves the item to [next] on the day of [on], keeping the completion
  /// facts true: entering `completed` records `completed_date` and
  /// `completed_by` ([by]); leaving it clears both. `updated` is stamped with
  /// the day. Moving to the status it already has changes nothing.
  void changeStatus(TomTodoStatus next, {required DateTime on, String? by}) {
    if (next == status) return;
    final wasCompleted = status == TomTodoStatus.completed;
    status = next;
    updated = tomCanonicalDate(on);
    if (next == TomTodoStatus.completed) {
      completedDate = on;
      completedBy = by;
    } else if (wasCompleted) {
      completedDate = null;
      completedBy = null;
    }
  }

  /// Validates the fields with a form: [estimate], [blockedUntil],
  /// [nextRepeat], [repeatCount], [remind], [nextRemind], [remindCount] and
  /// the workflow's.
  void check() {
    if (estimate != null && !_durationRe.hasMatch(estimate!)) {
      throw FormatException(
        'Todo "estimate" must be an ISO-8601 duration: "$estimate"',
      );
    }
    for (final condition in blockedUntil) {
      checkBlockedUntil(condition);
    }
    if (nextRepeat != null &&
        !TomTodoRepeat.nextRepeatRe.hasMatch(nextRepeat!)) {
      throw FormatException(
        'Todo "next_repeat" must read yyyy-MM-ddTHH:MM with Z or an offset: "$nextRepeat"',
      );
    }
    if (repeatCount != null && repeatCount! < 0) {
      throw FormatException(
        'Todo "repeat_count" must be 0 or more: $repeatCount',
      );
    }
    if (remind != null && remind!.rule == TomTodoRepeatRule.manual) {
      throw const FormatException(
        'Todo "remind" cannot be manual: a reminder rule names its moments',
      );
    }
    if (nextRemind != null &&
        !TomTodoRepeat.nextRepeatRe.hasMatch(nextRemind!)) {
      throw FormatException(
        'Todo "next_remind" must read yyyy-MM-ddTHH:MM with Z or an offset: "$nextRemind"',
      );
    }
    if (remindCount != null && remindCount! < 0) {
      throw FormatException(
        'Todo "remind_count" must be 0 or more: $remindCount',
      );
    }
    workflow?.check();
  }

  // ── copies ─────────────────────────────────────────────────────────────

  /// A detached deep copy carrying the same id.
  TomItem copy() => TomItem.fromMap(toMap());

  /// A copy with the given fields replaced. A field cannot be cleared here:
  /// take [copy] and set it to null.
  TomItem copyWith({
    String? headline,
    List<String>? itemTypes,
    String? summary,
    String? description,
    List<String>? categories,
    List<String>? tags,
    TomTodoStatus? status,
    TomTodoPriority? priority,
    bool? flag,
    DateTime? start,
    DateTime? due,
    String? estimate,
    List<TomItemReminder>? reminders,
    TomTodoRepeat? repeat,
    String? nextRepeat,
    int? repeatCount,
    TomTodoRepeat? remind,
    String? nextRemind,
    int? remindCount,
    DateTime? completedDate,
    String? completedBy,
    List<String>? dependencies,
    List<String>? blockedBy,
    List<String>? blocking,
    List<String>? blockedUntil,
    List<String>? comprisedOf,
    List<TomItemAddress>? assignees,
    List<TomItemMembership>? memberships,
    TomItemLinks? links,
    String? source,
    String? notes,
    DateTime? created,
    DateTime? updated,
    String? author,
    String? editedBy,
    String? bodyType,
    Object? body,
    Map<String, Object?>? presentation,
    bool? template,
    TomItemContainer? container,
    TomItemPeople? people,
    TomItemMail? mail,
    TomItemWorkflow? workflow,
  }) {
    final next = copy();
    if (headline != null) next.headline = headline;
    if (itemTypes != null) next.itemTypes = List.of(itemTypes);
    if (summary != null) next.summary = summary;
    if (description != null) next.description = description;
    if (categories != null) next.categories = List.of(categories);
    if (tags != null) next.tags = List.of(tags);
    if (status != null) next.status = status;
    if (priority != null) next.priority = priority;
    if (flag != null) next.flag = flag;
    if (start != null) next.start = start;
    if (due != null) next.due = due;
    if (estimate != null) next.estimate = estimate;
    if (reminders != null) next.reminders = List.of(reminders);
    if (repeat != null) next.repeat = repeat.copy();
    if (nextRepeat != null) next.nextRepeat = nextRepeat;
    if (repeatCount != null) next.repeatCount = repeatCount;
    if (remind != null) next.remind = remind.copy();
    if (nextRemind != null) next.nextRemind = nextRemind;
    if (remindCount != null) next.remindCount = remindCount;
    if (completedDate != null) next.completedDate = completedDate;
    if (completedBy != null) next.completedBy = completedBy;
    if (dependencies != null) next.dependencies = List.of(dependencies);
    if (blockedBy != null) next.blockedBy = List.of(blockedBy);
    if (blocking != null) next.blocking = List.of(blocking);
    if (blockedUntil != null) next.blockedUntil = List.of(blockedUntil);
    if (comprisedOf != null) next.comprisedOf = List.of(comprisedOf);
    if (assignees != null) next.assignees = List.of(assignees);
    if (memberships != null) next.memberships = List.of(memberships);
    if (links != null) next.links = links.copy();
    if (source != null) next.source = source;
    if (notes != null) next.notes = notes;
    if (created != null) next.created = created;
    if (updated != null) next.updated = updated;
    if (author != null) next.author = author;
    if (editedBy != null) next.editedBy = editedBy;
    if (bodyType != null) next.bodyType = bodyType;
    if (body != null) next.body = _deepCopy(body);
    if (presentation != null) {
      next.presentation = _deepCopy(presentation) as Map<String, Object?>;
    }
    if (template != null) next.template = template;
    if (container != null) next.container = container.copy();
    if (people != null) next.people = people.copy();
    if (mail != null) next.mail = mail.copy();
    if (workflow != null) next.workflow = workflow.copy();
    next.check();
    return next;
  }

  // ── field lists ────────────────────────────────────────────────────────

  /// The record's top-level keys in D1 §3.1 order (the D1 codec's
  /// field-order table).
  static const List<String> recordFields = [
    'id',
    'item_types',
    'headline',
    'summary',
    'description',
    'categories',
    'tags',
    'planning',
    'dependencies',
    'assignees',
    'memberships',
    'links',
    'source',
    'notes',
    'created',
    'updated',
    'author',
    'edited_by',
    'body_type',
    'body',
    'presentation',
    'template',
    'children',
    'people',
    'mail',
    'workflow',
  ];

  /// The base fields outside the groups, in [recordFields] order.
  static const List<String> baseFields = [
    'id',
    'item_types',
    'headline',
    'summary',
    'description',
    'categories',
    'tags',
    'assignees',
    'memberships',
    'source',
    'notes',
    'created',
    'updated',
    'author',
    'edited_by',
    'body_type',
    'body',
    'presentation',
    'template',
  ];

  /// The `planning:` group (D1 §3.5.1).
  static const List<String> planningFields = [
    'status',
    'priority',
    'flag',
    'start',
    'due',
    'estimate',
    'reminders',
    'repeat',
    'next_repeat',
    'repeat_count',
    'remind',
    'next_remind',
    'remind_count',
    'completed_date',
    'completed_by',
  ];

  /// The `dependencies:` group (D1 §3.5.2), with the derived `blocking` the
  /// todo files carry.
  static const List<String> dependencyFields = [
    'dependencies',
    'blocked_by',
    'blocking',
    'blocked_until',
    'comprised_of',
  ];

  /// The flat todo-file form: every field of the item under its key, in the
  /// order a key added to a todo file is placed. `title` is [headline],
  /// `references` the external links, `related` the related ones; the
  /// workflow fields and the planning and dependency fields are top-level
  /// keys; `children`, `people` and `mail` are mappings. The workspace todo
  /// schema has exactly these properties (`_bin/check_todo_model.py`).
  static const Set<String> fields = {
    'id',
    'item_types',
    'title',
    'summary',
    'description',
    'status',
    'priority',
    'flag',
    'start',
    'due',
    'estimate',
    'reminders',
    'tags',
    'categories',
    'scope',
    'decisions',
    'references',
    'related',
    'dependencies',
    'blocked_by',
    'blocking',
    'comprised_of',
    'blocked_until',
    'assignees',
    'memberships',
    'user_action',
    'repeat',
    'next_repeat',
    'repeat_count',
    'remind',
    'next_remind',
    'remind_count',
    'due_reminded',
    'notes',
    'source',
    'created',
    'updated',
    'completed_date',
    'author',
    'edited_by',
    'completed_by',
    'last_answer',
    'archived',
    'deleted',
    'execution_role',
    'qa_role',
    'orchestration_role',
    'bundle_id',
    'role',
    'guidelines',
    'derived_from',
    'feedback_source',
    'on_done',
    'filed_by',
    'resources',
    'claim_hold',
    'claim_free',
    'body_type',
    'body',
    'presentation',
    'template',
    'children',
    'people',
    'mail',
  };

  // ── the flat form ──────────────────────────────────────────────────────

  /// The item in the flat todo-file form, set fields only, in [fields]
  /// order. Nothing set is lost: every field that holds something is here.
  /// `status` is always written; `resources: []` is kept (it claims
  /// nothing); the stored type `todo` alone — what every todo-file item is —
  /// is not written.
  Map<String, Object?> toMap() {
    final wf = workflow?.toMap() ?? const <String, Object?>{};
    final storedTypes = [
      for (final t in itemTypes)
        if (TomItemType.tryWire(t)?.computed != true) t,
    ];
    final writeTypes =
        !(storedTypes.length == 1 &&
            storedTypes.single == TomTodoItemTypes.todo);
    final map = <String, Object?>{
      'id': id,
      if (writeTypes && storedTypes.isNotEmpty) 'item_types': storedTypes,
      if (writeTypes && storedTypes.isEmpty) 'item_types': const <String>[],
      'title': headline,
      'summary': ?summary,
      'description': ?description,
      'status': status.wire,
      if (priority != null) 'priority': priority!.wire,
      if (flag) 'flag': true,
      if (_start != null) 'start': encodeDate(_start!),
      if (_due != null) 'due': encodeDate(_due!),
      'estimate': ?estimate,
      if (reminders.isNotEmpty)
        'reminders': [for (final r in reminders) r.toMap()],
      if (tags.isNotEmpty) 'tags': List.of(tags),
      if (categories.isNotEmpty) 'categories': List.of(categories),
      if (wf.containsKey('scope')) 'scope': wf['scope'],
      if (wf.containsKey('decisions')) 'decisions': wf['decisions'],
      if (links.external.isNotEmpty)
        'references': [for (final r in links.external) r.toMap()],
      if (links.related.isNotEmpty)
        'related': [for (final r in links.related) r.toMap()],
      if (dependencies.isNotEmpty) 'dependencies': List.of(dependencies),
      if (blockedBy.isNotEmpty) 'blocked_by': List.of(blockedBy),
      if (blocking.isNotEmpty) 'blocking': List.of(blocking),
      if (comprisedOf.isNotEmpty) 'comprised_of': List.of(comprisedOf),
      if (blockedUntil.isNotEmpty) 'blocked_until': List.of(blockedUntil),
      if (assignees.isNotEmpty)
        'assignees': [for (final a in assignees) a.toMap()],
      if (memberships.isNotEmpty)
        'memberships': [for (final m in memberships) m.toMap()],
      if (wf.containsKey('user_action')) 'user_action': true,
      if (repeat != null) 'repeat': repeat!.toMap(),
      'next_repeat': ?nextRepeat,
      'repeat_count': ?repeatCount,
      if (remind != null) 'remind': remind!.toMap(),
      'next_remind': ?nextRemind,
      'remind_count': ?remindCount,
      if (wf.containsKey('due_reminded')) 'due_reminded': wf['due_reminded'],
      'notes': ?notes,
      'source': ?source,
      if (created != null) 'created': encodeDateOrTime(created!),
      if (updated != null) 'updated': encodeDateOrTime(updated!),
      if (_completedDate != null) 'completed_date': encodeDate(_completedDate!),
      'author': ?author,
      'edited_by': ?editedBy,
      'completed_by': ?completedBy,
    };
    for (final key in const [
      'last_answer',
      'archived',
      'deleted',
      'execution_role',
      'qa_role',
      'orchestration_role',
      'bundle_id',
      'role',
      'guidelines',
      'derived_from',
      'feedback_source',
      'on_done',
      'filed_by',
      'resources',
      'claim_hold',
      'claim_free',
    ]) {
      if (wf.containsKey(key)) map[key] = wf[key];
    }
    if (bodyType != null) map['body_type'] = bodyType;
    if (!_isEmptyValue(body)) map['body'] = _deepCopy(body);
    if (presentation != null && presentation!.isNotEmpty) {
      map['presentation'] = _deepCopy(presentation);
    }
    if (template) map['template'] = true;
    if (container != null && !container!.isEmpty) {
      map['children'] = [for (final c in container!.children) c.toMap()];
    }
    if (people != null && !people!.isEmpty) map['people'] = people!.toMap();
    if (mail != null && !mail!.isEmpty) map['mail'] = mail!.toMap();
    return map;
  }

  /// Parses an item in the flat todo-file form. A key outside [fields] is a
  /// format error. An absent `title` reads as empty, an absent `status` as
  /// `not-started`, an absent `item_types` as `[todo]`; a computed type in
  /// `item_types` is ignored.
  static TomItem fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!fields.contains(key)) {
        throw FormatException('Unknown todo field: "$key"');
      }
    }
    final id = map['id'];
    final title = map['title'] ?? '';
    if (id is! String || title is! String) {
      throw FormatException('Invalid todo map (id/title): $map');
    }
    final status = map['status'];
    final priority = map['priority'];
    final types = map['item_types'];
    final hasWorkflow = TomItemWorkflow.fields.any(
      (k) => map.containsKey(k) && map[k] != null,
    );
    final presentation = map['presentation'];
    final children = map['children'];
    return TomItem(
      id: id,
      headline: title,
      itemTypes: types == null
          ? const [TomTodoItemTypes.todo]
          : [
              for (final t in _strings(types))
                if (TomItemType.tryWire(t)?.computed != true) t,
            ],
      summary: map['summary'] as String?,
      description: map['description'] as String?,
      categories: _strings(map['categories']),
      tags: _strings(map['tags']),
      status: status == null
          ? TomTodoStatus.notStarted
          : TomTodoStatus.fromWire(status.toString()),
      priority: priority == null
          ? null
          : TomTodoPriority.fromWire(priority.toString()),
      flag: _flag(map['flag'], 'flag'),
      start: _date(map, 'start'),
      due: _date(map, 'due'),
      estimate: map['estimate'] as String?,
      reminders: [
        for (final r in (map['reminders'] as List? ?? const []))
          TomItemReminder.fromMap(r as Map),
      ],
      repeat: map['repeat'] == null
          ? null
          : TomTodoRepeat.fromMap(map['repeat'] as Map),
      nextRepeat: map['next_repeat']?.toString(),
      repeatCount: map['repeat_count'] == null
          ? null
          : (map['repeat_count'] is int
                ? map['repeat_count'] as int
                : throw FormatException(
                    'Todo "repeat_count" must be a whole number, not "${map['repeat_count']}"',
                  )),
      remind: map['remind'] == null
          ? null
          : TomTodoRepeat.fromMap(map['remind'] as Map),
      nextRemind: map['next_remind']?.toString(),
      remindCount: map['remind_count'] == null
          ? null
          : (map['remind_count'] is int
                ? map['remind_count'] as int
                : throw FormatException(
                    'Todo "remind_count" must be a whole number, not "${map['remind_count']}"',
                  )),
      completedDate: _date(map, 'completed_date'),
      completedBy: map['completed_by'] as String?,
      dependencies: _strings(map['dependencies']),
      blockedBy: _strings(map['blocked_by']),
      blocking: _strings(map['blocking']),
      blockedUntil: _strings(map['blocked_until']),
      comprisedOf: _strings(map['comprised_of']),
      assignees: [
        for (final a in (map['assignees'] as List? ?? const []))
          TomItemAddress.fromMap(a as Map),
      ],
      memberships: [
        for (final m in (map['memberships'] as List? ?? const []))
          TomItemMembership.fromMap(m as Map),
      ],
      links: TomItemLinks(
        external: [
          for (final r in (map['references'] as List? ?? const []))
            TomTodoReference.fromMap(r as Map),
        ],
        related: [
          for (final r in (map['related'] as List? ?? const []))
            TomItemRelated.fromMap(r as Map),
        ],
      ),
      source: map['source'] as String?,
      notes: map['notes'] as String?,
      created: _dateOrTime(map, 'created'),
      updated: _dateOrTime(map, 'updated'),
      author: map['author'] as String?,
      editedBy: map['edited_by'] as String?,
      bodyType: map['body_type'] as String?,
      body: map['body'],
      presentation: presentation == null
          ? null
          : Map<String, Object?>.from(presentation as Map),
      template: _flag(map['template'], 'template'),
      container: children == null
          ? null
          : TomItemContainer(
              children: [
                for (final c in children as List)
                  TomItemChild.fromMap(c as Map),
              ],
            ),
      people: map['people'] == null
          ? null
          : TomItemPeople.fromMap(map['people'] as Map),
      mail: map['mail'] == null
          ? null
          : TomItemMail.fromMap(map['mail'] as Map),
      workflow: hasWorkflow ? TomItemWorkflow.fromMap(map) : null,
    );
  }

  // ── dates ──────────────────────────────────────────────────────────────

  /// `yyyy-MM-dd`, the day [date] names from its own fields.
  static String encodeDate(DateTime date) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${p2(date.month)}-${p2(date.day)}';
  }

  /// A date when [value] has no time of day (in its own fields), else the
  /// UTC timestamp `yyyy-MM-ddTHH:MM:SS[.fff]Z`.
  static String encodeDateOrTime(DateTime value) {
    final midnight =
        value.hour == 0 &&
        value.minute == 0 &&
        value.second == 0 &&
        value.millisecond == 0 &&
        value.microsecond == 0;
    if (midnight) return encodeDate(value);
    final utc = value.toUtc();
    final text = utc.toIso8601String();
    return text.endsWith('.000Z')
        ? '${text.substring(0, text.length - 5)}Z'
        : text;
  }

  static final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _timestampRe = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$',
  );

  /// Parses a stored date field, rejecting anything that is not date-only.
  static DateTime decodeDate(Object value, {String field = 'due'}) {
    final text = value.toString();
    if (!_dateRe.hasMatch(text)) {
      throw FormatException(
        'Todo "$field" must be date-only "yyyy-MM-dd": "$text"',
      );
    }
    return DateTime.parse('${text}T00:00:00Z');
  }

  /// Parses `created` / `updated`: a date or a timestamp with its zone.
  static DateTime decodeDateOrTime(Object value, {required String field}) {
    final text = value.toString();
    if (_dateRe.hasMatch(text)) return DateTime.parse('${text}T00:00:00Z');
    if (_timestampRe.hasMatch(text)) return DateTime.parse(text).toUtc();
    throw FormatException(
      'Todo "$field" must be a date "yyyy-MM-dd" or a timestamp with its zone: "$text"',
    );
  }

  static DateTime? _date(Map<dynamic, dynamic> map, String key) =>
      map[key] == null ? null : decodeDate(map[key] as Object, field: key);

  static DateTime? _dateOrTime(Map<dynamic, dynamic> map, String key) =>
      map[key] == null
      ? null
      : decodeDateOrTime(map[key] as Object, field: key);

  /// ISO-8601 durations, `P[nY][nM][nW][nD][T[nH][nM][nS]]`, at least one
  /// component.
  static final RegExp _durationRe = RegExp(
    r'^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!$)(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?$',
  );

  static final RegExp _blockedUntilRe = RegExp(
    r'^[a-z][a-z0-9_]*\s*>=?\s*\d+\.\d+\.\d+$',
  );

  /// Validates one `blocked_until` condition (`<package> >= <x.y.z>`).
  static void checkBlockedUntil(String condition) {
    if (!_blockedUntilRe.hasMatch(condition.trim())) {
      throw FormatException(
        'Todo "blocked_until" must read '
        '"<package> >= <x.y.z>": "$condition"',
      );
    }
  }

  // ── equality ───────────────────────────────────────────────────────────

  /// Equal when every field is equal (the flat forms are).
  @override
  bool operator ==(Object other) =>
      other is TomItem &&
      other.runtimeType == runtimeType &&
      _deepEquals(other.toMap(), toMap());

  @override
  int get hashCode => Object.hash(id, headline, status, _due);

  @override
  String toString() => 'TomItem($id "$headline" ${status.wire})';
}

/// The stored item type names (D1 §3.1 field 2), as constants for
/// [TomItem.itemTypes].
abstract final class TomTodoItemTypes {
  static const String todo = 'todo';
  static const String reminder = 'reminder';
}

bool _isEmptyValue(Object? value) =>
    value == null ||
    (value is String && value.isEmpty) ||
    (value is List && value.isEmpty) ||
    (value is Map && value.isEmpty);

Object? _deepCopy(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final e in value.entries) '${e.key}': _deepCopy(e.value),
  },
  List() => [for (final v in value) _deepCopy(v)],
  _ => value,
};

List<String> _strings(Object? value) => [
  for (final v in (value as List? ?? const [])) v.toString(),
];

bool _flag(Object? value, String field) {
  if (value == null) return false;
  if (value is bool) return value;
  throw FormatException('Todo "$field" must be true or false, not "$value"');
}

void _known(Map<dynamic, dynamic> map, List<String> fields, String what) {
  for (final key in map.keys) {
    if (!fields.contains(key)) {
      throw FormatException('Unknown $what field: "$key"');
    }
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
