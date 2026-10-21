# Reporting

Read before any message to a channel. The chat UI always gets a summary. A channel gets a
message only when `report_channel` and `report_chat` are set, and only when there is
something to say.

| Run outcome | Channel message |
| --- | --- |
| Quiet sweep: nothing new queued, nothing fixed | **none.** Silence is the correct report. |
| Sweep that queued rows | one line: the boundary and what was queued, counted by kind |
| Verified fix opened | the PR link, the claim that was wrong, one line |
| Release pass opened | the boundary, the PR link, corrections and additions as separate counts, and anything held back |
| Audit | only when `audit_report: enabled`, or when anything is red |

- **Lead with the result.** A few lines. Link the PR, then stop.
- **A correction is an admission** that the site was publishing a wrong claim. Say so
  plainly, and never call an addition a correction.
- **Never report a missed or slipped release from an early check**
  ([verification.md](verification.md) → **The boundary**). Report what the boundary is at
  the moment of checking.
- **Never quote unreleased or flagged work** in a channel others can read, beyond its
  count.
- Send with `mcp__platform-outbound__send_channel_message` (`channel` = `report_channel`,
  `chatId` = `report_chat`). A failed send is reported in the chat UI and logged; it is
  never retried in a loop.
