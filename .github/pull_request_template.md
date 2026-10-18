## What

<!-- What changes, and why? Link the issue if there is one ("Closes #123"). -->

## Checked

<!-- How you made sure it works. Delete what doesn't apply. -->

- [ ] `odin check .` and the tests of the packages I touched (`odin test dom`, `layout`, `http`, `loader`, `browser`, `ui`, `vendor/lexbor`)
- [ ] new behavior has a test
- [ ] for visible changes: a page in `testdata/`, compared with Firefox (`tools/compare.py`)
- [ ] for changes that can affect real pages: the pages in `tools/pages.txt` before and after
- [ ] README / `docs/rendering-gaps.md` updated if something user-visible changed

## Notes

<!-- Anything reviewers should know: what is not done yet, open questions. -->
