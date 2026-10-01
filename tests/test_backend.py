import importlib.machinery
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "bin", "blue-pencil")

loader = importlib.machinery.SourceFileLoader("blue_pencil", SCRIPT)
spec = importlib.util.spec_from_loader("blue_pencil", loader)
bp = importlib.util.module_from_spec(spec)
loader.exec_module(bp)


def tip_line(kind="clarity", title="T", body="B", quote="Q"):
    return json.dumps({"kind": kind, "title": title, "body": body, "quote": quote})


class ParseTests(unittest.TestCase):
    def test_valid_and_normalised(self):
        t = bp.parse_tip(tip_line(kind="  Keep "))
        self.assertEqual(t["kind"], "keep")

    def test_rejects(self):
        for line in ["", "```json", "```", "hello", "[1]", "{bad json}",
                     tip_line(kind="praise"), tip_line(title="  "),
                     json.dumps({"kind": "tone"})]:
            self.assertIsNone(bp.parse_tip(line), line)

    def test_truncation(self):
        t = bp.parse_tip(tip_line(title="x" * 500, body="y" * 5000, quote="z" * 900))
        self.assertEqual((len(t["title"]), len(t["body"]), len(t["quote"])), (120, 1200, 300))

    def test_missing_optional(self):
        t = bp.parse_tip(json.dumps({"kind": "tone", "title": "x"}))
        self.assertEqual((t["body"], t["quote"]), ("", ""))

    def test_stream_split_chunks(self):
        s = bp.TipStream()
        line = tip_line(title="één") + "\n"
        out = []
        for i in range(0, len(line), 7):
            out += s.feed(line[i:i + 7])
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["title"], "één")

    def test_stream_fences_and_trailing(self):
        s = bp.TipStream()
        out = s.feed("```json\n" + tip_line() + "\nchatter\n" + tip_line(kind="KEEP"))
        self.assertEqual(len(out), 1)
        out += s.finish()
        self.assertEqual([t["kind"] for t in out], ["clarity", "keep"])

    def test_clamp(self):
        self.assertEqual(bp.clamp_max_tips(1), 3)
        self.assertEqual(bp.clamp_max_tips(99), 10)
        self.assertEqual(bp.clamp_max_tips("7"), 7)
        self.assertEqual(bp.clamp_max_tips(None), 6)

    def test_prompt_substitution(self):
        p = bp.load_system_prompt(4)
        self.assertNotIn("{{MAX_TIPS}}", p)
        self.assertIn("at most 4 tips", p)

    def test_classify(self):
        self.assertEqual(bp.classify_failure("Invalid API key · Please run /login"), "not-signed-in")
        self.assertEqual(bp.classify_failure("You've hit your usage limit"), "rate-limit")
        self.assertEqual(bp.classify_failure("boom"), "failed")

    def test_adapters(self):
        c = bp.ClaudeAdapter()
        self.assertEqual(c.handle({"type": "system", "subtype": "init"})[0], "init")
        ev = {"type": "stream_event", "event": {"type": "content_block_delta",
                                                "delta": {"type": "text_delta", "text": "hi"}}}
        self.assertEqual(c.handle(ev), ("text", "hi"))
        self.assertEqual(c.handle({"type": "result", "is_error": True, "result": "bad"}),
                         ("error", "bad"))
        x = bp.CodexAdapter()
        self.assertEqual(x.handle({"type": "item.completed",
                                   "item": {"type": "agent_message", "text": "a"}}), ("text", "a\n"))
        self.assertEqual(x.handle({"type": "turn.failed", "error": {"message": "m"}}), ("error", "m"))

    def test_command_lines(self):
        cmd = bp.ClaudeAdapter().command("claude", "haiku", "SYS", "/w")
        self.assertIn("--tools", cmd)
        self.assertEqual(cmd[cmd.index("--tools") + 1], "")
        cmd = bp.CodexAdapter().command("codex", "m", "SYS\nline", "/w")
        self.assertEqual(cmd[-1], "-")
        self.assertIn('developer_instructions="SYS\\nline"', cmd)


class FakeCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def fake(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write("#!/usr/bin/python3\n" + textwrap.dedent(body))
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

    def advise(self, req, home=None):
        env = dict(os.environ, PATH=self.bin + os.pathsep + "/usr/bin:/bin", HOME=home or self.tmp.name)
        p = subprocess.run([SCRIPT, "advise"], input=json.dumps(req), capture_output=True,
                           text=True, env=env, timeout=60)
        events = [json.loads(l) for l in p.stdout.splitlines()]
        return p.returncode, events

    def claude_ok(self, texts):
        self.fake("claude", """
            import sys, json
            sys.stdin.read()
            print(json.dumps({"type":"system","subtype":"init"}), flush=True)
            for t in %r:
                print(json.dumps({"type":"stream_event","event":{"type":"content_block_delta",
                    "delta":{"type":"text_delta","text":t}}}), flush=True)
            print(json.dumps({"type":"result","is_error":False,"result":""}), flush=True)
        """ % (texts,))

    def test_empty_text(self):
        rc, ev = self.advise({"provider": "claude", "text": "  \n "})
        self.assertEqual(rc, 1)
        self.assertEqual([e["type"] for e in ev], ["error"])
        self.assertEqual(ev[0]["code"], "empty-text")

    def test_not_installed(self):
        rc, ev = self.advise({"provider": "codex", "text": "hi"}, home="/nonexistent-home")
        self.assertEqual(rc, 1)
        self.assertEqual(ev[-1]["code"], "not-installed")

    def test_claude_streaming_and_cap(self):
        lines = [tip_line(title="t%d" % i) + "\n" for i in range(5)]
        self.claude_ok(["```json\n", lines[0][:10], lines[0][10:] + lines[1]] + lines[2:] + ["noise\n"])
        rc, ev = self.advise({"provider": "claude", "text": "hello", "maxTips": 3})
        self.assertEqual(rc, 0)
        types = [e["type"] for e in ev]
        self.assertEqual(types[:3], ["status", "status", "status"])
        self.assertEqual([e["phase"] for e in ev[:3]], ["starting", "reading", "writing"])
        self.assertEqual(types.count("tip"), 3)
        self.assertEqual(ev[-1], {"type": "done", "count": 3})

    def test_bad_output(self):
        self.claude_ok(["just some prose\n"])
        rc, ev = self.advise({"provider": "claude", "text": "hello"})
        self.assertEqual((rc, ev[-1]["code"]), (1, "bad-output"))
        self.assertEqual(sum(e["type"] in ("done", "error") for e in ev), 1)

    def test_auth_error(self):
        self.fake("claude", """
            import sys, json
            sys.stdin.read()
            print(json.dumps({"type":"result","is_error":True,"result":"Invalid API key - Please run /login"}))
            sys.exit(1)
        """)
        rc, ev = self.advise({"provider": "claude", "text": "hello"})
        self.assertEqual(ev[-1]["code"], "not-signed-in")

    def test_rate_limit_stderr(self):
        self.fake("codex", """
            import sys
            sys.stdin.read()
            sys.stderr.write("You've hit your usage limit")
            sys.exit(1)
        """)
        rc, ev = self.advise({"provider": "codex", "text": "hello"})
        self.assertEqual(ev[-1]["code"], "rate-limit")

    def test_generic_failure(self):
        self.fake("codex", """
            import sys
            sys.stdin.read()
            sys.stderr.write("kaboom")
            sys.exit(2)
        """)
        rc, ev = self.advise({"provider": "codex", "text": "hello"})
        self.assertEqual(ev[-1]["code"], "failed")
        self.assertIn("kaboom", ev[-1]["message"])

    def test_codex_stream_and_stdin_not_argv(self):
        self.fake("codex", """
            import sys, json
            data = sys.stdin.read()
            assert "SECRETDRAFT" in data and not any("SECRETDRAFT" in a for a in sys.argv)
            assert "<goal>" in data and "<draft>" in data
            print(json.dumps({"type":"thread.started"}), flush=True)
            msg = %r + "\\n" + %r
            print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":msg}}), flush=True)
            print(json.dumps({"type":"turn.completed"}), flush=True)
        """ % (tip_line(kind="TONE"), tip_line(kind="keep")))
        rc, ev = self.advise({"provider": "codex", "text": "SECRETDRAFT", "goal": "g", "tone": "t"})
        self.assertEqual(rc, 0)
        self.assertEqual([e["tip"]["kind"] for e in ev if e["type"] == "tip"], ["tone", "keep"])

    def test_sigterm_kills_child(self):
        marker = os.path.join(self.bin, "pid")
        self.fake("claude", """
            import os, sys, time, json
            open(%r, "w").write(str(os.getpid()))
            print(json.dumps({"type":"system","subtype":"init"}), flush=True)
            time.sleep(60)
        """ % marker)
        env = dict(os.environ, PATH=self.bin + os.pathsep + "/usr/bin:/bin", HOME=self.tmp.name)
        p = subprocess.Popen([SCRIPT, "advise"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             text=True, env=env)
        p.stdin.write(json.dumps({"provider": "claude", "text": "hello"}))
        p.stdin.close()
        import time
        for _ in range(100):
            if os.path.exists(marker) and open(marker).read():
                break
            time.sleep(0.1)
        pid = int(open(marker).read())
        p.terminate()
        p.wait(timeout=10)
        time.sleep(0.3)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_scan_not_installed(self):
        env = dict(os.environ, PATH="/usr/bin:/bin", HOME="/nonexistent-home")
        p = subprocess.run([SCRIPT, "scan"], capture_output=True, text=True, env=env, timeout=60)
        data = json.loads(p.stdout)
        self.assertEqual([x["id"] for x in data["providers"]], ["claude", "codex"])
        self.assertFalse(any(x["installed"] for x in data["providers"]))

    def test_scan_fake(self):
        self.fake("claude", """
            import sys
            if "--version" in sys.argv: print("9.9.9 (Claude Code)")
            else: print('{"loggedIn": true}')
        """)
        self.fake("codex", """
            import sys
            a = sys.argv[1:]
            if a == ["--version"]: print("codex-cli 1.2.3")
            elif a[0] == "login": print("Logged in using ChatGPT")
            else: print('{"models":[{"slug":"a","display_name":"A","visibility":"list"},{"slug":"h","display_name":"H","visibility":"hide"}]}')
        """)
        env = dict(os.environ, PATH=self.bin + os.pathsep + "/usr/bin:/bin", HOME=self.tmp.name)
        p = subprocess.run([SCRIPT, "scan"], capture_output=True, text=True, env=env, timeout=60)
        c, x = json.loads(p.stdout)["providers"]
        self.assertEqual((c["version"], c["signedIn"], c["defaultModel"]), ("9.9.9", True, "sonnet"))
        self.assertEqual((x["version"], x["signedIn"], x["models"], x["defaultModel"]),
                         ("1.2.3", True, [{"id": "a", "name": "A"}], "a"))


if __name__ == "__main__":
    unittest.main()
