# Vita3K fork patch series

Our commits on top of upstream Vita3K, exported from `third_party/vita3k`
(branch `ss-delta`) with:

    git -C third_party/vita3k format-patch -o ../../patches/vita3k <base>..ss-delta

Base: upstream `b75d5e62` (see [D5](../../docs/decisions.md)). To rebuild the
fork from scratch: clone upstream with submodules, check out the base,
create branch `ss-delta`, then `git am patches/vita3k/*.patch`.
