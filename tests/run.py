"""Runs the Peer Review logic tests against a stubbed WoW client.  pip install lupa"""
import pathlib, sys
import lupa.lua51 as L

root = pathlib.Path(__file__).resolve().parent.parent
failed = False
for suite in ("tests.lua", "tests_regional.lua"):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lines = []
    lua.globals().PYLOG = lambda *a: lines.append(" ".join(str(x) for x in a))
    lua.execute((root / "tests" / "stubs.lua").read_text(encoding="utf-8"))
    lua.execute("function LOG(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end PYLOG(table.concat(t, ' ')) end")
    ns = lua.eval("{}")
    lua.globals().NS = ns
    load = lua.eval("function(src, name) local f, e = loadstring(src, name); if not f then error(e) end; return f end")
    for f in ("Core.lua", "Sync.lua", "UI.lua"):
        load((root / f).read_text(encoding="utf-8"), "@" + f)("PeerReview", ns)
    lua.execute((root / "tests" / suite).read_text(encoding="utf-8"))
    bad = [l for l in lines if l.startswith("FAIL") or "FAILED" in l or l.startswith("PRINTED")]
    print(f"{suite}: {sum(l.startswith('ok') for l in lines)} passed, {len([l for l in lines if l.startswith('FAIL')])} failed")
    for l in bad:
        print("  " + l)
    failed = failed or bool(bad)
sys.exit(1 if failed else 0)
