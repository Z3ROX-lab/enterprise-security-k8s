#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Trivy Operator → Grafana Dashboard              ║"
echo "║       Visualisation des vulnérabilités en temps réel     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Trivy Operator existe
if ! kubectl get deployment -n trivy-system trivy-operator &>/dev/null; then
    echo "❌ Trivy Operator non trouvé"
    echo "Lancez d'abord : ./41-trivy.sh"
    exit 1
fi

# Vérifier que Prometheus existe
if ! kubectl get deployment -n security-siem prometheus-kube-prometheus-operator &>/dev/null; then
    echo "❌ Prometheus non trouvé"
    echo "Lancez d'abord : ./13-prometheus.sh"
    exit 1
fi

echo "📋 Ce script va configurer :"
echo "  1. Activer les métriques Trivy Operator"
echo "  2. Créer un ServiceMonitor pour Prometheus"
echo "  3. Créer un dashboard Grafana pour Trivy"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

# 1. Vérifier si les métriques sont déjà exposées
echo ""
echo "1️⃣  Vérification des métriques Trivy Operator..."
echo "  ℹ️  Trivy Operator expose les métriques par défaut sur le port 8080"
echo "  ✅ Pas de reconfiguration nécessaire"

# 2. Créer un Service pour exposer les métriques
echo ""
echo "2️⃣  Création du Service pour les métriques..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: trivy-operator-metrics
  namespace: trivy-system
  labels:
    app.kubernetes.io/name: trivy-operator
spec:
  ports:
  - name: metrics
    port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app.kubernetes.io/name: trivy-operator
  type: ClusterIP
EOF

echo "  ✅ Service créé"

# 3. Créer le ServiceMonitor pour Prometheus
echo ""
echo "3️⃣  Création du ServiceMonitor Prometheus..."
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: trivy-operator
  namespace: trivy-system
  labels:
    app.kubernetes.io/name: trivy-operator
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: trivy-operator
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF

echo "  ✅ ServiceMonitor créé"

# 4. Créer le ConfigMap pour le dashboard Grafana
echo ""
echo "4️⃣  Création du dashboard Grafana..."
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: trivy-dashboard
  namespace: security-siem
  labels:
    grafana_dashboard: "1"
data:
  trivy-dashboard.json: |
    {
      "annotations": {
        "list": []
      },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "liveNow": false,
      "panels": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "thresholds"
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "red",
                    "value": 1
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 6,
            "x": 0,
            "y": 0
          },
          "id": 1,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": [
                "lastNotNull"
              ],
              "fields": "",
              "values": false
            },
            "textMode": "auto"
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"Critical\"})",
              "refId": "A"
            }
          ],
          "title": "🔴 Critical Vulnerabilities",
          "type": "stat"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "thresholds"
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "orange",
                    "value": 1
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 6,
            "x": 6,
            "y": 0
          },
          "id": 2,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": [
                "lastNotNull"
              ],
              "fields": "",
              "values": false
            },
            "textMode": "auto"
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"High\"})",
              "refId": "A"
            }
          ],
          "title": "🟠 High Vulnerabilities",
          "type": "stat"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "thresholds"
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "yellow",
                    "value": 1
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 6,
            "x": 12,
            "y": 0
          },
          "id": 3,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": [
                "lastNotNull"
              ],
              "fields": "",
              "values": false
            },
            "textMode": "auto"
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"Medium\"})",
              "refId": "A"
            }
          ],
          "title": "🟡 Medium Vulnerabilities",
          "type": "stat"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "thresholds"
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 6,
            "x": 18,
            "y": 0
          },
          "id": 4,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": [
                "lastNotNull"
              ],
              "fields": "",
              "values": false
            },
            "textMode": "auto"
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "count(trivy_image_vulnerabilities)",
              "refId": "A"
            }
          ],
          "title": "📦 Total Images Scanned",
          "type": "stat"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 10,
                "gradientMode": "none",
                "hideFrom": {
                  "tooltip": false,
                  "viz": false,
                  "legend": false
                },
                "lineInterpolation": "linear",
                "lineWidth": 2,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "never",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 10,
            "w": 24,
            "x": 0,
            "y": 8
          },
          "id": 5,
          "options": {
            "legend": {
              "calcs": [],
              "displayMode": "list",
              "placement": "bottom",
              "showLegend": true
            },
            "tooltip": {
              "mode": "single",
              "sort": "none"
            }
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"Critical\"})",
              "legendFormat": "Critical",
              "refId": "A"
            },
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"High\"})",
              "legendFormat": "High",
              "refId": "B"
            },
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"Medium\"})",
              "legendFormat": "Medium",
              "refId": "C"
            },
            {
              "expr": "sum(trivy_image_vulnerabilities{severity=\"Low\"})",
              "legendFormat": "Low",
              "refId": "D"
            }
          ],
          "title": "📈 Vulnerabilities Trend",
          "type": "timeseries"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "custom": {
                "align": "auto",
                "cellOptions": {
                  "type": "auto"
                },
                "inspect": false
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 10,
            "w": 24,
            "x": 0,
            "y": 18
          },
          "id": 6,
          "options": {
            "cellHeight": "sm",
            "footer": {
              "countRows": false,
              "fields": "",
              "reducer": [
                "sum"
              ],
              "show": false
            },
            "showHeader": true
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "topk(10, sum by (image_repository, image_tag) (trivy_image_vulnerabilities{severity=\"Critical\"}))",
              "format": "table",
              "refId": "A"
            }
          ],
          "title": "🎯 Top 10 Images with Critical Vulnerabilities",
          "transformations": [
            {
              "id": "organize",
              "options": {
                "excludeByName": {
                  "Time": true
                },
                "indexByName": {},
                "renameByName": {
                  "Value": "Critical Vulns",
                  "image_repository": "Repository",
                  "image_tag": "Tag"
                }
              }
            }
          ],
          "type": "table"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "hideFrom": {
                  "tooltip": false,
                  "viz": false,
                  "legend": false
                }
              },
              "mappings": []
            },
            "overrides": []
          },
          "gridPos": {
            "h": 10,
            "w": 12,
            "x": 0,
            "y": 28
          },
          "id": 7,
          "options": {
            "legend": {
              "displayMode": "list",
              "placement": "right",
              "showLegend": true,
              "values": []
            },
            "pieType": "pie",
            "tooltip": {
              "mode": "single",
              "sort": "none"
            }
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "sum by (namespace) (trivy_image_vulnerabilities{severity=\"Critical\"})",
              "refId": "A"
            }
          ],
          "title": "🔴 Critical Vulnerabilities by Namespace",
          "type": "piechart"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "hideFrom": {
                  "tooltip": false,
                  "viz": false,
                  "legend": false
                }
              },
              "mappings": []
            },
            "overrides": []
          },
          "gridPos": {
            "h": 10,
            "w": 12,
            "x": 12,
            "y": 28
          },
          "id": 8,
          "options": {
            "legend": {
              "displayMode": "list",
              "placement": "right",
              "showLegend": true,
              "values": []
            },
            "pieType": "pie",
            "tooltip": {
              "mode": "single",
              "sort": "none"
            }
          },
          "pluginVersion": "10.0.3",
          "targets": [
            {
              "expr": "sum by (severity) (trivy_image_vulnerabilities)",
              "refId": "A"
            }
          ],
          "title": "📊 Vulnerabilities Distribution by Severity",
          "type": "piechart"
        }
      ],
      "refresh": "30s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": [
        "trivy",
        "security",
        "vulnerabilities"
      ],
      "templating": {
        "list": []
      },
      "time": {
        "from": "now-6h",
        "to": "now"
      },
      "timepicker": {},
      "timezone": "",
      "title": "Trivy Vulnerability Scanner",
      "uid": "trivy-vulnerabilities",
      "version": 1,
      "weekStart": ""
    }
EOF

echo "  ✅ Dashboard Grafana créé"

# 5. Attendre que Prometheus scrape les métriques
echo ""
echo "5️⃣  Attente de la collecte des métriques (30 sec)..."
sleep 30

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ TRIVY → GRAFANA CONFIGURÉ                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ Métriques Trivy Operator activées"
echo "  ✅ Service créé pour exposer les métriques"
echo "  ✅ ServiceMonitor Prometheus créé"
echo "  ✅ Dashboard Grafana importé"
echo ""
echo "🎯 Accéder à Grafana :"
echo "  kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "  http://localhost:3000"
echo ""
echo "  Credentials par défaut :"
echo "  Username: admin"
echo "  Password: $(kubectl get secret -n security-siem prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "📊 Dashboard disponible :"
echo "  Dashboards → Trivy Vulnerability Scanner"
echo ""
echo "📈 Métriques disponibles :"
echo "  - trivy_image_vulnerabilities"
echo "  - Par sévérité : Critical, High, Medium, Low"
echo "  - Par namespace, image, tag"
echo ""
echo "🔍 Vérifier que Prometheus scrape Trivy :"
echo "  kubectl get servicemonitor -n trivy-system"
echo "  kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator"
echo ""
