# Blue Pencil

<p align="center">
  <img src="assets/blue-pencil.gif" width="720" alt="Blue Pencil: a wall of stock AI phrases, then the panel. A blog intro gets notes in the margin — the hook arrives late, the stock opening hides your voice, keep the little red dots — with the slop phrase highlighted. It points. It never rewrites.">
</p>

**No AI slop. A writing pad for Omarchy with an AI editor in the margin: it gives you notes on your own text and never writes it for you.**

## Why this exists

You know the text. You have read it in a hundred LinkedIn posts, cover
letters and product pages this year. It opens by saying something is
"more important than ever". It lists three things where two would do. It
is warm, balanced, perfectly punctuated, and you have forgotten it before
you reach the end. Nobody wrote it, and it shows. People have a word for
it now: **AI slop**.

The tempting fix is to let the AI write a first draft and polish it a
little. The trouble is that the draft wins. Research on AI-assisted
writing keeps finding the same thing: when a language model rewrites or
"improves" a text, the writer's voice drains out of it. Personal
anecdotes disappear, "I" becomes "one", rough edges are sanded down, and
texts from different people start to sound alike
(see [How LLMs Distort Our Written Language](https://arxiv.org/abs/2603.18161),
[AI Suggestions Homogenize Writing Toward Western Styles](https://arxiv.org/abs/2409.11360)
and [Does Writing with Language Models Reduce Content Diversity?](https://arxiv.org/abs/2309.05196)). Asking the model nicely to
"keep my voice" helps a bit. It does not fix it.

The way you write is part of who you are: the joke only you would make,
the detail you remember because you were there, the slightly blunt
sentence your colleagues know you by. That is what readers trust, and it
is worth keeping.

So Blue Pencil splits the work the way it used to be split. **You write.**
The AI gets the job editors have done for a century with a blue pencil in
the margin: point at what is unclear, notice when the structure works
against you, warn you about the pitfall you are walking into, and tell you
what is so typically you that you should leave it alone. It is not
allowed to write a single sentence for you. What you send out is still
yours, only sharper.

## Features

- **Write, or paste.** A goal field (*what should this text achieve?*), a tone
  field (*how should it feel?*), and a large editor.
- **Get advice.** The panel grows a margin column on the right and the notes
  stream in one by one, while a status line shows what the AI is doing and how
  long it has taken. You can cancel at any time.
- **Notes you can tick off.** Each note has a bold title, a short explanation
  and a label — *Structure*, *Clarity*, *Pitfall*, *Tone* or *Keep*. Ticking one
  strikes it through and folds it away; open notes stay on top. Hover a note
  and the words it is about light up in your text.
- **Your voice is protected.** The system prompt
  ([`prompts/system.md`](prompts/system.md)) forbids rewrites and example
  sentences, treats quirks, dialect and first person as features rather than
  errors, and asks for one or two *Keep* notes about what already works.
  The advice comes back in the language you write in.
- **History.** Every text is saved automatically, with its goal, tone, notes
  and ticks. Open an older one, delete one, or clear them all.
- **Uses what you already have.** Claude Code or Codex, whichever is installed
  and signed in, with a model of your choice. No API keys, no extra accounts.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
  and/or [Codex](https://github.com/openai/codex) (`codex`), signed in
- `/usr/bin/python3` (standard library only)

## Install

```bash
omarchy plugin add https://github.com/hpolthof/omarchy-blue-pencil.git --enable
```

The installer shows what it is about to do and asks you to confirm in the
terminal. When there is no terminal to answer in (a script, an AI agent), add
`--yes` to skip the prompt.

A quill appears on the right of the bar. Click it to open Blue Pencil. To put
it somewhere else:

```bash
omarchy bar move io.github.hpolthof.blue-pencil --section left   # or center
```

### First run

The first time you open it, Blue Pencil asks whether it may scan for AI tools.
Nothing is scanned before you press **Scan for AI tools**. The scan only runs
version and sign-in checks (`claude auth status`, `codex login status`,
`codex debug models`) — nothing you write is involved. Pick a provider and a
model and start writing. You can also skip and set it up later under
**Settings**; the editor and history work without any AI.

## Keyboard

| Where | Key | Action |
|---|---|---|
| Anywhere | `Ctrl+Enter` | Get advice |
| | `Ctrl+N` | New text |
| | `Ctrl+H` | History |
| | `Ctrl+,` | Settings |
| | `Esc` | Back / close |
| Editor | `Tab` / `Shift+Tab` | Goal → Tone → Text |
| History | `j` `k` / arrows, `Enter` | Move, open |
| | `x` / `Delete` | Delete (asks first) |

Blue Pencil does not bind a global shortcut. To open it with one, add a bind
of your own that runs:

```bash
omarchy-shell io.github.hpolthof.blue-pencil toggle
```

## Privacy and safety

- Your text leaves your machine **only when you press Get advice**, and only
  to the provider you selected, through its own CLI.
- The text is passed to the CLI on standard input, never on the command line,
  so it does not show up in process listings.
- The CLI runs headless in an empty temporary directory that is removed
  afterwards, with **no tools**: Claude Code with `--tools ""` and no
  settings, MCP servers, skills or session history; Codex with a read-only
  sandbox, web search off and its shell, browser, apps and plugin features
  disabled.
- All text from you or the AI is rendered as plain text.

### Where things are stored

| What | Where |
|---|---|
| Texts, notes and ticks | `~/.local/state/omarchy/blue-pencil/history.json` |
| Settings (provider, model, max notes, last scan) | `~/.config/omarchy/blue-pencil/settings.json` |

Both are written atomically. Remove the plugin with
`omarchy plugin remove io.github.hpolthof.blue-pencil`; delete the two folders
above if you also want your texts gone.

## How it works

```
BarWidget.qml   host: state, processes, IPC, bar button
Store.qml       history + settings persistence (FileView, atomic writes)
Model.js        pure helpers
Panel.qml       the panel: editor, margin column, history, setup
bin/blue-pencil scan / advise backend (Python, stdlib only)
prompts/system.md  the editor's brief
```

`bin/blue-pencil advise` reads one JSON request on stdin and writes JSON Lines
events (`status`, `tip`, `done`, `error`) to stdout, so notes appear as soon as
each one is complete. Run the backend tests with:

```bash
python3 -m unittest tests.test_backend
```

## License

MIT © Paul Olthof
