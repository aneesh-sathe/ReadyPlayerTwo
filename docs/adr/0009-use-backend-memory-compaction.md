---
status: proposed
---

# Use backend Memory Compaction

When a future memory-enabled release reaches its Memory Budget, it may send `memory.md` to a backend LLM for compaction rather than run a model on-device. This transmits a concentrated set of potentially sensitive facts; the decision remains proposed until the security review resolves consent, provider retention and training, encryption, access, and deletion.

Backend Memory Compaction is excluded from v1.
