# signoff

This add-on holds no code. The sign-off event handler (the adapter that turns
sign-off board answers into hold answers) was a verbatim copy of a Firstmate
file. Upstream has since removed its source, and the current runner cannot
dispatch an add-on adapter, so the copy is out of this directory.

- The adapter and its journey test are in git history: `52a443c`
  (`signoff/bin/fm-procevent-signoff.sh`, `signoff/tests/fm-procevent-signoff.test.sh`).
- Reviving it needs one upstream seam (register lookup and the answer ack);
  the seam is not implemented here. Until then this add-on is empty and the
  copied-line count in `signoff/` is 0.
