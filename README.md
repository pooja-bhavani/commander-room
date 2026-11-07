# commander-room

An incident room where two AI agents do the digging, and a human still makes the call. Built with **Switch AI**

video: <VIDEO_LINK>

## The problem

When a release breaks production, the first ten minutes are messy. People paste kubectl commands into the chat, someone asks which release just went out, and nobody is sure who is allowed to roll things back.

I wanted to see if AI agents could sit in that same chat, do the slow investigation work, and still leave the risky decision to a person.

## What I built

A small incident room in Mattermost with two agents in it:

incident-inspector investigates. It runs real kubectl commands on a real Kubernetes cluster, finds why the app is failing, and tells you with proof. It can only read. It cannot change anything.
incident-release fixes. It tells you what it is about to do and waits. When you reply approve, it rolls the app back, checks the pods are healthy again, and files the incident report as a GitHub issue.

Nothing in the demo is faked. The cluster is real, the crash is real (the app runs out of memory), the rollback is real, and the report is a real GitHub issue.

## What it looks like

I ship a bad release, version 2 of a small checkout service. It loads a 300 MB cache when it starts, but its pods are only allowed 128 MB, so Kubernetes kills them again and again.

Then, in the chat:

You:                 @incident-inspector the shop checkout service looks broken after the latest release. Investigate.
incident-inspector:  The new pod is OOMKilled (exit code 137). Memory limit is 128Mi and the logs say
                     "loading price cache (300 MB)". The change came with "release v2". Proposed fix: roll back to v1.

You:                 @incident-release roll back checkout to the previous revision
incident-release:    I will roll deployment/checkout back to the previous revision. Reply "approve" to go ahead.

You:                 approve
incident-release:    Rolled back. Both pods are Ready. Incident report: <link to GitHub issue>
How it works

## Architecture

<img width="1568" height="990" alt="image" src="https://github.com/user-attachments/assets/8ee9cb1c-68a8-4cdc-9c25-896b20e15610" />

## Why Switch is the centre of it

Switch is not a side feature here. It is the room. It connects the chat to the agents, decides who an agent will answer to, starts the agent sessions, and keeps one shared conversation that both agents read. That is why the second agent knows what the first one found without me copying anything. Without Switch this would be two scripts and a bot token.

## Why it is safe

I did not want to rely only on a prompt. The limits are set in Kubernetes itself (see k8s/rbac.yaml):

Agent	What it is allowed to do
incident-inspector	Read pods, logs, events, deployments and similar things. Nothing else. It cannot read secrets.
incident-release	Read the same things, and change the checkout deployment only.

You can check it yourself:

```bash
kubectl --kubeconfig agents/inspector/kubeconfig auth can-i --list -n shop
kubectl --kubeconfig agents/release/kubeconfig auth can-i --list -n shop
```

The "wait for approve" rule is an instruction in the Release agent's prompt. It is not a lock. The permissions are the lock: even if the agent ignored its instructions, the cluster would still refuse anything outside that one deployment.

## What you need

• A Linux machine	I used an AWS EC2 t3.large (2 CPUs, 8 GB RAM) with a 30 GB disk, Ubuntu. A 2 GB machine was too small.
• Docker with the Compose plugin	Runs Switch, Mattermost and the cluster.
• kind and kubectl	The local Kubernetes cluster and its command line.
• Node 24 and pnpm	Only to build the agent controller.
• Codex CLI	npm install -g @openai/codex.

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 git gh nodejs npm
sudo usermod -aG docker $USER   # log out and back in after this
```

```bash
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 && chmod +x kind && sudo mv kind /usr/local/bin/
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

```bash
sudo npm install -g @openai/codex pnpm@10.28.2
```

The controller build needs Node 24. Install it with nvm (nvm install 24) for the build step only.

## Set it up 

1. Get this repo
```bash
git clone https://github.com/pooja-bhavani/commander-room.git
cd commander-room
```

2. Make the cluster and the broken app's healthy version
```bash
./scripts/01-cluster.sh       # creates a kind cluster called commander-room
./scripts/02-deploy-v1.sh     # deploys the healthy app and the agent permissions
./scripts/04-agent-access.sh  # makes one key file for each agent (valid for 96 hours)
kubectl -n shop get pods      # two pods, 1/1 Running
```

3. Start Switch and Mattermost
```bash
git clone https://github.com/sandbox-quantum/switch.git ~/switch
cd ~/switch
```
Create a .env file there (the Switch repo has an .env.example) and set these three lines:

SWITCH_VERSION=0.31.0
FEATURE_FLAGS_ENABLED=agent_management
CONTROLLER_TOKEN_SECRET=<any random text, 32 characters or longer>

Then start it:

```bash
docker compose -f deploy/local/standalone-docker-compose.yml \
  --profile collab --profile gateway --project-directory . up -d
curl -s http://127.0.0.1:8000/health     # should print {"status":"ok"}
```

You now have three things running:

What	Port
Switch dashboard (the gateway)	3000
Mattermost chat	8065
Switch API	8000

They only listen on the machine itself. To reach them from your laptop, open a tunnel and leave it running:

```bash
ssh -i <your-key>.pem -L 8065:127.0.0.1:8065 -L 3000:127.0.0.1:3000 -L 8000:127.0.0.1:8000 ubuntu@<machine-ip>
```

Then open http://localhost:3000 (dashboard) and http://localhost:8065 (Mattermost).

4. Build the agent controller

No ready-made release of the controller existed during the hackathon, so I built it from the Switch source with Node 24:

```bash
source ~/.nvm/nvm.sh && nvm use 24
cd ~/switch/console
pnpm install --filter @switch-console/agent-controller...
pnpm --filter "@switch-console/agent-controller^..." run build
pnpm --filter @switch-console/agent-controller run package
nvm use system
sudo npm install --global ~/switch/console/packages/agent-controller/dist-package/switch-agent-controller-*.tgz
```

5. Sign in to Codex and let it reach the cluster

6. Connect the machine to Switch

In the dashboard, open Machines, click Add machine, and copy the one-time code (it lasts 10 minutes). Then:

```bash
switch-agent-controller enroll --server http://127.0.0.1:8000 --code <the code> --name incident-box
switch-agent-controller install-service
sudo loginctl enable-linger $USER      # keeps it running after you log out
switch-agent-controller doctor         # every line should say ok
```

7. Let the Release agent file GitHub issues
```bash
gh auth login --with-token     # paste your fine-grained token, press Enter, then Ctrl+D
gh auth status
```

8. Create the two agents and the room

In the dashboard, on Machines, click New managed agent twice:

	incident-inspector	incident-release
Machine	incident-box	incident-box
Provider	Codex	Codex
Working directory	<project>/agents/inspector	<project>/agents/release
Instructions	from docs/agents/inspector.md	from docs/agents/release.md (put your own GitHub repo name in it)

Both agents should show running. Then go to Rooms, click New room, name it incident-live, choose the Mattermost bridge, add both agents, and paste the text from docs/room-instructions.md.

Open Mattermost. The incident-live channel is there with both agents.

Run the demo

1. Check everything is up

```bash
switch-agent-controller doctor
kubectl -n shop get pods
```

2. Show what each agent is allowed to do

```bash
kubectl --kubeconfig agents/inspector/kubeconfig auth can-i --list -n shop
kubectl --kubeconfig agents/release/kubeconfig auth can-i --list -n shop
```

3. Ship the bad release (the same steps are in docs/break-it-by-hand.md)

```bash
kubectl config use-context kind-commander-room
docker build --build-arg VERSION=v2 -t checkout:v2 app
kind load docker-image checkout:v2 --name commander-room
kubectl -n shop set image deployment/checkout checkout=checkout:v2
kubectl -n shop annotate deployment/checkout --overwrite \
  kubernetes.io/change-cause="release v2: preload price cache at startup"
kubectl -n shop get pods -w
```
Wait for CrashLoopBackOff, then press Ctrl+C.

4. Handle it in the chat. In incident-live, type these one at a time and wait for each answer:

@incident-inspector the shop checkout service looks broken after the latest release. Investigate.
@incident-release roll back checkout to the previous revision
approve

Under any agent reply, click Show activity to see every command it ran.

5. Check the result

```bash
kubectl -n shop get pods
kubectl -n shop rollout history deployment/checkout
```
Then open the Issues tab of this repo. The incident report is there.

6. Reset for another run

```bash
./scripts/05-reset.sh
If you stop and start the machine
```
Docker's network can go stale, and Switch and Mattermost then cannot find each other. This script fixes it without deleting any data:

```bash
./scripts/revive.sh
```
## Components

| Part | What it does | Where it runs | Port |
|---|---|---|---|
| Mattermost | The team chat where you talk to the agents | Docker, on the machine | 8065 |
| switch-core | Switch's server: keeps the rooms, decides which agent a message is for | Docker, on the machine | 8000 |
| Switch gateway | The dashboard for machines, agents and rooms | Docker, on the machine | 3000 |
| Postgres | Stores every room message | Docker, on the machine | internal |
| Agent controller | Starts the agents when they are needed | systemd service, on the machine | none |
| incident-inspector | Investigates the cluster. Can only read. | Codex, started by the controller | none |
| incident-release | Rolls back after you approve, then files the report | Codex, started by the controller | none |
| kind cluster | A real Kubernetes cluster holding the checkout app | Docker, on the machine | internal |
| GitHub | Holds the incident report as an issue | github.com | none |

## What happens to one message

| Step | What happens |
|---|---|
| 1 | You type a message in Mattermost |
| 2 | Switch reads it and works out which agent it is for |
| 3 | The agent controller starts that agent |
| 4 | The agent runs real `kubectl` commands using its own key file |
| 5 | Kubernetes checks the command against that agent's permissions |
| 6 | The answer comes back through Switch into the chat |
| 7 | After a rollback, the Release agent files the report on GitHub |

I built this for Flip the Switch Hackathon. 

License

MIT. See LICENSE.
