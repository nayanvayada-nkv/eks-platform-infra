# ADR 0011: Multi-tenant RAG with pgvector on Aurora and Claude on Amazon Bedrock

- Status: accepted (code written 27 Nov 2026, not applied)
- Context: Phase 9 (vector DB + RAG, tenant-filtered search, private endpoint + KMS). The FDE track
  needs a customer-facing use case on top of it. Options were pgvector, OpenSearch Serverless, Qdrant.
- Decisions:
  1. **pgvector on the existing Aurora PostgreSQL** (you chose it). No new database to secure, back up,
     replicate or pay for: IAM logins, KMS, private subnets, NetworkPolicy and the Frankfurt global
     database already apply. HNSW index with cosine distance on 1024-dimension Titan vectors.
     When to move: tens of millions of chunks, heavy hybrid keyword + vector search, or vector load that
     competes with transactional load -> OpenSearch (or a dedicated vector store) behind the same API.
  2. **Tenant isolation in the database (row-level security), not only in the app.** Each request sets
     `app.tenant_id` for its transaction; a FORCE'd RLS policy filters every read and checks every write.
     An application bug cannot leak another tenant's chunks. Iterative HNSW scans keep top-k complete
     under the filter (pgvector 0.8+).
  3. **Tenants are declared in Git** (`gitops/workloads/backend/tenants`): only a SHA-256 of each
     256-bit API key is stored; the db-migrate job syncs the list (create/update/disable). Onboarding
     and offboarding are reviewed pull requests with an audit trail.
  4. **Models on Amazon Bedrock, no API keys:** Titan Text Embeddings V2 (`bedrock-runtime`) and Claude
     Opus 5.5 through Claude in Amazon Bedrock (`bedrock-mantle`, Messages API, official Anthropic SDK
     `AnthropicBedrockMantle`). Pod Identity signs requests; VPC interface endpoints for both keep the
     traffic private. Mumbai is served through Bedrock's global endpoint (requests may be processed in
     another region; a data-residency customer would need a regional/geographic option).
  5. **Grounded answers:** retrieved chunks go in as document blocks with citations enabled, effort `low`,
     a 4096-token cap. The system prompt treats document text as data (prompt-injection defence) and
     tells the model to say when the answer is not in the documents. No chunks -> no model call.
  6. **Refusals:** server-side fallbacks are not available on Bedrock, so the SDK's client-side
     `BetaRefusalFallbackMiddleware` retries a policy decline once on Claude Opus 4.8; a final refusal
     returns HTTP 422 and is counted (`rag_llm_refusals_total`).
  7. **Cost controls:** answers cached in Valkey for 10 minutes per tenant + question, token counters
     with a `RagTokenSpendHigh` alert, input limits (question 1000 chars, document 200k chars).
- Consequences: two more interface endpoints (~$0.08/hour in dev). The model choice is a variable
  (`LLM_MODEL`); Claude Haiku 5.5 would cut answer cost a lot - that is a product decision, measured
  with an eval set, not a default. IAM for `bedrock-mantle:CreateInference` is `Resource: "*"` because
  AWS documents no model-level ARN for it yet; revisit when it does.
