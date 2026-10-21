# Tom Modules

Reusable components of the Tom workspace on a business level: shared models
and the code that reads, writes, serialises and changes them. They are not of
general interest the way `tom_basics` or `tom_core` are, but several Tom
applications use the same model, so it lives here once.

| Package | What it is |
| --- | --- |
| [`tom_todo_model`](tom_todo_model/) | The shared todo model (`TomTodo`) and the `*.todo.yaml` file codec. |

Each package is published on pub.dev on its own and has its own README and
changelog.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
