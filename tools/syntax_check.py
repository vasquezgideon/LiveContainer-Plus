import sys, os, subprocess
import tree_sitter_swift, tree_sitter_objc
from tree_sitter import Language, Parser

SW = Parser(Language(tree_sitter_swift.language()))
OC = Parser(Language(tree_sitter_objc.language()))

def errors(parser, src):
    tree = parser.parse(src)
    out = []
    def walk(n):
        if n.type == "ERROR" or n.is_missing:
            out.append((n.start_point[0] + 1, n.type, src[n.start_byte:n.end_byte][:60].decode('utf8', 'replace')))
            return
        for c in n.children:
            walk(c)
    walk(tree.root_node)
    return out

def check(path, base_path=None):
    ext = os.path.splitext(path)[1]
    parser = SW if ext == ".swift" else OC
    cur = errors(parser, open(path, 'rb').read())
    base = errors(parser, open(base_path, 'rb').read()) if base_path and os.path.exists(base_path) else []
    return cur, base

if __name__ == "__main__":
    work, clean = sys.argv[1], sys.argv[2]
    files = subprocess.check_output(["git", "-C", work, "ls-files", "-m", "-o", "--exclude-standard"], text=True).split()
    bad = 0
    for rel in files:
        if os.path.splitext(rel)[1] not in (".swift", ".m", ".h"): continue
        cur, base = check(os.path.join(work, rel), os.path.join(clean, rel))
        status = "ok " if len(cur) <= len(base) else "ERR"
        if status == "ERR": bad += 1
        print(f"{status} {rel}: parse errors {len(cur)} (baseline {len(base)})")
        if status == "ERR":
            for e in cur[:8]: print("    ", e)
    print("files with NEW parse errors:", bad)
