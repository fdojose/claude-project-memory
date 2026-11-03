#!/usr/bin/env python3
"""UserPromptSubmit hook: flag developer messages that look like a correction,
a re-explanation, or a standing instruction, so the session records them.

Reads the hook JSON on stdin. On a match it appends one row to
memory/signals.tsv (time, session, signals, matched phrase; never the message
itself) and prints a short note, which Claude Code adds to the session context.
Pattern matching only, no model. Never blocks a prompt: always exits 0.

Run with --selftest to see how sample messages are classified.
"""
import json
import os
import re
import sys
import time

HEAD = 240      # characters checked for an opening correction
REACH = 600     # characters checked for repeat and remember phrases

# The developer says this was already covered: a memory miss.
REPEAT = re.compile(
    r"\b(we|i|you)( have| had|'ve|'d)? already (told|said|explained|asked|discussed|talked|agreed|decided)\b|"
    r"\bya (te dije|lo dije|dije|hablamos|vimos|lo vimos|lo hablamos|hab[ií]amos)\b|"
    r"\bi (told|asked) you\b|\bas i (said|told)\b|\bcomo (te )?dije\b|\bte (lo )?dije\b|"
    r"\bwe (have |had |'ve )?(already )?(talked|discussed|agreed|decided|been through)\b"
    r".{0,40}\b(times|before|already|again)\b|"
    r"\bat least \d+ times\b|\b(how many|cu[aá]ntas) (times|veces)\b|"
    r"\b(otra vez|de nuevo) (con |lo mismo|el mismo|la misma)|"
    r"\bpor ?qu[eé] volvemos\b|\bvolvemos a (esto|lo mismo)\b|"
    r"^again\b|\bsame (error|problem|mistake|bug|issue) again\b|"
    r"(?<!\bi )\bremember that (we|you|i)\b|\brecuerda que\b",
    re.I)

# A standing instruction for future sessions.
REMEMBER = re.compile(
    r"\bfrom now on\b|\bde ahora en adelante\b|\ba partir de ahora\b|"
    r"\b(always|never|siempre|nunca) (use|do|run|ask|commit|push|edit|write|touch|"
    r"usa|uses|hagas|haz|debes|preguntes|toques)\b|"
    r"\bdon'?t (ever|do that again)\b|\bno (lo )?vuelvas a\b|"
    r"\bremember this\b|\brecuerda esto\b|\bnext time\b|\bla pr[oó]xima vez\b|"
    r"\bpara (el futuro|la pr[oó]xima)\b",
    re.I)

# The message opens by contradicting or stopping the assistant.
CORRECTION = re.compile(
    r"^(no|nope|wrong|incorrect|incorrecto|mal)([\s,.!:]|$)|"
    r"^that'?s (not|wrong)\b|^that is not\b|^this is (not|wrong)\b|"
    r"^not (what|that|right|correct|accepted|working)\b|"
    r"^(wait|espera|para|stop|det[eé]n)[\s,.!]+(what|why|que|qu[eé]|por|no|that|this|you|don'?t)\b|"
    r"^why (did|are|would) you\b|^por ?qu[eé] (hiciste|cambiaste|est[aá]s|usas|usaste)\b|"
    r"^you (didn'?t|did not|missed|forgot|broke|changed|removed|are wrong)\b|"
    r"^still (there|not|the same|failing|broken|wrong|happening)\b|"
    r"^sigue (sin|fallando|igual|mal|pasando)\b|"
    r"^(eso|esto) no\b|^est[aá] mal\b|^te equivoca|^no funciona\b|^no es (eso|as[ií])\b|"
    r"^but (we|you|it|that) (should|shouldn'?t|said|don'?t|didn'?t)\b|^pero (no|eso|as[ií])\b",
    re.I)

# Openers that look like a correction and are not one.
NOT_CORRECTION = re.compile(
    r"^no[\s,.!]+(it works|it worked|worked|thanks|thank you|gracias|problem|worries|"
    r"error\b|a[uú]n\b|yet\b|is late|it'?s late|need\b|hace falta|te preocupes|rush)|"
    r"^no (problem|worries|error|a[uú]n|need|rush)\b|^not (sure|yet|clear|now)\b|"
    r"^no se (pudo|puede|encontr)|^no[\s,.!]+(just thinking|is (it )?possible)",
    re.I)

NOTES = {
    "repeat": (
        "Memory signal (repeat): the developer's message suggests this was already "
        "explained or decided. Check memory/index.md for an entry that covers it and "
        "read that entry. Add one line under Misses in memory/inbox.md: the date, then one "
        "sentence saying what was repeated and where it should have been found. If no "
        "entry covers it, write one once the fact is confirmed."),
    "correction": (
        "Memory signal (correction): the developer's message looks like a correction of "
        "something you said or did. If it is, then once the correct fact is confirmed, "
        "append one short entry to memory/inbox.md: what was wrong, what is right, and a "
        "pointer to the file or evidence. If it is not a correction, ignore this note."),
    "remember": (
        "Memory signal (instruction): the developer's message looks like a standing "
        "instruction for future sessions. If it is, append one short entry to "
        "memory/inbox.md stating it in the developer's terms. If it is not, ignore this note."),
}
ORDER = ("repeat", "correction", "remember")


def classify(prompt):
    """Return [(signal, matched phrase)] for a developer message."""
    text = re.sub(r"\s+", " ", prompt or "").strip()
    if not text or text[0] in "/<":
        return []
    found = []
    m = REPEAT.search(text[:REACH])
    if m:
        found.append(("repeat", m.group(0)))
    m = CORRECTION.search(text[:HEAD])
    if m and not NOT_CORRECTION.search(text[:HEAD]):
        found.append(("correction", m.group(0)))
    m = REMEMBER.search(text[:REACH])
    if m:
        found.append(("remember", m.group(0)))
    return found


SELFTEST = [
    ("correction", "no, all wrong!, when you edit a slideshow you got: <div>"),
    ("correction", "no, just 3 logos"),
    ("correction", "why did you change the branch? this should be multi-document!!"),
    ("correction", "still there: <button type=\"button\">"),
    ("correction", "no, the model is part of the models in Together.ai"),
    ("repeat", "again \"Revisar uno por uno\" do nothing for the user, we have talked about this at least 3 times"),
    ("repeat", "espera, que haces, los modelos a usar estan configurados en la Org, porque volvemos a esto?"),
    ("repeat", "ya recargué crédito, recuerda que vimos que para gráficos complejos no era suficiente"),
    ("remember", "from now on write a plan before implementing"),
    ("remember", "nunca hagas push sin preguntar"),
    ("", "no, it worked, thanks"),
    ("", "not sure understanding this: Where residual risk actually sits"),
    ("", "not yet, launch an agent to check the plan"),
    ("", "wait for the other two agents"),
    ("", "commit and push"),
    ("", "no aun, revisemos la integridad del plan"),
    ("", "/memory-review"),
    ("", "No se pudo generar la toma: Scene 1 has changed since the last video"),
    ("", "wait, I remember that we have to implement the credit system first"),
    ("", "No. Just thinking, keep the 3 funnel process."),
    ("", "why do you suggest tightening the Misses rule?"),
    ("", "Should we build an MCP server? Was this already discussed, and what was concluded?"),
    ("repeat", "We have already talked about this, but now things are improved"),
    ("repeat", "ya hablamos de esto, los modelos vienen de la Org"),
    ("", "how is going?"),
]


def selftest():
    bad = 0
    for want, msg in SELFTEST:
        got = [s for s, _ in classify(msg)]
        ok = (want in got) if want else not got
        bad += not ok
        print("%s  want=%-10s got=%-22s %s" % ("ok  " if ok else "FAIL", want or "-", ",".join(got) or "-", msg[:60]))
    print("%d of %d as expected" % (len(SELFTEST) - bad, len(SELFTEST)))
    return 1 if bad else 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    found = classify(data.get("prompt", ""))
    if not found:
        return 0
    project = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    memory = os.path.join(project, "memory")
    if os.path.isdir(memory):
        ledger = os.path.join(memory, "signals.tsv")
        new = not os.path.exists(ledger)
        with open(ledger, "a") as f:
            if new:
                f.write("time\tsession\tsignals\tmatched\n")
            f.write("%s\t%s\t%s\t%s\n" % (
                time.strftime("%Y-%m-%dT%H:%M:%S"), data.get("session_id", "unknown"),
                ",".join(s for s, _ in found), " | ".join(p[:40] for _, p in found)))
    signals = [s for s, _ in found]
    print(NOTES[next(s for s in ORDER if s in signals)])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
