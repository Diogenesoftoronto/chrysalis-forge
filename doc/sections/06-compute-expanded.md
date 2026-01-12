## 6. Decentralized Compute Integration (Expanded)

### 6.1 Use Cases (Detailed)

#### 6.1.1 Finetuning Base Models
**Goal**: Customize foundation models on Chrysalis-specific task distributions

**Data sources**:
- Sanitized traces from evals.jsonl (user opt-in)
- Synthetic data generated from elite agent demos
- Public coding datasets (e.g., The Stack)

**Expected outcomes**:
- Model better understands Chrysalis tool calling
- Improved performance on file-edit, vcs operations
- Faster convergence for new task types

#### 6.1.2 Reinforcement Learning from Feedback
**Goal**: Train policies via GEPA-style iterative improvement

**RL Signal sources**:
- Binary success/failure from eval-store
- User corrections (implicit negative signal)
- GEPA feedback loops
- Automated test suite results

**Approach**: 
- GRPO (Group Relative Policy Optimization) as used by DeepSeek
- Async RL as demonstrated by Prime Intellect INTELLECT-2

#### 6.1.3 Distributed Evaluation
**Goal**: Evaluate agent configs across diverse environments

**Why distributed**:
- Different OS environments (Linux, macOS, Windows)
- Different project types (Rust, Python, JavaScript)
- Different model backends (local, API)
- Parallelism for faster iteration

### 6.2 Platform Deep Dives

#### 6.2.1 Akash Network

**Overview**: Decentralized cloud marketplace for compute resources

**Proven Capabilities** (from Akash blog):
- Foundation model training with 32x A100 80GB GPUs
- 1024 vCPUs, 4096GB RAM, 32TB NVMe storage
- Ray cluster orchestration for distributed training

**Cost Model**:
- No static server costs
- Pay per deployment (AKT tokens or USDC)
- ~60-80% cheaper than AWS/GCP for GPU workloads

**SDL (Stack Definition Language) Example**:
```yaml
version: "2.0"
services:
  trainer:
    image: chrysalis/trainer:latest
    env:
      - JOB_ID=${JOB_ID}
      - MODEL=llama3-8b
      - DATA_REPO=git@github.com:user/traces.git
    expose:
      - port: 8080
        as: 80
        to:
          - global: true
profiles:
  compute:
    trainer:
      resources:
        cpu:
          units: 8
        memory:
          size: 64Gi
        gpu:
          units: 1
          attributes:
            vendor:
              nvidia:
                - model: a100
        storage:
          size: 100Gi
  placement:
    dcloud:
      pricing:
        trainer:
          denom: uakt
          amount: 1000
deployment:
  trainer:
    dcloud:
      profile: trainer
      count: 1
```

**Citation**: [Akash Foundation Model Training](https://akash.network/blog/foundation-ai-model-training-on-akash/)

#### 6.2.2 Tashi Network

**Overview**: Real-time coordination layer for distributed systems

**Key Innovation**: Leaderless DAG consensus with <50ms finality

**Architecture**:
```
┌─────────────────────────────────────────┐
│             Tashi Network               │
├─────────────────────────────────────────┤
│  Vertex Layer (Free coordination)       │
│  - Session management                   │
│  - Peer discovery                       │
│  - State synchronization                │
├─────────────────────────────────────────┤
│  Lattice Layer (Metered infrastructure) │
│  - Compute resources                    │
│  - Storage                              │
│  - Bandwidth                            │
├─────────────────────────────────────────┤
│  Proof of Coordination                  │
│  - Verifiable by anyone                 │
│  - Rewarded based on contribution       │
│  - Settled on public blockchains        │
└─────────────────────────────────────────┘
```

**Best For Chrysalis**:
- Real-time RL update coordination
- Multi-agent session synchronization
- Low-latency model update propagation

**Citation**: [Tashi Network](https://tashi.network/)

#### 6.2.3 Prime Intellect

**Overview**: Infrastructure for globally distributed AI training

**INTELLECT-2 Breakthrough**:
- First 32B parameter model trained via distributed RL
- Async RL with 4-step delay tolerance
- TOPLOC verification for trustless inference

**Key Components**:
1. **prime-rl**: Open-source async distributed RL library
2. **Shardcast**: HTTP-based tree-topology model distribution
3. **TOPLOC**: Efficient verifiable inference
4. **Protocol Testnet**: P2P coordination with incentives

**Async RL Architecture**:
```
┌─────────────────┐     ┌─────────────────┐
│ Inference       │     │ Inference       │
│ Rollout Worker  │     │ Rollout Worker  │
│ (vLLM)          │     │ (vLLM)          │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
    ┌─────────────────────────────────┐
    │       TOPLOC Validators         │
    │   (verify inference results)    │
    └─────────────────────────────────┘
                    │
                    ▼
    ┌─────────────────────────────────┐
    │      GRPO Training Workers      │
    │   (update policy, broadcast)    │
    └─────────────────────────────────┘
                    │
                    ▼
              Shardcast
         (distribute new weights)
```

**Why Prime Intellect for Chrysalis**:
- Proven async RL at scale
- Consumer GPU friendly (4x RTX 3090 sufficient)
- Open-source stack (prime-rl, Shardcast)

**Citation**: [INTELLECT-2](https://www.primeintellect.ai/blog/intellect-2)

#### 6.2.4 P2PFL (Peer-to-Peer Federated Learning)

**Overview**: Decentralized federated learning without central server

**How It Works**:
1. Each node trains on local data
2. Model updates (gradients/weights) shared via gossip
3. Aggregation happens peer-to-peer
4. No node sees another's raw data

**Architecture**:
```
     Node A                Node B                Node C
   ┌────────┐            ┌────────┐            ┌────────┐
   │ Local  │            │ Local  │            │ Local  │
   │ Data   │            │ Data   │            │ Data   │
   └───┬────┘            └───┬────┘            └───┬────┘
       │                     │                     │
       ▼                     ▼                     ▼
   ┌────────┐            ┌────────┐            ┌────────┐
   │ Local  │◄──gossip──►│ Local  │◄──gossip──►│ Local  │
   │ Model  │            │ Model  │            │ Model  │
   └────────┘            └────────┘            └────────┘
       │                     │                     │
       └─────────────────────┼─────────────────────┘
                             │
                             ▼
                    Converged Global Model
```

**Best For Chrysalis**:
- Privacy-preserving training across organizations
- No single point of failure
- Works with PyTorch, TensorFlow, JAX

**Citation**: [P2PFL GitHub](https://github.com/p2pfl/p2pfl)

### 6.3 Orchestrator Architecture (Detailed)

#### 6.3.1 Design Principles
1. **Backend agnostic**: Easy to add new compute providers
2. **Job-centric**: Everything is a job with defined lifecycle
3. **Verifiable**: All results cryptographically signed
4. **Fault-tolerant**: Jobs can be retried on different backends

#### 6.3.2 Component Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                     Chrysalis Forge                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ cf-submit-  │  │ cf-check-   │  │ cf-fetch-   │         │
│  │ training    │  │ training    │  │ artifacts   │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                    Orchestrator (HTTP API)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Job Queue   │  │ Backend     │  │ Artifact    │         │
│  │             │  │ Adapters    │  │ Manager     │         │
│  └─────────────┘  └──────┬──────┘  └─────────────┘         │
└──────────────────────────┼──────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │  Akash   │     │  Tashi   │     │  Prime   │
    │  Adapter │     │  Adapter │     │ Intellect│
    └──────────┘     └──────────┘     └──────────┘
```

#### 6.3.3 Job Lifecycle

```
CREATED → QUEUED → SUBMITTED → RUNNING → COMPLETED
                                    ↓
                               [on failure]
                                    ↓
                                 FAILED → RETRY → SUBMITTED
                                    ↓
                               [max retries]
                                    ↓
                                ABANDONED
```

#### 6.3.4 Orchestrator API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/jobs` | POST | Submit new training job |
| `/jobs/:id` | GET | Get job status |
| `/jobs/:id/logs` | GET | Stream job logs |
| `/jobs/:id/artifacts` | GET | List artifacts |
| `/jobs/:id/artifacts/:name` | GET | Download artifact |
| `/jobs/:id/cancel` | POST | Cancel running job |
| `/backends` | GET | List available backends |
| `/backends/:name/health` | GET | Backend health check |

### 6.4 Training Job Spec (Full Schema)

```json
{
  "$schema": "https://chrysalis-forge.dev/schemas/training-job-v1.json",
  
  "job_id": "uuid-v4",
  "owner_did": "did:key:z6Mk...",
  "created_at": 1712345678,
  
  "job_type": "finetune | rl | eval",
  
  "base_model": {
    "name": "llama3-8b-instruct",
    "source": "huggingface",
    "revision": "main"
  },
  
  "objective": {
    "optimize_for": "success_rate",
    "task_types": ["file-edit", "vcs"],
    "target_metric": 0.90,
    "max_steps": 10000
  },
  
  "data": {
    "source": "git",
    "repo": "git@github.com:user/chrysalis-traces.git",
    "branch": "main",
    "path": "datasets/file-edit/",
    "format": "jsonl",
    "validation_split": 0.1
  },
  
  "hyperparameters": {
    "learning_rate": 1e-5,
    "batch_size": 4,
    "gradient_accumulation_steps": 8,
    "warmup_steps": 100,
    "weight_decay": 0.01
  },
  
  "resources": {
    "gpus": 1,
    "gpu_type": "a100",
    "gpu_mem_gb": 80,
    "cpus": 8,
    "ram_gb": 64,
    "storage_gb": 100,
    "max_hours": 8
  },
  
  "backend": {
    "provider": "akash",
    "region": "any",
    "max_cost_usd": 50.00
  },
  
  "artifacts": {
    "output_repo": "git@github.com:user/chrysalis-models.git",
    "output_branch": "jobs/${job_id}",
    "save_checkpoints": true,
    "checkpoint_interval_steps": 1000
  },
  
  "notifications": {
    "on_complete": "nostr:npub1...",
    "on_failure": "nostr:npub1..."
  },
  
  "signature_ed25519": "base64url..."
}
```

### 6.5 Result Integration Pipeline

After training completes:

```
1. Orchestrator commits artifacts to output_repo
   └── models/job-<id>/
       ├── model.safetensors
       ├── config.json
       ├── training_log.jsonl
       └── metrics.json

2. Chrysalis node pulls output_repo
   └── cf-fetch-artifacts --job-id <id>

3. Run standardized eval suite
   └── cf-eval --model ./models/job-<id>/ --tasks all
   └── Results written to evals.jsonl

4. If metrics beat existing agents:
   └── update-elite-registry! generates new manifest
   └── New agent marked as "finetuned derivative"
   └── Links to base_agent_id for provenance

5. Optionally auto-publish
   └── cf-export-elites --auto-publish
```
