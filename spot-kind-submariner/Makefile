.PHONY: all help create submariner kubeconfig demo \
        init plan apply inventory ansible keys \
        ssh1 ssh2 ssh3 destroy clean reset-clusters _wait-ssh _subctl-install

SSH    = ssh -i id_gcp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes
KUBE   = kubectl --kubeconfig kubeconfig.yaml
SUBCTL = PATH="$$PATH:$$HOME/.local/bin" subctl

all: help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  3 GCP VMs, 1 kind cluster per VM, linked via Submariner:"
	@echo "    create         - Deploy 3 VMs, kind clusters, install Submariner"
	@echo "    submariner     - (Re)install Submariner broker and join all clusters"
	@echo ""
	@echo "  Steps (run individually):"
	@echo "    keys           - Generate SSH keypair (id_gcp / id_gcp.pub) if missing"
	@echo "    init           - terraform init"
	@echo "    plan           - terraform plan"
	@echo "    inventory      - Generate inventory.ini from terraform outputs"
	@echo "    ansible        - Run ansible playbook"
	@echo "    kubeconfig     - Fetch and merge kubeconfigs -> kubeconfig.yaml"
	@echo "    demo           - Deploy nginx to each cluster, show pod placement"
	@echo ""
	@echo "  SSH:  ssh1  ssh2  ssh3"
	@echo ""
	@echo "  Teardown:"
	@echo "    destroy        - terraform destroy"
	@echo "    clean          - destroy + remove generated files"
	@echo "    reset-clusters - Delete kind clusters+networks on all VMs, recreate with correct Docker subnets"

# ── Deploy ────────────────────────────────────────────────────────────────────

create: keys init apply inventory ansible kubeconfig submariner

# ── SSH keys ──────────────────────────────────────────────────────────────────

keys:
	@test -f id_gcp || ssh-keygen -t ed25519 -f id_gcp -N "" -C "spot-kind-submariner"
	@echo "SSH key: id_gcp (gitignored)"

# ── Terraform ─────────────────────────────────────────────────────────────────

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply -auto-approve

# ── Inventory ─────────────────────────────────────────────────────────────────

inventory:
	@python3 -c "\
import json, subprocess; \
ext = json.loads(subprocess.check_output(['terraform','output','-json','external_ips'])); \
inn = json.loads(subprocess.check_output(['terraform','output','-json','internal_ips'])); \
lines = ['[kind_hosts]']; \
[lines.append('kind{} ansible_host={} internal_ip={}'.format(i+1,e,n)) for i,(e,n) in enumerate(zip(ext,inn))]; \
open('inventory.ini','w').write('\\n'.join(lines)+'\\n'); \
print('Generated inventory.ini for {} node(s)'.format(len(ext)))"
	@$(MAKE) --no-print-directory _wait-ssh

_wait-ssh:
	@for host in $$(terraform output -json external_ips | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)))"); do \
	  ssh-keygen -R $$host 2>/dev/null || true; \
	  echo "Waiting for SSH on $$host..."; \
	  for i in $$(seq 1 30); do \
	    if $(SSH) -o ConnectTimeout=5 laird@$$host true 2>/dev/null; then \
	      echo "  $$host: ready"; break; \
	    fi; \
	    echo "  attempt $$i/30..."; sleep 5; \
	  done; \
	done

# ── Ansible ───────────────────────────────────────────────────────────────────

ansible:
	ansible-playbook playbook.yml

# ── Kubeconfig ────────────────────────────────────────────────────────────────

kubeconfig:
	@python3 -c "\
import json, subprocess, os; \
ext = json.loads(subprocess.check_output(['terraform','output','-json','external_ips'])); \
[subprocess.run(['scp','-i','id_gcp','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=/dev/null','-o','IdentitiesOnly=yes', \
  'laird@{}:.kube/config'.format(ip),'kubeconfig-kind{}.yaml'.format(i+1)],check=True) \
  for i,ip in enumerate(ext)]; \
kc = ':'.join(['kubeconfig-kind{}.yaml'.format(i+1) for i in range(len(ext))]); \
env = {**os.environ,'KUBECONFIG':kc}; \
open('kubeconfig.yaml','wb').write(subprocess.check_output(['kubectl','config','view','--flatten'],env=env)); \
print('Merged {} kubeconfig(s) -> kubeconfig.yaml'.format(len(ext)))"
	@echo ""
	@echo "Contexts:"
	@kubectl --kubeconfig kubeconfig.yaml config get-contexts

# ── Submariner ────────────────────────────────────────────────────────────────

_subctl-install:
	@command -v subctl >/dev/null 2>&1 || \
	  (echo "Installing subctl..." && curl -Ls https://get.submariner.io | bash)

submariner: _subctl-install
	@echo "=== Deploying Submariner broker on kind1 ==="
	$(SUBCTL) deploy-broker --kubeconfig kubeconfig-kind1.yaml
	@echo "=== Joining kind1 ==="
	$(SUBCTL) join broker-info.subm \
	  --kubeconfig kubeconfig-kind1.yaml --clusterid kind1 \
	  --natt=true --cable-driver=vxlan \
	  --clustercidr 10.244.0.0/16 --servicecidr 10.96.0.0/16 \
	  --check-broker-certificate=false
	@echo "=== Joining kind2 ==="
	$(SUBCTL) join broker-info.subm \
	  --kubeconfig kubeconfig-kind2.yaml --clusterid kind2 \
	  --natt=true --cable-driver=vxlan \
	  --clustercidr 10.245.0.0/16 --servicecidr 10.97.0.0/16 \
	  --check-broker-certificate=false
	@echo "=== Joining kind3 ==="
	$(SUBCTL) join broker-info.subm \
	  --kubeconfig kubeconfig-kind3.yaml --clusterid kind3 \
	  --natt=true --cable-driver=vxlan \
	  --clustercidr 10.246.0.0/16 --servicecidr 10.98.0.0/16 \
	  --check-broker-certificate=false
	@echo "=== Waiting 60s for gateways to connect ==="
	@sleep 60
	$(SUBCTL) show connections --kubeconfig kubeconfig-kind1.yaml

# ── Reset clusters ────────────────────────────────────────────────────────────

reset-clusters:
	@echo "=== Deleting kind clusters and Docker networks on all VMs ==="
	$(eval IP1 := $(shell terraform output -json external_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[0])"))
	$(eval IP2 := $(shell terraform output -json external_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[1])"))
	$(eval IP3 := $(shell terraform output -json external_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[2])"))
	$(SSH) laird@$(IP1) "sg docker -c 'kind delete cluster --name kind1 2>/dev/null || true; docker network rm kind 2>/dev/null || true'"
	$(SSH) laird@$(IP2) "sg docker -c 'kind delete cluster --name kind2 2>/dev/null || true; docker network rm kind 2>/dev/null || true'"
	$(SSH) laird@$(IP3) "sg docker -c 'kind delete cluster --name kind3 2>/dev/null || true; docker network rm kind 2>/dev/null || true'"
	@echo "=== Recreating clusters with correct Docker subnets ==="
	$(MAKE) ansible
	$(MAKE) kubeconfig
	$(MAKE) submariner

# ── Demo ──────────────────────────────────────────────────────────────────────

demo:
	@echo "=== Contexts ==="
	@$(KUBE) config get-contexts
	@echo ""
	@for ctx in $$($(KUBE) config get-contexts -o name 2>/dev/null); do \
	  echo "--- $$ctx: nodes ---"; \
	  $(KUBE) --context $$ctx get nodes -o wide; \
	  echo ""; \
	done
	@echo "=== Deploying nginx to each cluster ==="
	@for ctx in $$($(KUBE) config get-contexts -o name 2>/dev/null); do \
	  $(KUBE) --context $$ctx delete pod demo-nginx --ignore-not-found --wait 2>/dev/null; \
	  $(KUBE) --context $$ctx run demo-nginx --image=nginx --restart=Never; \
	done
	@echo "Waiting 30s for pods..."
	@sleep 30
	@for ctx in $$($(KUBE) config get-contexts -o name 2>/dev/null); do \
	  echo "--- $$ctx: pods ---"; \
	  $(KUBE) --context $$ctx get pods -o wide; \
	  echo ""; \
	done

# ── SSH ───────────────────────────────────────────────────────────────────────

ssh1:
	$(SSH) laird@$$(terraform output -json external_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[0])")

ssh2:
	$(SSH) laird@$$(terraform output -json external_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[1])")

ssh3:
	$(SSH) laird@$$(terraform output -json external_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[2])")

# ── Teardown ──────────────────────────────────────────────────────────────────

destroy:
	terraform destroy -auto-approve

clean: destroy
	rm -f inventory.ini kubeconfig.yaml kubeconfig-kind*.yaml broker-info.subm id_gcp*
