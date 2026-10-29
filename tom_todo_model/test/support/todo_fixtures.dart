/// Todo files shaped like the workspace's own: header comments, a generated
/// block, the schema line, block scalars, a key the model does not know,
/// comments between items.
library;

const String questTodoFile = '''# Garden Quest - Todo List
# yaml-language-server: \$schema=../schemas/todo.schema.json

quest: garden
updated: "2026-10-01"

# ACTIVE SET: 3 todos in one series.
#   gx1..gx3 — the beds.
todos:
  - id: gx1_ajka-plant
    title: Plant the beds
    description: Plant the spring beds.
    status: not-started   # first
    notes: Soil first.
    created: "2026-10-01"

  # Watering needs a decision on timing.
  - id: gx2_ajka-water
    title: Water
    description: |-
      Twice a week.
      More in summer.
    status: in-progress
    x_note: kept as written
    tags: []
    notes: null

  - id: gx3_ajka-harvest
    title: Harvest
    description: "Harvest: the beans."
    status: completed
    decisions:
      - summary: When
        decision_needed: Morning or evening?
        decision: Mornings.
''';

/// A schema in the workspace schema's shape, cut down to what the tests
/// exercise.
const String todoSchema = '''
{
  "\$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["todos"],
  "properties": {
    "quest": {"type": ["string", "null"]},
    "updated": {"type": ["string", "null"]},
    "created": {"type": ["string", "null"]},
    "author": {"type": ["string", "null"]},
    "todos": {"type": "array", "items": {"\$ref": "#/\$defs/todo"}}
  },
  "additionalProperties": false,
  "\$defs": {
    "todo": {
      "type": "object",
      "required": ["id", "description", "status"],
      "properties": {
        "id": {"type": "string"},
        "title": {"type": ["string", "null"]},
        "description": {"type": "string"},
        "status": {"enum": ["not-started", "in-progress", "blocked",
            "decision-needed", "completed", "cancelled"]},
        "priority": {"enum": ["low", "medium", "high", "critical", null]},
        "notes": {"type": ["string", "null"]},
        "tags": {"type": ["array", "null"], "items": {"type": "string"}},
        "created": {"type": ["string", "null"]},
        "updated": {"type": ["string", "null"]},
        "archived": {"type": ["string", "null"]},
        "deleted": {"type": ["string", "null"]},
        "estimate": {"type": ["string", "null"]},
        "due": {"type": ["string", "null"]},
        "x_note": {"type": "string"},
        "completed_date": {"type": ["string", "null"]},
        "completed_by": {"type": ["string", "null"]},
        "author": {"type": ["string", "null"]},
        "scope": {"type": ["object", "null"]},
        "references": {"type": ["array", "null"]},
        "dependencies": {"type": ["array", "null"]},
        "blocked_by": {"type": ["array", "null"]},
        "blocking": {"type": ["array", "null"]},
        "blocked_until": {"type": ["array", "null"]},
        "decisions": {"type": ["array", "null"]}
      },
      "additionalProperties": false
    }
  }
}
''';
