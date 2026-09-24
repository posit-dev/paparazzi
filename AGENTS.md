**Kata is the system of record** (the `kata` CLI issue tracker; the session environment provides its usage conventions). One issue per work item; decisions and dispositions land on issues, never only in chat scrollback. See `kata quickstart --agent` for usage details.

## Work Mechanics

1. **One kata issue per work item**, parented appropriately; claim with
   `work.attention ok`, stamp `work.branch`, keep the attention pair
   truthful, close with evidence. Never end a session with the signal stale.
1. **Small conventional commits**, one logical change each, kata refs in the
   body.
1. **Escalate early on these tripwires** — each is a known money pit:
   anything touching the init/restore window; anything that wants a timer,
   a queue, or a second flag to manage ordering; anything that stores
   display-shaped content; anything where the fix is "add a guard for the
   guard." Stop and consult before building.
1. **All comments are load-bearing** — only use comments to capture context that
   will be relevant in the future. Never include local refs (like kata or
   roborev), always inline important context from those refs. Regardless,
   comments should be minimal and included only when necessary.
