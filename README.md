# commander-room

An automated, human-in-the-loop Incident Command Room built with **Switch AI**

[![Interactive Switch Demo](./demo.gif)](https://codepen.io/Pooja-Bhavani/pen/01a1b5cc-ce34-74fa-b113-1201691e707d)

When a release breaks production, two agents handle it in a chat room:

- **incident-inspector** reads the real cluster (pods, logs, events, rollout history) and posts the cause with the exact evidence. It cannot change anything.
- **incident-release** proposes the fix and changes nothing until the owner replies `approve`. Then it rolls back, checks the pods, and files the incident report as a GitHub issue.

Everything in the demo is real: a real Kubernetes cluster, a real crash (OOMKilled), a real rollback, a real GitHub issue.

Demo video: `<VIDEO_LINK>`

## How the pieces fit

```
you in Mattermost chat
        |
      Switch  (room, addressing, agent sessions)
        |
   +----+-----------------+
   |                      |
incident-inspector   incident-release
(read-only)          (one deployment only, after approval)
   |                      |
   +------ Kubernetes (kind) ------+
                                  |
                        GitHub issue (incident report)
```

- **Mattermost** is the team chat. It ships with the self-hosted Switch stack.
- **Switch** puts the agents in the room so they read the conversation and answer in it.
- **Agents** run with Codex, started on a machine by the Switch agent controller.
- **The app** (`app/`) is a small checkout service. `v1` is healthy. `v2` preloads a 300 MB price cache into pods limited to 128Mi, so the kernel kills it at startup.

## Safety

The limits are enforced by Kubernetes, not only by prompts (`k8s/rbac.yaml`):

| Agent | Allowed on the cluster |
|---|---|
| incident-inspector | `get`, `list`, `watch` on pods, pod logs, events, services, endpoints, deployments, replicasets. No secrets. |
| incident-release | `get` and `patch` on the `checkout` deployment only, plus read access to pods, events and replicasets. |

Check it yourself:

```bash
kubectl --kubeconfig agents/inspector/kubeconfig auth can-i --list -n shop
kubectl --kubeconfig agents/release/kubeconfig   auth can-i --list -n shop
```

The Release agent is instructed to act only after an explicit `approve` from the owner (`docs/agents/release.md`).

### Known limits

- The two agents run as the same Linux user on one machine. A prompt tells each agent to stay in its own directory, but nothing at the OS level stops the Inspector from reading the Release agent's kubeconfig. Separate agent users (`install-service --separate-users` in the controller) would close this. Not done here.
- The `gh` login used to file the report is shared by both agents. It is a fine-grained token limited to this repository's issues.
- The agents use Codex on a free ChatGPT sign-in, which has limited usage.
- No Switch controller release was published during the event, so the controller was built from the Switch source.

## Run it yourself

You need Docker, `kind`, `kubectl`, Node 24 (to build the controller) and a Codex sign-in.

**1. The cluster**

```bash
./scripts/01-cluster.sh      # kind cluster "commander-room"
./scripts/02-deploy-v1.sh    # healthy checkout:v1 and the RBAC roles
./scripts/04-agent-access.sh # writes agents/inspector/kubeconfig and agents/release/kubeconfig
```

**2. Switch (self-hosted)**

Clone `sandbox-quantum/switch`, then in its `.env` set `SWITCH_VERSION=0.31.0`, `FEATURE_FLAGS_ENABLED=agent_management` and a `CONTROLLER_TOKEN_SECRET` of at least 32 characters. Start it:

```bash
docker compose -f deploy/local/standalone-docker-compose.yml \
  --profile collab --profile gateway --project-directory . up -d
```

The gateway is on port 3000, Mattermost on 8065 and the Switch API on 8000.

**3. The agent controller**

Build it from the Switch checkout (`console/`) with Node 24:

```bash
pnpm install --filter @switch-console/agent-controller...
pnpm --filter "@switch-console/agent-controller^..." run build
pnpm --filter @switch-console/agent-controller run package
npm install --global console/packages/agent-controller/dist-package/switch-agent-controller-*.tgz
```

In the gateway, open Machines, then Add machine, and enroll:

```bash
switch-agent-controller enroll --server http://127.0.0.1:8000 --code <code> --name incident-box
switch-agent-controller install-service
codex login --device-auth
```

**4. Agents and room**

In the gateway, Machines, New managed agent: create the two agents with the settings in `docs/agents/`. Then Rooms, New room: `incident-live`, bridge Mattermost, both agents, instructions from `docs/room-instructions.md`.

**5. Run the incident**

Break the service by hand (`docs/break-it-by-hand.md`), then in the room:

```
@incident-inspector the shop checkout service looks broken after the latest release. Investigate.
@incident-release roll back checkout to the previous revision
approve
```

## Layout

```
app/        checkout service v1 (healthy) and v2 (OOMs under the 128Mi limit)
k8s/        namespace, deployment, RBAC roles for the two agents
scripts/    cluster, deploy, agent kubeconfig and reset scripts
docs/       agent instructions, room instructions, manual break steps
```

## Built during the hackathon

Written during Flip the Switch (Nov 2026). I used Claude as an AI assistant for planning, scripts and debugging.

## License

MIT, see `LICENSE`.
