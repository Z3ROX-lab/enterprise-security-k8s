#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Falco Tuning - Réduction des faux positifs      ║"
echo "║     Filtrer les alertes normales des outils de monitoring║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script va créer des règles Falco personnalisées pour :"
echo "  - Exclure les alertes des namespaces de confiance (security-siem, trivy-system, kube-system)"
echo "  - Réduire le bruit de ~2000 alertes/h → ~50-100 alertes pertinentes/h"
echo "  - Garder uniquement les alertes suspectes sur les workloads applicatifs"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Tuning annulé."
    exit 0
fi

echo ""
echo "1️⃣  Création des règles Falco personnalisées..."

# Créer une ConfigMap avec des règles custom qui ajoutent des exceptions
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-rules-custom
  namespace: security-detection
  labels:
    app: falco
data:
  custom-rules.yaml: |
    # ========================================================================
    # Falco Custom Rules - Réduction des faux positifs
    # ========================================================================

    # Liste des namespaces de confiance (monitoring, sécurité, système)
    - list: trusted_namespaces
      items: [kube-system, kube-public, kube-node-lease, security-siem, security-detection, trivy-system, monitoring]

    # Liste des images de confiance
    - list: trusted_images
      items:
        - docker.io/grafana/grafana
        - quay.io/prometheus/prometheus
        - docker.elastic.co/elasticsearch/elasticsearch
        - docker.elastic.co/kibana/kibana
        - ghcr.io/aquasecurity/trivy
        - docker.io/aquasec/trivy

    # ========================================================================
    # Override: Contact K8S API Server From Container
    # Cette règle génère beaucoup de bruit pour Grafana, Prometheus, Trivy
    # ========================================================================
    - rule: Contact K8S API Server From Container
      desc: Detect attempts to contact the K8S API Server from a container (filtered for trusted namespaces)
      condition: >
        evt.type=connect and
        evt.dir=< and
        (fd.typechar=4 or fd.typechar=6) and
        container and
        k8s.ns.name != "" and
        not k8s.ns.name in (trusted_namespaces) and
        not container.image.repository in (trusted_images) and
        fd.sip="127.0.0.1" and
        fd.sport=443
      output: >
        Unexpected connection to K8S API Server from container
        (user=%user.name user_loginuid=%user.loginuid %container.info
        image=%container.image.repository:%container.image.tag
        connection=%fd.name container_id=%container.id)
      priority: NOTICE
      tags: [network, k8s, container, mitre_discovery]
      append: false

    # ========================================================================
    # Override: Drop and execute new binary in container
    # Filtrer les namespaces de build/scan (Trivy)
    # ========================================================================
    - rule: Drop and execute new binary in container
      desc: Detect if an executable not in base image is executed (filtered for trusted namespaces)
      condition: >
        spawned_process and
        container and
        proc.is_exe_upper_layer=true and
        not proc.name in (known_binaries) and
        not k8s.ns.name in (trusted_namespaces)
      output: >
        Executing binary not in base image
        (user=%user.name user_loginuid=%user.loginuid process=%proc.cmdline file=%proc.exe
        container_id=%container.id image=%container.image.repository:%container.image.tag)
      priority: CRITICAL
      tags: [process, container, mitre_execution]
      append: false

    # ========================================================================
    # Override: Redirect STDOUT/STDIN to Network Connection in Container
    # Filtrer les connexions réseau normales des CNI (Calico, Flannel)
    # ========================================================================
    - rule: Redirect STDOUT/STDIN to Network Connection in Container
      desc: Detect redirecting stdout/stdin to network connection in container (filtered for CNI and trusted namespaces)
      condition: >
        dup and
        container and
        evt.rawres>=0 and
        fd.typechar in (4, 6) and
        not proc.name in (shell_binaries) and
        not k8s.ns.name in (trusted_namespaces) and
        not k8s.pod.name startswith "calico-node" and
        not k8s.pod.name startswith "kube-proxy"
      output: >
        Redirect stdout/stdin to network connection
        (user=%user.name user_loginuid=%user.loginuid %container.info process=%proc.cmdline
        terminal=%proc.tty container_id=%container.id image=%container.image.repository fd.name=%fd.name)
      priority: NOTICE
      tags: [network, process, container, mitre_exfiltration]
      append: false

    # ========================================================================
    # Nouvelle règle : Alerter uniquement sur les namespaces applicatifs
    # ========================================================================
    - rule: Suspicious Activity in Application Namespace
      desc: Activity suspecte détectée dans un namespace applicatif (hors monitoring/système)
      condition: >
        spawned_process and
        container and
        not k8s.ns.name in (trusted_namespaces) and
        (proc.name in (shell_binaries) or
         proc.name in (network_tools) or
         proc.name in (system_tools))
      output: >
        ALERT: Activité suspecte dans namespace applicatif
        (namespace=%k8s.ns.name pod=%k8s.pod.name container=%container.name
        process=%proc.cmdline user=%user.name image=%container.image.repository:%container.image.tag)
      priority: WARNING
      tags: [process, container, security, application]

    # ========================================================================
    # Liste des binaires shell
    # ========================================================================
    - list: shell_binaries
      items: [bash, sh, zsh, ksh, csh, tcsh, fish, dash]

    - list: network_tools
      items: [nc, netcat, ncat, nmap, curl, wget, telnet, ftp, ssh, scp]

    - list: system_tools
      items: [ps, top, htop, lsof, strace, tcpdump, wireshark]

    - list: known_binaries
      items: [ls, cat, grep, sed, awk, find, head, tail, echo]
EOF

echo "  ✅ ConfigMap 'falco-rules-custom' créée"

echo ""
echo "2️⃣  Mise à jour du Helm release Falco pour charger les règles custom..."

# Vérifier si le fichier values existe
if [ ! -f "/tmp/falco-values-tuned.yaml" ]; then
    # Créer un fichier values pour activer les règles custom
    cat > /tmp/falco-values-tuned.yaml <<'EOF'
# Configuration Falco avec règles custom
customRules:
  custom-rules.yaml: |-
    # Les règles custom sont chargées depuis la ConfigMap falco-rules-custom

# Monter la ConfigMap avec les règles custom
extraVolumes:
  - name: falco-rules-custom
    configMap:
      name: falco-rules-custom

extraVolumeMounts:
  - name: falco-rules-custom
    mountPath: /etc/falco/rules.d
    readOnly: true

# Activer le chargement des règles custom
falco:
  rulesFile:
    - /etc/falco/falco_rules.yaml
    - /etc/falco/falco_rules.local.yaml
    - /etc/falco/rules.d/custom-rules.yaml
EOF
fi

echo "  ℹ️  Fichier de configuration créé"
echo "  ⚠️  IMPORTANT: Pour appliquer ces règles, vous devez mettre à jour Falco :"
echo ""
echo "     helm upgrade falco falcosecurity/falco \\"
echo "       --namespace security-detection \\"
echo "       --reuse-values \\"
echo "       -f /tmp/falco-values-tuned.yaml"
echo ""

read -p "Voulez-vous appliquer la mise à jour maintenant ? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "3️⃣  Mise à jour de Falco avec les règles custom..."

    helm upgrade falco falcosecurity/falco \
      --namespace security-detection \
      --reuse-values \
      -f /tmp/falco-values-tuned.yaml

    echo "  ✅ Falco mis à jour"

    echo ""
    echo "4️⃣  Redémarrage des pods Falco..."
    kubectl rollout restart daemonset -n security-detection falco

    echo "  ⏳ Attente du redémarrage (30 secondes)..."
    sleep 30

    echo "  ✅ Pods Falco redémarrés"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          ✅ FALCO TUNING CONFIGURÉ                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Règles custom créées :"
echo "  ✅ Contact K8S API Server → Filtré pour security-siem, trivy-system, kube-system"
echo "  ✅ Drop and execute binary → Filtré pour namespaces de confiance"
echo "  ✅ Redirect STDOUT/STDIN → Filtré pour CNI (Calico, kube-proxy)"
echo "  ✅ Nouvelle règle : Alertes sur namespaces applicatifs uniquement"
echo ""
echo "🎯 Résultat attendu :"
echo "  Avant : ~2000 alertes/h (beaucoup de bruit)"
echo "  Après : ~50-100 alertes/h (uniquement activités suspectes réelles)"
echo ""
echo "📈 Vérifier dans Grafana (après 5-10 minutes) :"
echo "  kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "  http://localhost:3000 → Dashboard Falco Security Alerts"
echo "  Le panel 'Alertes par heure' devrait montrer beaucoup moins d'alertes"
echo ""
echo "🔍 Vérifier dans Kibana :"
echo "  kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
echo "  http://localhost:5601 → Discover → Data View: Falco Alerts"
echo "  Vous devriez voir principalement des alertes sur des namespaces non-système"
echo ""
echo "💡 Namespaces filtrés (considérés de confiance) :"
echo "  - kube-system, kube-public, kube-node-lease"
echo "  - security-siem (Grafana, Prometheus, Elasticsearch, Kibana)"
echo "  - security-detection (Falco, Falcosidekick)"
echo "  - trivy-system (Scans de vulnérabilités)"
echo "  - monitoring"
echo ""
echo "⚙️  Pour ajuster le tuning :"
echo "  1. Modifier la ConfigMap: kubectl edit cm falco-rules-custom -n security-detection"
echo "  2. Redémarrer Falco: kubectl rollout restart daemonset falco -n security-detection"
echo ""
