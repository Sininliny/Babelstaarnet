"""Protocol fixture: no Argos models, network access, or third-party packages."""
import json
import sys
import time

for line in sys.stdin:
    texts = json.loads(line)["texts"]
    if "__hang__" in texts:
        time.sleep(90)
    if any(text.startswith("__slow") for text in texts):
        time.sleep(0.5)
    if "__exit__" in texts:
        sys.exit(12)
    if "__stderr__" in texts:
        sys.stderr.write("x" * 150_000 + "\n")
        sys.stderr.flush()
    values = ["en:" + text for text in texts]
    if "__bad_count__" in texts:
        values = []
    print(json.dumps({"translations": values}, ensure_ascii=False), flush=True)
