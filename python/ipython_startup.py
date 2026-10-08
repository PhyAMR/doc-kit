# doc-kit: linked by install.sh as ~/.ipython/profile_default/startup/50-doc-kit.py.
# In a kernel started by Quarto for a book or report (phu-* formats), set
# the plot style (phu.py). Output is left alone. PHU_DISPLAY=0 turns it off.
def _doc_kit_setup():
    import os
    import sys

    if not os.environ.get("QUARTO_DOCUMENT_PATH") or os.environ.get("PHU_DISPLAY") == "0":
        return
    here = os.path.dirname(os.path.realpath(__file__))
    if here not in sys.path:
        sys.path.append(here)
    import phu

    if phu.wants_look():
        phu.setup()


try:
    _doc_kit_setup()
except Exception as err:  # never break a kernel over looks
    print(f"doc-kit: phu display helpers not loaded ({err})")
del _doc_kit_setup
