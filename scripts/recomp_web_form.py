"""A recompiled function as DKR-R's own N64Recomp writes it, from the web's.

A web page's code comes from N64Recomp as N64Recomp-browser patches it
(scripts/build_web.sh), which writes a few things into every function that
DKR-R's desktop build doesn't have: a RECOMP_FUNC_ENTRY line at the top, a
RECOMP_TAIL_CALL in front of a tail call, a load to $zero as "(void)(...)"
where the desktop writes "0 = ...", and a guard on division by zero
(WebAssembly traps). DKR-R's pipelines pin the functions they change or copy
by the hash of their desktop text (scripts/save_layout_pipeline.py,
character_portrait_pipeline.py, camera_scene_kernel.py,
generate_visual_model_kernel.py), so they hash, and the kernels copy, this
form of a body. It is exact or it is caught: a web body that doesn't come
back to the reviewed text misses its pin, as a changed one would.

Text from DKR-R's own N64Recomp has none of these, and comes back as it is.
"""

from __future__ import annotations

import re

_ENTRY = re.compile(r"^    RECOMP_FUNC_ENTRY\(\w+\)\n", re.M)
_ZERO = re.compile(r"^(\s*)\(void\)\((.*)\);$", re.M)
_DIV32 = re.compile(r"if \((?:S32|U32)\(\S+?\) == 0\) \{ [^{}]* \} else \{ (.*?) \}$", re.M)
_DIV64 = re.compile(r"if \((?:S64|U64)\(\S+?\) == 0\) \{ [^{}]* \} else (DDIVU?\(.*?\);)$", re.M)


def desktop_form(body: str) -> str:
    body = _ENTRY.sub("", body)
    body = body.replace("RECOMP_TAIL_CALL ", "")
    body = _ZERO.sub(r"\g<1>0 = \g<2>;", body)
    body = _DIV32.sub(r"\g<1>", body)
    return _DIV64.sub(r"\g<1>", body)
