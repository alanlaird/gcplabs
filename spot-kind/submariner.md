# Submariner Multi-Cluster Demo

Submariner enables direct pod-to-pod networking and cross-cluster service discovery
between the three independent kind clusters (kind1, kind2, kind3).

## Architecture

```
kind1 VM (10.138.0.x)         kind2 VM (10.138.0.x)         kind3 VM (10.138.0.x)
Docker bridge: 172.21.0.0/16  Docker bridge: 172.22.0.0/16  Docker bridge: 172.23.0.0/16
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│  kind cluster: kind1│      │  kind cluster: kind2│      │  kind cluster: kind3│
│  pods: 10.244.0.0/16│◄────►│  pods: 10.245.0.0/16│◄────►│  pods: 10.246.0.0/16│
│  svc:  10.96.0.0/16 │      │  svc:  10.97.0.0/16 │      │  svc:  10.98.0.0/16 │
│                     │      │                     │      │                     │
│  [broker namespace] │      │                     │      │                     │
│  gateway: kind1-    │      │  gateway: kind2-    │      │  gateway: kind3-    │
│  worker             │      │  worker             │      │  worker             │
└─────────────────────┘      └─────────────────────┘      └─────────────────────┘
         ▲                            ▲                            ▲
         └──── VXLAN tunnels (UDP 4500, NAT discovery UDP 4490) ──┘
```

**Networking notes:**
- Each VM uses a unique Docker bridge subnet (172.21-23.0.0/16) so gateway containers
  get unique private IPs → unique Submariner VTEP IPs (241.21-23.0.0/8 range)
- NAT is detected (`NAT: yes`) — kind containers are double-NATed: Docker bridge → GCP VM
- Ports forwarded from GCP VM `ens4` to gateway container:
  - UDP 4490: NAT discovery protocol
  - UDP 4500: VXLAN cross-cluster tunnel (`vxlan-tunnel`, dstport 4500)
  - UDP 4800: Route agent intra-cluster VXLAN (`vx-submariner`, dstport 4800)
- Gateway annotation `gateway.submariner.io/public-ip=ipv4:<internal-ip>` (v0.22 format)

## Prerequisites

```bash
make create-multi    # deploys VMs, kind clusters, and runs Submariner
# or separately:
make kubeconfig      # download kubeconfig.yaml
make submariner      # install broker + join clusters
```

Local tools required: `kubectl`, `python3`  
`subctl` is auto-installed to `~/.local/bin/` by `make submariner`.

---

## 1. Verify Cluster Status

### Connected clusters and gateways
```bash
subctl show connections --kubeconfig kubeconfig-kind1.yaml
```

Expected output (all STATUS = connected, NAT = yes):
```
GATEWAY        CLUSTER   REMOTE IP    NAT   CABLE DRIVER   SUBNETS                       STATUS      RTT avg.
kind2-worker   kind2     10.138.0.2   yes   vxlan          10.97.0.0/16, 10.245.0.0/16   connected   689µs
kind3-worker   kind3     10.138.0.4   yes   vxlan          10.98.0.0/16, 10.246.0.0/16   connected   540µs
```

### Check gateway and route-agent pods
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  get pods -n submariner-operator -o wide

kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 \
  get pods -n submariner-operator -o wide
```

### Show network CIDRs per cluster
```bash
subctl show networks --kubeconfig kubeconfig-kind1.yaml
```

---

## 2. Cross-Cluster Pod Connectivity

### Deploy a pod on kind1 and capture its IP
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  run nginx --image=nginx --restart=Never

kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  wait pod/nginx --for=condition=Ready --timeout=60s

POD_IP=$(kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  get pod nginx -o jsonpath='{.status.podIP}')
echo "nginx pod IP (kind1): $POD_IP"
```

### Ping from kind2
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 \
  run ping-test --image=busybox --restart=Never -- ping -c 3 "$POD_IP"

sleep 5
kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 logs ping-test
```

Expected:
```
3 packets transmitted, 3 packets received, 0% packet loss
```

### Ping from kind3
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind3 \
  run ping-test --image=busybox --restart=Never -- ping -c 3 "$POD_IP"

sleep 5
kubectl --kubeconfig kubeconfig.yaml --context kind-kind3 logs ping-test
```

---

## 3. Cross-Cluster Service Discovery

Submariner Lighthouse provides DNS resolution for exported services via the
`.clusterset.local` domain.

### Deploy and expose a service on kind1
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  create deployment nginx --image=nginx

kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  expose deployment nginx --port=80
```

### Export the service to all clusters
```bash
subctl export service nginx \
  --kubeconfig kubeconfig-kind1.yaml \
  --namespace default
```

### Verify the ServiceExport was created
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  get serviceexport nginx
```

```
NAME    AGE
nginx   10s
```

### Access the service from kind2
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 \
  run curl-test --image=curlimages/curl --restart=Never -- \
  curl -s --max-time 5 nginx.default.svc.clusterset.local

sleep 10
kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 logs curl-test
```

Expected: nginx welcome HTML page

### Access the service from kind3
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind3 \
  run curl-test --image=curlimages/curl --restart=Never -- \
  curl -s --max-time 5 nginx.default.svc.clusterset.local

sleep 10
kubectl --kubeconfig kubeconfig.yaml --context kind-kind3 logs curl-test
```

---

## 4. Submariner Diagnostics

### Run the built-in connectivity verification suite
```bash
subctl verify kubeconfig-kind1.yaml kubeconfig-kind2.yaml \
  --connection-attempts 3 --verbose
```

This tests: gateway connectivity, service discovery, pod-to-pod routing.

### Show endpoints advertised by each cluster
```bash
subctl show endpoints --kubeconfig kubeconfig-kind1.yaml
```

### Show all joined clusters
```bash
subctl show clusters --kubeconfig kubeconfig-kind1.yaml
```

### Check gateway logs (useful for tunnel debugging)
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  logs -n submariner-operator -l app=submariner-gateway --tail=50
```

---

## 5. Cleanup Test Resources

```bash
for ctx in kind-kind1 kind-kind2 kind-kind3; do
  kubectl --kubeconfig kubeconfig.yaml --context $ctx \
    delete pod nginx ping-test curl-test --ignore-not-found
done

kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  delete deployment nginx --ignore-not-found

kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  delete service nginx --ignore-not-found

subctl unexport service nginx \
  --kubeconfig kubeconfig-kind1.yaml --namespace default
```

---

## Troubleshooting

### Gateways show "error" instead of "connected"

Check that all Submariner UDP ports are open on the GCP firewall (4490, 4500, 4800):
```bash
gcloud compute firewall-rules describe kind-allow-submariner
```

Verify iptables DNAT rules exist on each VM:
```bash
# On kind1 VM (make ssh1)
sudo iptables -t nat -L PREROUTING -n | grep -E '4490|4500|4800'
# Should have 3 DNAT rules for the gateway container IP
```

Verify Docker port mapping is active on each VM:
```bash
# On kind1 VM (make ssh1)
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep kind1-worker
# Should show: 0.0.0.0:4490->4490/udp, 0.0.0.0:4500->4500/udp, 0.0.0.0:4800->4800/udp
```

Verify gateway node annotation (must use `ipv4:` prefix for Submariner v0.22):
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind1 \
  get node kind1-worker -o jsonpath='{.metadata.annotations}' | python3 -m json.tool
# Should include: "gateway.submariner.io/public-ip": "ipv4:10.x.x.x"
```

Check VXLAN FDB entries in gateway container (should only show VM IPs, not Docker IPs):
```bash
# On kind1 VM (make ssh1)
docker exec kind1-worker bridge fdb show dev vxlan-tunnel
# Should show: 00:00:00:00:00:00 dst 10.138.0.x (VM IPs only)
```

### Root cause: VTEP collision (same Docker bridge subnet across VMs)

If all VMs use the same Docker bridge subnet (e.g., 172.18.0.0/16), the Submariner
VTEP IP for each gateway would be identical (derived as 241.x.x.x from private IP),
causing routes to loop back to the local cluster instead of the remote one.

Fix: use `make reset-clusters` to recreate clusters with unique subnets (172.21-23.0.0/16).

### Service discovery not working

Check Lighthouse DNS pods are running:
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 \
  get pods -n submariner-operator -l app=submariner-lighthouse-coredns
```

Check that the ServiceImport was auto-created on the consuming cluster:
```bash
kubectl --kubeconfig kubeconfig.yaml --context kind-kind2 \
  get serviceimport -A
```
