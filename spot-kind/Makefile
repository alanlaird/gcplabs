.PHONY: all help create init plan apply inventory ansible kubeconfig demo ssh destroy clean _wait-ssh

SSH  = ssh -i id_gcp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
KUBE = kubectl --kubeconfig kubeconfig.yaml

all: help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  create         - Deploy 1 GCP VM and configure a kind cluster"
	@echo ""
	@echo "  Steps (run individually):"
	@echo "    init           - terraform init"
	@echo "    plan           - terraform plan"
	@echo "    inventory      - Generate inventory.ini from terraform outputs"
	@echo "    ansible        - Run ansible playbook"
	@echo "    kubeconfig     - Fetch kubeconfig -> kubeconfig.yaml"
	@echo "    demo           - Show nodes and deploy a test pod"
	@echo ""
	@echo "  SSH:  ssh"
	@echo ""
	@echo "  Teardown:"
	@echo "    destroy        - terraform destroy"
	@echo "    clean          - destroy + remove generated files"

# ── Deploy ────────────────────────────────────────────────────────────────────

create: init apply inventory ansible kubeconfig

# ── Terraform ─────────────────────────────────────────────────────────────────

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply -auto-approve

# ── Inventory ─────────────────────────────────────────────────────────────────

inventory:
	@EXT=$$(terraform output -raw external_ip); \
	 INN=$$(terraform output -raw internal_ip); \
	 printf '[kind_hosts]\nkind1 ansible_host=%s internal_ip=%s\n' "$$EXT" "$$INN" > inventory.ini; \
	 echo "Generated inventory.ini ($$EXT)"
	@$(MAKE) --no-print-directory _wait-ssh

_wait-ssh:
	@HOST=$$(terraform output -raw external_ip); \
	 ssh-keygen -R $$HOST 2>/dev/null || true; \
	 echo "Waiting for SSH on $$HOST..."; \
	 for i in $$(seq 1 30); do \
	   if $(SSH) -o ConnectTimeout=5 laird@$$HOST true 2>/dev/null; then \
	     echo "  $$HOST: ready"; break; \
	   fi; \
	   echo "  attempt $$i/30..."; sleep 5; \
	 done

# ── Ansible ───────────────────────────────────────────────────────────────────

ansible:
	ansible-playbook playbook.yml

# ── Kubeconfig ────────────────────────────────────────────────────────────────

kubeconfig:
	@EXT=$$(terraform output -raw external_ip); \
	 scp -i id_gcp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	   laird@$$EXT:.kube/config kubeconfig.yaml; \
	 echo ""; \
	 echo "Contexts:"; \
	 kubectl --kubeconfig kubeconfig.yaml config get-contexts

# ── Demo ──────────────────────────────────────────────────────────────────────

demo:
	@echo "=== Nodes ==="
	@$(KUBE) get nodes -o wide
	@echo ""
	@echo "=== Deploying nginx ==="
	@$(KUBE) delete pod demo-nginx --ignore-not-found --wait 2>/dev/null; \
	 $(KUBE) run demo-nginx --image=nginx --restart=Never
	@echo "Waiting 20s for pod..."
	@sleep 20
	@$(KUBE) get pods -o wide

# ── SSH ───────────────────────────────────────────────────────────────────────

ssh:
	$(SSH) laird@$$(terraform output -raw external_ip)

# ── Teardown ──────────────────────────────────────────────────────────────────

destroy:
	terraform destroy -auto-approve

clean: destroy
	rm -f inventory.ini kubeconfig.yaml kubeconfig-kind*.yaml broker-info.subm*

