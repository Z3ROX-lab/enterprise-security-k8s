#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        Import Dashboard Falco dans Grafana               ║"
echo "║         Dashboard pré-configuré avec métriques            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Grafana existe
if ! kubectl get deployment -n security-siem prometheus-grafana &>/dev/null; then
    echo "❌ Grafana non trouvé"
    echo "Lancez d'abord : ./14-grafana.sh"
    exit 1
fi

echo "📋 Ce script va :"
echo "  1. Créer un dashboard Falco pré-configuré"
echo "  2. Importer le dashboard dans Grafana via l'API"
echo "  3. Dashboard avec 6 panels (alertes, erreurs, latences, etc.)"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Import annulé."
    exit 0
fi

# 1. Créer le fichier JSON du dashboard
echo ""
echo "1️⃣  Création du dashboard Falco..."

cat > /tmp/falco-dashboard.json <<'EOF'
{
  "dashboard": {
    "title": "Falco Security Alerts",
    "tags": ["falco", "security", "runtime"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "type": "timeseries",
        "title": "Taux d'alertes Falco (par seconde)",
        "targets": [
          {
            "expr": "rate(falcosidekick_inputs[5m])",
            "legendFormat": "Alertes/sec",
            "refId": "A"
          }
        ],
        "options": {
          "legend": {"displayMode": "list", "placement": "bottom"},
          "tooltip": {"mode": "single"}
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "fillOpacity": 10
            },
            "unit": "reqps"
          }
        }
      },
      {
        "id": 2,
        "gridPos": {"h": 8, "w": 6, "x": 12, "y": 0},
        "type": "stat",
        "title": "Total alertes reçues",
        "targets": [
          {
            "expr": "falcosidekick_inputs",
            "refId": "A"
          }
        ],
        "options": {
          "graphMode": "area",
          "colorMode": "value",
          "textMode": "auto"
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 100, "color": "yellow"},
                {"value": 1000, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "gridPos": {"h": 8, "w": 6, "x": 18, "y": 0},
        "type": "piechart",
        "title": "Alertes par destination",
        "targets": [
          {
            "expr": "sum by (destination) (falcosidekick_outputs)",
            "legendFormat": "{{destination}}",
            "refId": "A"
          }
        ],
        "options": {
          "legend": {"displayMode": "table", "placement": "right"},
          "pieType": "pie",
          "tooltip": {"mode": "single"}
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"}
          }
        }
      },
      {
        "id": 4,
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "type": "timeseries",
        "title": "Alertes Falco par priorité",
        "targets": [
          {
            "expr": "sum by (priority) (falco_events)",
            "legendFormat": "{{priority}}",
            "refId": "A"
          }
        ],
        "options": {
          "legend": {"displayMode": "list", "placement": "bottom"},
          "tooltip": {"mode": "multi"}
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "fillOpacity": 10
            }
          }
        }
      },
      {
        "id": 5,
        "gridPos": {"h": 8, "w": 6, "x": 12, "y": 8},
        "type": "bargauge",
        "title": "Top 5 règles Falco",
        "targets": [
          {
            "expr": "topk(5, sum by (rule) (falco_events))",
            "legendFormat": "{{rule}}",
            "refId": "A"
          }
        ],
        "options": {
          "orientation": "horizontal",
          "displayMode": "gradient",
          "showUnfilled": true
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "continuous-RdYlGn"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 100, "color": "yellow"},
                {"value": 500, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 6,
        "gridPos": {"h": 8, "w": 6, "x": 18, "y": 8},
        "type": "bargauge",
        "title": "Alertes par heure",
        "targets": [
          {
            "expr": "increase(falcosidekick_inputs[1h])",
            "legendFormat": "Dernière heure",
            "refId": "A"
          }
        ],
        "options": {
          "orientation": "horizontal",
          "displayMode": "gradient",
          "showUnfilled": true
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "continuous-GrYlRd"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 50, "color": "yellow"},
                {"value": 100, "color": "red"}
              ]
            }
          }
        }
      }
    ]
  },
  "overwrite": true
}
EOF

echo "  ✅ Dashboard JSON créé"

# 2. Port-forward Grafana (en arrière-plan)
echo ""
echo "2️⃣  Connexion à Grafana..."

# Vérifier si un port-forward existe déjà
if pgrep -f "port-forward.*grafana.*3000" > /dev/null; then
    echo "  ℹ️  Port-forward Grafana déjà actif"
else
    kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
    PF_PID=$!
    echo "  ⏳ Attente du port-forward (5 secondes)..."
    sleep 5
fi

# 3. Importer le dashboard via l'API Grafana
echo ""
echo "3️⃣  Import du dashboard dans Grafana..."

# Récupérer le mot de passe Grafana depuis le secret
GRAFANA_USER="admin"
GRAFANA_PASS=$(kubectl get secret -n security-siem prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
GRAFANA_URL="http://localhost:3000"

# Importer le dashboard
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -d @/tmp/falco-dashboard.json \
  "$GRAFANA_URL/api/dashboards/db")

# Vérifier le résultat
if echo "$RESPONSE" | grep -q '"status":"success"'; then
    DASHBOARD_URL=$(echo "$RESPONSE" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
    echo "  ✅ Dashboard importé avec succès"
    echo "  📊 URL: $GRAFANA_URL$DASHBOARD_URL"
else
    echo "  ⚠️  Erreur lors de l'import"
    echo "  Response: $RESPONSE"
fi

# 4. Nettoyer le port-forward si on l'a créé
if [ -n "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

# Nettoyer le fichier temporaire
rm -f /tmp/falco-dashboard.json

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ DASHBOARD FALCO IMPORTÉ DANS GRAFANA          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Dashboard créé avec 6 panels :"
echo "  1. 📈 Taux d'alertes Falco (par seconde)"
echo "  2. 📊 Total alertes reçues"
echo "  3. 🥧 Alertes par destination (Elasticsearch, WebUI)"
echo "  4. 🔴 Alertes Falco par priorité (Critical, Notice, etc.)"
echo "  5. 📊 Top 5 règles Falco les plus déclenchées"
echo "  6. 📊 Alertes par heure"
echo ""
echo "🖥️  Accès au dashboard :"
echo "     kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "     http://localhost:3000"
echo ""
echo "     Login : admin / admin123"
echo "     Puis : Dashboards → Falco Security Alerts"
echo ""
echo "💡 Le dashboard se rafraîchit toutes les 30 secondes automatiquement"
echo ""
echo "🔄 Pour regénérer des alertes et voir les données :"
echo "     kubectl run test-alert --image=nginx"
echo "     kubectl exec test-alert -- /bin/bash -c 'ls /etc'"
echo "     kubectl delete pod test-alert"
echo ""
